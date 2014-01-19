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
  check_coll "$c"
  if [ $? -ne 0 ]; then
    logn "initializing collection $c with $SET_TYPE<$MDD_TYPE<$BASE_TYPE>>... "
    $RASQL -q "create collection $c $SET_TYPE" > /dev/null
    feedback
  fi
  
  coll_empty "$c"
  if [ $? -ne 0 ]; then
    logn "initializing object... "
    local x=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $1; }')
    local y=$(echo "$pixel_shift" | tr -d '[' | tr -d ']' | tr -d ',' | awk '{ print $2; }')
    $RASQL -q "insert into $c values marray x in [$x:$x,$y:$y,$t:$t] values {0c,0c,0c,0c,0c}" > /dev/null || exit $RC_ERROR
    feedback
  fi
done
}

# ----------------------------------------------------------------------------
# import data to rasdaman
# ----------------------------------------------------------------------------

update_query()
{
  $RASQL -q "update $c as m set m[*:*, *:*, $t] assign shift(inv_tiff(\$1), $pixel_shift)" -f $f > /dev/null || exit
}

import_file()
{
  [ -n "$1" ] || error "no file to import given."
  local f="$1"
  [ -f "$f" ] || error "file $f not found."
  
  # check and uncompress input file if necessary
  echo "$f" | egrep -i "\.tar\.gz$" > /dev/null
  if [ $? -eq 0 ]; then
    f=$(tar xzf "$f" -C "$TMP_DIR" -v | egrep -i "\.tif$")
    if [ $? -ne 0 ]; then
      error "no TIFF file found in $f."
    fi
  else
    echo "$f" | egrep -i "\.tif$" > /dev/null
    if [ $? -ne 0 ]; then
      error "input file $f does not appear to be neither an archive nor a TIFF file."
    fi
  fi
  
  # at this point we assume to have a TIFF in f
  initcolls
  
  # time slice
  t=`echo $f | awk -F '_' '{ print $3; }'`
  
  # position in rasdaman, computed from resolution and geo-bbox
  pixel_shift=$(compute_pixel_shift $f)
  
  logn " importing $f, shift $pixel_shift, slice $t... "
  run_rasql_query update_query
  update_geo_bbox "$f"
}

import_dir()
{
  [ -n "$1" ] || error "no directory to import given."
  local d="$1"
  [ -d "$d" ] || error "directory $d not found."
  
  pushd $d > /dev/null

  for c in $COLLS; do
    log "importing $c"
    for pf in *; do
      [ -f "$pf" ] || continue
      
      # consider only .tar.gz and .tif files
      echo "$f" | egrep -i "(\.tar\.gz|\.tif)$" > /dev/null
      if [ $? -eq 0 ]; then
        import_file "$f"
      fi
    done
  done

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
  echo -e "  -f, --file FILE"
  echo -e "    specify file to import, can be an archive or TIFF file."
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

# go through all arguments on the command line
for i in $*; do
  if [ -n "$option" ]; then
    case $option in
      -f|--file*)   file_to_import="$i";;
      -d|--dir*)    dir_to_import="$i";;
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

# import data
if [ -n "$dir_to_import" ]; then
  import_dir "$dir_to_import"
  importpet
elif [ -n "$file_to_import" ]; then
  import_file "$file_to_import"
  importpet
fi

log "done."
