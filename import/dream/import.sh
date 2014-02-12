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

RASTERIZE="$IMPORT_SCRIPT_DIR/rasterize.py"

#
# Parse XML DOM
#
read_dom () {
  local IFS=\>
  read -d \< ENTITY CONTENT
}
parse_dom() {
  if [[ $ENTITY = "gml:beginPosition" ]] ; then
    timestamp=$CONTENT
  fi
}

# ----------------------------------------------------------------------------
# import initialization
# ----------------------------------------------------------------------------

# check dependencies
check_rasdaman
check_gdal

create_coll()
{
  local c="$1"
  local data_file="$2"
  
  # 1. get collection/mdd type
  get_types $(python $GETTYPE "$data_file" 3 "$c" "$TMP_DIR" 2>/dev/null)
  [ -f "$TMP_DIR/$c.init" ] || error "failed to compute initialization value"
  [ -f "$TMP_DIR/$c.dl" ]   && read_types_from "$TMP_DIR/$c.dl"
  local init_val=$(head -n 1 "$TMP_DIR/$c.init")
  
  logn "creating collection $c of type $SET_TYPE... "
  $RASQL -q "create collection $c $SET_TYPE" > /dev/null && echo ok. || error "failed"
  
  local x=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $1; }')
  local y=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $2; }')
  logn "initializing mdd object... "
  $RASQL -q "insert into $c values marray i in [$x:$x,$y:$y,0:0] values $init_val" > /dev/null && echo ok. || error failed.
}

create_mask_coll()
{
  local c="$1"
  logn "creating collection $c of type GreySet3... "
  $RASQL -q "create collection $c GreySet3" > /dev/null && echo ok. || error "failed"
  
  local x=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $1; }')
  local y=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $2; }')
  local init_val="0c"
  logn "initializing mdd object... "
  $RASQL -q "insert into $c values marray i in [$x:$x,$y:$y,0:0] values $init_val" > /dev/null && echo ok. || error failed.
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

update_query()
{
  logn " importing $file_to_import, shift $pixel_shift, slice $t_index... "
  $RASQL -q "update $coverage as m set m[*:*, *:*, $t_index] assign shift(inv_tiff(\$1), $pixel_shift)" -f $file_to_import > /dev/null && echo ok. || error failed.
  update_geo_bbox "$file_to_import" "$coverage"
  return 0
}

update_query_mask()
{
  logn " importing $raster_mask, shift $pixel_shift, slice $t_index... "
  $RASQL -q "update $coverage_mask as m set m[*:*, *:*, $t_index] assign shift(inv_tiff(\$1), $pixel_shift)" -f $raster_mask > /dev/null && echo ok. || error failed.
  update_geo_bbox "$raster_mask" "$coverage_mask"
  return 0
}

# TODO
rasterize_mask()
{
  raster_mask="$TMP_DIR/raster_mask.tif"
  python $RASTERIZE -f "$file_metadata" -o "$raster_mask" -r "$file_to_import"
  pixel_shift=$(compute_pixel_shift "$raster_mask")
}

# ----------------------------------------------------------------------------
# import data to petascope
# ----------------------------------------------------------------------------

importpet()
{
  local c="$1"
  check_petascope_cov "$c"
  if [ $? -ne 0 ]; then
    import_petascope "$c" "$axes_names" "$CRS"
  else
    update_petascope "$c" "$axes_names"
  fi
}

# ----------------------------------------------------------------------------
# actual work
# ----------------------------------------------------------------------------

usage()
{
  if [ -n "$1" ]; then
    echo "$PROG: $*" 1>&2
    echo
  fi
  echo "Usage: $PROG [OPTION]..."
  echo
  echo "Description: import DREAM data."
  echo
  echo "Options:"
  echo -e "  -f, --file FILE"
  echo -e "    specify file to import, can be an archive or TIFF file."
  echo -e "  -m, --metadata"
  echo -e "    specify EO-O&M metadata file."
  echo -e "  -h, --help"
  echo -e "    display this help and exit"
  
  if [ -n "$1" ]; then
    exit $RC_ERROR
  else
    exit $RC_OK
  fi
}

#
# parse command-line arguments
#
option=""
file_to_import=""
file_metadata=""
coverage=""

# go through all arguments on the command line
for i in $*; do
  if [ -n "$option" ]; then
    case $option in
      -f|--file*)     file_to_import="$i";;
      -m|--metadata*) file_metadata="$i";;
      -c|--coverage*) coverage="$i";;
      *) error "unknown option: $option"
    esac
    option=""
  else
    case $i in
      -h|--help*)   usage;;
      *) option="$i"
    esac
  fi
done

# arguments check
logn "checking input arguments... "
[ -z "$file_metadata" ]  && usage "please specify EO-O&M metadata file."
[ -z "$file_to_import" ] && usage "please specify file to import."
[ -z "$coverage" ]       && usage "please specify coverage name."
[ -f "$file_metadata" ]  || usage "specified EO-O&M metadata file not found: $file_metadata"
[ -f "$file_to_import" ] || usage "specified file not found: $file_to_import"
file "$file_metadata" | egrep 'XML +document +text' > /dev/null 2>&1 || error "specified EO-O&M metadata file is not an XML file: $file_metadata"
gdalinfo "$file_to_import" > /dev/null 2>&1 || error "specified file to import not recognized by GDAL: $file_to_import"
echo ok.

coverage_mask=$(mask_coll "$coverage")

#
# import data
#

# 1. translate to geotiff if file is in another format
gdalinfo "$file_to_import" | grep "Driver: GTiff/GeoTIFF" > /dev/null
if [ $? -ne 0 ]; then
  logn "translating input file to GeoTIFF... "
  gdal_translate -of GTiff "$file_to_import" "$TMP_DIR/tmp.tif" -q > /dev/null && echo ok. || error failed.
  file_to_import="$TMP_DIR/tmp.tif"
fi

# 2. compute pixel x/y shift in rasdaman
pixel_shift=$(compute_pixel_shift "$file_to_import")

# 3. check if coverage is present in rasdaman and create collection if not
check_coll "$coverage" || create_coll "$coverage" "$file_to_import"
check_coll "$coverage_mask" || create_mask_coll "$coverage_mask"

# 4. find out time index
timestamp=""
while read_dom; do
  parse_dom
  [ -n "$timestamp" ] && break
done < $file_metadata

timestamps_file="$TIMESTAMPS_DIR/$coverage"
if [ -f "$timestamps_file" ]; then
  tmp=$(grep "$timestamp" "$timestamps_file")
  if [ $? -eq 0 ]; then
    t_index=$(echo "$tmp" | awk '{ print $1; }')
  else
    t_index=$(cat "$timestamps_file" | wc -l)
    t_index=$(($t_index + 1))
    echo "$t_index $timestamp" >> "$timestamps_file"
  fi
else
  t_index=0
  echo "$t_index $timestamp" > "$timestamps_file"
fi

# 5. import geotiff file
run_rasql_query update_query
importpet "$coverage"

# 6. import mask
#rasterize_mask
#run_rasql_query update_query_mask
#importpet "$coverage_mask"


log "done."
