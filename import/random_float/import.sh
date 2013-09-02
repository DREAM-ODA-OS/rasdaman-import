#!/bin/bash
# ----------------------------------------------------------------------------
# Description   Script to import data to rasdaman and petascope
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
# import initialization
# ----------------------------------------------------------------------------

# check dependencies
check_rasdaman

# update coll/cov lists
update_covs
update_colls

# read rasdl types from types.dl file
read_types

function initcolls()
{
for c in $COLLS; do
  logn "initializing collection $c... "
  $RASQL -q "create collection $c $SET_TYPE" > /dev/null
  feedback
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

function insert_query()
{
  $RASQL -q "insert into $c values \$1" -f $f --mddtype "$MDD_TYPE" --mdddomain "[0:$X,0:$Y]" > /dev/null
}

function importras()
{
pushd $DATADIR > /dev/null

for c in $COLLS; do
  logn "importing $c... "
  f=512x512.bin
  run_rasql_query insert_query
done

popd > /dev/null
}

# ----------------------------------------------------------------------------
# actual work
# ----------------------------------------------------------------------------

initcolls
importras


log "done."
