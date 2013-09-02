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

  logn "initializing object... "
  $RASQL -q "insert into $c values marray i in [0:0,0:0,0:0] values {0c,0c,0c} tiling aligned [0:$X,0:$Y,0:0] tile size $((($X+1)*($Y+1)*3)) index rpt_index" > /dev/null
  feedback
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

function update_query()
{
  $RASQL -q "update $c as a set a[*:*, *:*, $count] assign (char) inv_png(\$1)" -f $f > /dev/null
}

function importras()
{
pushd $DATADIR > /dev/null

for c in $COLLS; do
  log "importing $c"
  echo

  count=0
  for f in `ls a_vm* |sort -n -t m -k 2`
  do
    logn "slice $count / $H ... "
    run_rasql_query update_query
    count=$((count+1))
  done;

done

popd > /dev/null
}

# ----------------------------------------------------------------------------
# import data to petascope
# ----------------------------------------------------------------------------

function importpet()
{
for c in $COVS; do
  import_petascope "$c" "$axes_names" "$CRS"
done
}

# ----------------------------------------------------------------------------
# actual work
# ----------------------------------------------------------------------------

initcolls
importras
importpet

log "done."
