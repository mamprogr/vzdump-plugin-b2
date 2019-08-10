#!/bin/bash
CONFIG_FILE=$(dirname $0)/upload-b2.config

. "$CONFIG_FILE"

if [ ! -r "$CONFIG_FILE" ] ; then
  echo "Where is my config file? Looked in $CONFIG_FILE."
  echo "If you have none, copy the template and enter your information."
  echo "If it is somewhere else, change the second line of this script."
  exit 1
fi
if [ ! -x "$B2_BINARY" ] || [ ! -x "$JQ_BINARY" ] ; then
  echo "Missing one of $B2_BINARY or $JQ_BINARY."
  echo "Or one of the binaries is not executable."
  exit 2
fi

# Eliminate duplicate slashes. B2 does not accept those in file paths.
TARFILE=$(sed 's#//#/#g' <<< "$TARFILE")
TARBASENAME=$(basename "$TARFILE")
VMID=$3
SECONDARY=${SECONDARY_STORAGE:-`pwd`}


echo "PHASE: $1"
echo "MODE: $2"
echo "VMID: $3"
echo "VMTYPE: $VMTYPE"
echo "DUMPDIR: $DUMPDIR"
echo "HOSTNAME: $HOSTNAME"
echo "TARFILE: $TARFILE"
echo "TARBASENAME: $TARBASENAME"
echo "LOGFILE: $LOGFILE"
echo "USER: `whoami`"
echo "SECONDARY: $SECONDARY"

if [ ! -d "$SECONDARY" ] ; then
  echo "Missing secondary storage path $SECONDARY. Got >$SECONDARY_STORAGE< from config file."
  exit 12
fi

if [ "$1" == "backup-end" ]; then
  if [ ! -f $TARFILE ] ; then
    echo "Where is my tarfile?"
    exit 3
  fi

  echo "CHECKSUMMING whole tar."
  sha1sum -b "$TARFILE" >> "$TARFILE.sha1sums"
  if [ $? -ne 0 ] ; then
    echo "Something went wrong checksumming."
    exit 4
  fi

  echo "SPLITTING into chunks sized <=$B2_SPLITSIZE_BYTE byte"
  cd "$DUMPDIR"
  time split --bytes=$B2_SPLITSIZE_BYTE --suffix-length=3 --numeric-suffixes "$TARBASENAME" "$SECONDARY/$TARBASENAME.split."
  if [ $? -ne 0 ] ; then
    echo "Something went wrong splitting."
    exit 5
  fi

  echo "CHECKSUMMING splits"
  cd "$SECONDARY"
  sha1sum -b $TARBASENAME.split.* >> "$DUMPDIR/$TARBASENAME.sha1sums"
  if [ $? -ne 0 ] ; then
    echo "Something went wrong checksumming."
    exit 6
  fi

  echo "Deleting whole file"
  rm "$TARFILE"

  echo "AUTHORIZING AGAINST B2"
  $B2_BINARY authorize_account $B2_ACCOUNT_ID $B2_APPLICATION_KEY
  if [ $? -ne 0 ] ; then
    echo "Something went wrong authorizing."
    exit 9
  fi

  echo "UPLOADING to B2 with up to $NUM_PARALLEL_UPLOADS parallel uploads."
  ls -1 $TARFILE.sha1sums $TARFILE.split.* | xargs --verbose -I % -n 1 -P $NUM_PARALLEL_UPLOADS $B2_BINARY upload_file $B2_BUCKET "%" "$B2_PATH%"
  if [ $? -ne 0 ] ; then
    echo "Something went wrong uploading."
    exit 10
  fi

  echo "Deleting cleartext splits"
  rm $SECONDARY/$TARBASENAME.split.*

fi
