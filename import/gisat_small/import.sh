#!/bin/bash
# ----------------------------------------------------------------------------
# Description   Script to import data to rasdaman and petascope
# Dependencies  rasdaman, postgres
#
# Date          2013-dec-16
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

# read rasdl types from types.dl file
read_types

initcolls()
{
  local c="$1"
  check_coll "$c"
  if [ $? -ne 0 ]; then
    local set_type=$SET_TYPE
    [ "$c" != "$GISAT_COLL" ] && set_type="GreySet3"
    logn "initializing collection $c with $set_type>... "
    $RASQL -q "create collection $c $set_type" > /dev/null
    feedback
  fi
  
  coll_empty "$c"
  if [ $? -eq 0 ]; then
    logn "initializing object... "
    local x=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $1; }')
    local y=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $2; }')
    local init_val="{0c,0c,0c}"
    [ "$c" != "$GISAT_COLL" ] && init_val="0c"
    $RASQL -q "insert into $c values marray x in [$x:$(($x + $X)),$y:$(($y + $Y)),0:0] values $init_val" > /dev/null || exit $RC_ERROR
    feedback
  fi
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

update_query()
{
  pixel_shift=$(compute_pixel_shift $f)
  initcolls $c
  logn " importing $f, shift $pixel_shift, slice $pixel_t... "
  $RASQL -q "update $c as m set m[*:*, *:*, $pixel_t] assign shift(inv_tiff(\$1), $pixel_shift)" -f $f > /dev/null || exit
  rc=$?
  update_geo_bbox "$f"
  return $rc
}

importras()
{
  for pixel_t in $(seq 0 7); do
    for c in $COLLS; do
      f=$c$(($pixel_t + 1)).tif
      run_rasql_query update_query
    done
  done
}

# ----------------------------------------------------------------------------
# import data to petascope
# ----------------------------------------------------------------------------

importpet()
{
for c in $COLLS; do
  check_petascope_cov "$c"
  if [ $? -ne 0 ]; then
    import_petascope "$c" "$axes_names" "$CRS"
  else
    update_petascope "$c" "$axes_names"
  fi
done
}

# ----------------------------------------------------------------------------
# actual work
# ----------------------------------------------------------------------------

pushd "$DATADIR" > /dev/null

initcolls
importras
importpet

popd > /dev/null

log "done."
