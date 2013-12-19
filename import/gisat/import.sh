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

# update coll/cov lists
COVS="$COLLS"
update_covs
update_colls

# read rasdl types from types.dl file
read_types

initcolls()
{
for c in $COLLS; do
  logn "initializing collection $c with $SET_TYPE<$MDD_TYPE<$BASE_TYPE>>... "
  $RASQL -q "create collection $c $SET_TYPE" > /dev/null
  feedback

  logn "initializing object... "
  local x=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $1; }')
  local y=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $2; }')
  $RASQL -q "insert into $c values marray x in [$x:$x,$y:$y,$t:$t] values {0c,0c,0c,0c,0c}" > /dev/null || exit $RC_ERROR
  feedback
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

update_query()
{
  $RASQL -q "update $c as m set m[*:*, *:*, $t] assign shift(inv_tiff(\$1), $pixel_shift)" -f $f > /dev/null || exit
}

importras()
{
pushd $DATADIR > /dev/null

for c in $COLLS; do
  log "importing $c"
  for archive in *.tar.gz; do
    tar xzf "$archive" || continue
    d=$(echo "$archive" | sed 's/.tar.gz//')
    [ -d "$d" ] || continue
    
    pushd "$d" > /dev/null
    
    for f in *.tif; do
      [ -f "$f" ] || continue
      
      t=`echo $f | awk -F '_' '{ print $3; }'`
      pixel_shift=$(compute_pixel_shift $f)
      
      check_coll "$c"
      [ $? -ne 0 ] && initcolls
      
      logn " importing $f, shift $pixel_shift, slice $t... "
      run_rasql_query update_query
      update_geo_bbox
    done
    
    popd > /dev/null
    rm -rf "$d"
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

importras
importpet

log "done."
