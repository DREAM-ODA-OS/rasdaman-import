#!/bin/bash
# ----------------------------------------------------------------------------
# Description   Script to drop data from rasdaman and petascope
# Dependencies  rasdaman, postgres
#
# Date          2013-mar-16
# Author        Dimitar Misev
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# script initialization
# ----------------------------------------------------------------------------

# script name
PROG=`basename $0`

# determine script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
IMPORT_SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# include import data configuration and utility functions
. $IMPORT_SCRIPT_DIR/import.cfg

# ----------------------------------------------------------------------------
# work
# ----------------------------------------------------------------------------

COLLS=
for f in $TIMESTAMPS_DIR/*; do
  f=$(basename $f)
  mask=$(mask_coll $f)
  if [ -n "$COLLS" ]; then
    COLLS="$COLLS $f $mask"
  else
    COLLS="$f $mask"
  fi
done

drop_colls
drop_petascope
drop_types

rm -f $TIMESTAMPS_DIR/*

log "done."
