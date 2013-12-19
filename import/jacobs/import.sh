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
COVS=jacobs
update_covs
update_colls

# read rasdl types from types.dl file
read_types

initcolls()
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

insert_query()
{
  $RASQL -q "insert into $c values inv_tiff(\$1)" -f $f > /dev/null
}

importras()
{
pushd $DATADIR > /dev/null

for c in $COLLS; do
  logn "importing $c... "
  f=$c.tif
  run_rasql_query insert_query
done

popd > /dev/null
}

# ----------------------------------------------------------------------------
# import data to petascope
# ----------------------------------------------------------------------------

importpet()
{
for c in $COVS; do
  import_petascope "$c" "$axes_names" "$CRS"
done
}

importwms()
{
compile_wms
for c in $COVS; do
  log "importing $c as a WMS service."
  $INIT_WMS "$c"_wms $c $CRS -h $PS_HOST -p 8080
  $FILL_WMS $c
done
}

# ----------------------------------------------------------------------------
# actual work
# ----------------------------------------------------------------------------

initcolls
importras
importpet
#importwms

log "done."
