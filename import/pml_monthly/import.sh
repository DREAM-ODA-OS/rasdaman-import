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

# include import data coin_fileiguration and utility functions
. $IMPORT_SCRIPT_DIR/import.cfg

import_var=Rrs_510

# ----------------------------------------------------------------------------
# import initialization
# ----------------------------------------------------------------------------

check_rasdaman
check_gdal
check_nco

# update coll/cov lists
update_covs
update_colls

initcolls()
{
for c in $COLLS; do
  logn "initializing collection $c... "
  $RASQL -q "create collection $c $SET_TYPE" > /dev/null
  feedback

  logn "initializing object... "
  local tiling="tiling regular [0:63,0:63,0:3] tile size $((64*64*4 * 4))"
  $RASQL -q "insert into $c values marray x in [0:0,0:0,0:0] values (float)0 $tiling" > /dev/null
  feedback
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

update_query()
{
  $RASQL -q "update $c as m set m[0:*,0:*,$month] assign (float)inv_tiff(\$1)" -f $f > /dev/null
}

importras()
{
pushd $DATADIR > /dev/null

for c in $COLLS; do
  check_collection "$c" "collection $c not found, please initialize the import."
  
  log "importing $c"
  
  month=0
  for year in *; do
  
    [ -d "$year" ] || continue
    pushd "$year" > /dev/null
  
    for in_file in *.nc; do
    
      logn "month $month: translating NetCDF file to GTiff... "
      f="$TMP_DIR/$in_file.tiff"
      tmp_f="$TMP_DIR/tmp.nc"
      ncks -C -v $import_var "$in_file" "$tmp_f" > /dev/null
      gdal_translate -of GTiff -q "$tmp_f" "$f" > /dev/null 2>&1
      if [ $? -ne 0 ]; then
        echo failed.
        continue
      else
        echo -n "ok. "
      fi
      
      echo -n "importing to rasdaman... "
      run_rasql_query update_query
      
      month=$(($month + 1))
      
      rm -f "$f" "$tmp_f"
    done
    
    popd > /dev/null
  done
  
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

# ----------------------------------------------------------------------------
# actual work
# ----------------------------------------------------------------------------

initcolls
importras
#importpet

log "done."
