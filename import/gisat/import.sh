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

MAP_FILE="$TMP_DIR/slices_map"
RASTERIZE="$IMPORT_SCRIPT_DIR/rasterize.py"

# ----------------------------------------------------------------------------
# import initialization
# ----------------------------------------------------------------------------

# check dependencies
check_rasdaman

# read rasdl types from types.dl file
read_types

initcolls()
{
for c in $COLLS; do
  check_coll "$c"
  if [ $? -ne 0 ]; then
    logn "initializing collection $c with $SET_TYPE<$MDD_TYPE<$BASE_TYPE>>... "
    $RASQL -q "create collection $c $SET_TYPE" > /dev/null
    feedback
  fi
  
  coll_empty "$c"
  if [ $? -eq 0 ]; then
    logn "initializing object... "
    local x=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $1; }')
    local y=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $2; }')
    $RASQL -q "insert into $c values marray x in [$x:$x,$y:$y,$pixel_t:$pixel_t] values {0c,0c,0c,0c,0c}" > /dev/null || exit $RC_ERROR
    feedback
  fi
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

update_query()
{
  initcolls
  logn " importing $f, shift $pixel_shift, slice $t (rasdaman slice $pixel_t)... "
  $RASQL -q "update $GISAT_COLL as m set m[*:*, *:*, $pixel_t] assign shift(inv_tiff(\$1), $pixel_shift)" -f $f > /dev/null || exit
  rc=$?
  update_geo_bbox "$f"
  return $rc
}

update_query_mask()
{
  initcolls
  logn " importing $maskf, shift $pixel_shift, slice $t (rasdaman slice $pixel_t)... "
  $RASQL -q "update $GISAT_MASK_COLL as m set m[*:*, *:*, $pixel_t] assign shift(inv_tiff(\$1), $pixel_shift)" -f $maskf > /dev/null || exit
  rc=$?
  update_geo_bbox "$maskf"
  return $rc
}

import_file()
{
  [ -n "$1" ] || error "no file to import given."
  local f="$1"
  [ -f "$f" ] || error "file $f not found."
  local remove_dir=
  log ">>"
  
  local maskf="$1"
  local tiff=1
  local shp=1
  
  # check and uncompress input file if necessary
  echo "$f" | egrep -i "\.tar\.gz$" > /dev/null
  if [ $? -eq 0 ]; then
    logn " extracting $f... "
    local extracted_files=$(tar xzf "$f" -C "$TMP_DIR" -v)
    if [ $? -ne 0 ]; then
      echo failed.
      exit $RC_ERROR
    fi
    remove_dir="$TMP_DIR/"$(echo "$extracted_files" | head -n 1)
    if [ ! -d "$remove_dir" ]; then
      echo failed.
      exit $RC_ERROR
    fi
    local tmpf=$(echo "$extracted_files" | egrep -i "\.tif$")
    if [ $? -ne 0 ]; then
      error "no TIFF file found in $f."
    else
      echo ok.
      f="$TMP_DIR/$tmpf"
    fi
    tmpf=$(echo "$extracted_files" | egrep -i "\.shp$")
    if [ $? -ne 0 ]; then
      error "no shapefile file found in $f."
    else
      echo ok.
      maskf="$TMP_DIR/$tmpf"
    fi
  else
    echo "$f" | egrep -i "\.tif$" > /dev/null
    if [ $? -ne 0 ]; then
      tiff=0
    fi
    echo "$f" | egrep -i "\.shp$" > /dev/null
    if [ $? -ne 0 ]; then
      shp=0
    fi
    if [ $tiff -eq 0 -a $shp -eq 0 ]; then
      error "input file $f does not appear to be neither an archive, nor a TIFF/SHP file."
    fi
  fi
  
  # at this point we assume to have a TIFF in f
  
  # time slice
  t=$(echo $f | awk -F '_' '{ print $3; }')
  pixel_t=$(awk '/'$t'/ {print FNR}' "$MAP_FILE")
  
  if [ $tiff -eq 1 -a $masks -eq 0 ]; then
    # position in rasdaman, computed from resolution and geo-bbox
    pixel_shift=$(compute_pixel_shift "$f")
    run_rasql_query update_query
  fi
  
  if [ $shp -eq 1 ]; then
    # rasterize
    local maskr="$TMP_DIR/raster.tif"
    python $RASTERIZE -f "$maskf" -o "$maskr"
    
    # position in rasdaman, computed from resolution and geo-bbox
    pixel_shift=$(compute_pixel_shift "$maskr")
    run_rasql_query update_query_mask
    
    rm -f "$maskr"
  fi
  
  # remove extracted directory
  if [ -n "$remove_dir" ]; then
    logn " removing extracted data $remove_dir... "
    rm -rf "$remove_dir"
    feedback
  fi
}

import_dir()
{
  [ -n "$1" ] || error "no directory to import given."
  local d="$1"
  [ -d "$d" ] || error "directory $d not found."
  
  pushd $d > /dev/null

  c="gisat"
  log "importing $c"

  log "  determining number of time slices in $d..."
  ls | grep 'S2sim_' | awk -F '_' '{ print $3; }' | sed '/^$/d' | sort | uniq > "$MAP_FILE"
  [ -s "$MAP_FILE" ] || error "No Sentinel2-simulated data found (files or directories starting with 'S2sim_')"
  local slices_no=$(cat "$MAP_FILE" | wc -l)
  log "  found $slices_no unique time slices, will be imported in indexes 0 - $(($slices_no - 1))."

  for pf in *; do
    [ -f "$pf" -o -d "$pf" ] || continue
    
    # consider only .tar.gz and .tif files
    echo "$pf" | egrep -i "(\.tar\.gz|\.tif|\.shp)$" > /dev/null
    if [ $? -eq 0 ]; then
      import_file "$pf"
    elif [ -d "$pf" ]; then
      pushd "$pf" > /dev/null
      if [ $masks -eq 0 ]; then
        for tf in *.tif; do
          import_file "$tf"
        done
      fi
      for tf in *.shp; do
        import_file "$tf"
      done
      popd > /dev/null
    fi
  done
  rm -f "$MAP_FILE"

  popd > /dev/null
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

usage()
{
  echo "Usage: $PROG [OPTION]..."
  echo
  echo "Description: import simulated Sentinel-2 Data."
  echo
  echo "Options:"
  echo -e "  -d, --dir"
  echo -e "    specify directory, all files in it will be imported as with the -f option."
  echo -e "  -m, --masks"
  echo -e "    import only cloud masks."
  #echo -e "  -f, --file FILE"
  #echo -e "    specify file to import, can be an archive or TIFF file."
  echo -e "  -h, --help"
  echo -e "    display this help and exit"
  exit $RC_OK
}

#
# parse command-line arguments
#
option=""
file_to_import=""
dir_to_import=""
masks=0

# go through all arguments on the command line
for i in $*; do
  if [ -n "$option" ]; then
    case $option in
#      -f|--file*)   file_to_import="$i";;
      -d|--dir*)    dir_to_import="$i";;
      *) error "unknown option: $option"
    esac
    option=""
  else
    case $i in
      -h|--help*)   usage;;
      -m|--masks*)  masks=1;;
      *) option="$i"
    esac
  fi
done

# import data
if [ -n "$dir_to_import" ]; then
  import_dir "$dir_to_import"
  importpet
elif [ -n "$file_to_import" ]; then
  import_file "$file_to_import"
  importpet
else
  usage
fi

log "done."
