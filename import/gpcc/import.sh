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
  $RASQL -q "insert into $c values marray x in [0:0,0:0,0:0] values (float)0 tiling aligned [0:0,0:$(($Y-1)),0:$(($X-1))] tile size $(($X*$Y*4))" > /dev/null
  feedback
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

function importras()
{
pushd $TMP_DIR > /dev/null

for c in $COLLS; do
  check_collection "$c" "collection $c not found, please initialize the import."
  
  log "importing $c"
  
  gzipped="$DATADIR/full_data_v6_precip_05.nc.gz"
  f="data.nc"
  if [ ! -f "$gzipped" ]; then
    error "data not found: $gzipped"
  fi
  
  logn "unzipping $gzipped... "
  gunzip -c "$gzipped" > $f
  if [ -f $f ]; then
    echo ok.
  else
    echo failed.
    exit $RC_ERROR
  fi
  
  logn "flipping NetCDF file on the Y axis... "
  ncpdq -O -h -a -lon $f tmp.nc
  if [ $? -ne 0 ]; then
    echo "failed."
  else
    echo "ok."
    mv tmp.nc $f

    # import in 10 year increments (120 months)
    increment=0
    month=0
    while [ $month -lt $T ]; do
      
      logn "extracting $month / $T months... "
      ncks -O -d time,$month,$month $f tmp.nc > /dev/null
      feedback

      ncdump tmp.nc | sed 's/float p(time, /float p(/' | ncgen -o tmp2.nc
      mv tmp2.nc tmp.nc

      logn "importing NetCDF file to rasdaman... "
      $RASQL -q "update $c as m set m[$month,0:*,0:*] assign (float)inv_netcdf(\$1, \"vars=p\")" -f tmp.nc > /dev/null
      feedback
      
      month=$(($month + 1))

      # cleanup
      rm -f tmp.nc
    done
    
  fi
  
  # cleanup
  rm -f $f tmp.nc

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
