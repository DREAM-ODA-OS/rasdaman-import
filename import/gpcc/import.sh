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

check_rasdaman
check_gdal

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
  $RASQL -q "insert into $c values marray x in [0:0,0:0,0:0] values (float)0 tiling aligned [0:0,0:$(($X-1)),0:$(($Y-1))] tile size $(($X*$Y*4))" > /dev/null
  feedback
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

function update_query()
{
  $RASQL -q "update $c as m set m[$month,0:*,0:*] assign (float)inv_tiff(\$1)" -f $f > /dev/null
}

function importras()
{
pushd $DATADIR > /dev/null

for c in $COLLS; do
  check_collection "$c" "collection $c not found, please initialize the import."
  
  log "importing $c"
  
  month=0
  for nf in *.nc; do
    logn "$nf: "
    echo -n "translating NetCDF file to GTiff... "
    f="$TMP_DIR/$nf.tiff"
    gdal_translate -of GTiff -q "$nf" "$f"
    if [ $? -ne 0 ]; then
      echo failed.
      continue
    else
      echo -n "ok. "
    fi
    
    echo -n "importing to rasdaman... "
    run_rasql_query update_query
    
    month=$(($month + 1))
    
    rm -f "$f"
  done
  
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
