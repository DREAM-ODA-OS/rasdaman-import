#!/bin/bash
# ----------------------------------------------------------------------------
# Description   Utility methods for rasdaman import scripts.
# Dependencies  
#
# Date          2013-mar-16
# Author        Dimitar Misev
# ----------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# convert base type to collection type (print output)
# arg 1: base type
# arg 2: optional dimension number (default: none)
#
base_to_coll_type()
{
  local ret=""
  case "$1" in
    char) ret="GreySet";;
    short) ret="ShortSet";;
    long) ret="LongSet";;
    float) ret="FloatSet";;
    double) ret="DoubleSet";;
  esac
  if [ -n "$2" ]; then
    ret="$ret$2"
  fi
  echo $ret
}

# ------------------------------------------------------------------------------
# check if collection is empty
# arg 1: collection name
# return: 0 if empty, 1 otherwise
coll_empty()
{
  local c="$1"
  $RASQL -q "select oid($c) from $c" | grep "Query result collection has 0 element(s):"
  return $?
}

# ------------------------------------------------------------------------------
# drop rasdaman types, set in global vars $SET_TYPE, $MDD_TYPE, $BASE_TYPE
drop_types()
{
  check_rasdaman
  
  if [ -n "$SET_TYPE" ]; then
    $RASDL -p | grep $SET_TYPE > /dev/null
    if [ $? -eq 0 ]; then
      logn "deleting set type $SET_TYPE... "
      $RASDL --delsettype $SET_TYPE > /dev/null
      feedback
    fi
  fi

  if [ -n "$MDD_TYPE" ]; then
    $RASDL -p | grep $MDD_TYPE > /dev/null
    if [ $? -eq 0 ]; then
      logn "deleting array type $MDD_TYPE... "
      $RASDL --delmddtype $MDD_TYPE  > /dev/null
      feedback
    fi
  fi

  if [ -n "$BASE_TYPE" ]; then
    $RASDL -p | grep $BASE_TYPE > /dev/null
    if [ $? -eq 0 ]; then
      logn "deleting base type $BASE_TYPE... "
      $RASDL --delbasetype $BASE_TYPE  > /dev/null
      feedback
    fi
  fi
}

# ------------------------------------------------------------------------------
# update $COLLS (leave only the ones not present in rasdaman)
update_colls()
{
  local tmpcolls=""
  for c in $COLLS; do
    check_coll "$c"
    if [ $? -ne 0 ]; then
      if [ -z "$tmpcolls" ]; then
        tmpcolls="$c"
      else
        tmpcolls="$tmpcolls $c"
      fi
    fi
  done
  COLLS="$tmpcolls"
}

# ------------------------------------------------------------------------------
# check if collection exists in rasdaman
# arg 1: collection name
# return 0 if found in rasdaman, non-zero otherwise
#
check_coll()
{
  local coll_name="$1"
  $RASQL -q 'select r from RAS_COLLECTIONNAMES as r' --out string | egrep "\b$coll_name\b" > /dev/null
}

# check if collection exists in rasdaman
# arg 1: collection name
# arg 2: error message in case collection doesn't exist
check_collection()
{
  check_coll "$1"
  if [ $? -ne 0 ]; then
    error "$2"
  fi
}


# ------------------------------------------------------------------------------
# drop collections as specified by the arguments. If no collections are given
# it assumes global var $COLLS
drop_colls()
{
  check_rasdaman
  local colls_to_drop="$COLLS"
  if [ $# -gt 0 ]; then
    colls_to_drop="$*"
  fi
  for c in $colls_to_drop; do
    logn "deleting collection $c from rasdaman... "
    $RASQL -q 'select r from RAS_COLLECTIONNAMES as r' --out string | egrep "\b$c\b" > /dev/null
    if [ $? -eq 0 ]; then
      $RASQL -q "drop collection $c" > /dev/null
      feedback
    else
      echo not found.
    fi
  done
}


# ------------------------------------------------------------------------------
# check user-defined types, if not present testdata/types.dl is read by rasdl.
# arg 1: set type name
#
check_user_type()
{
  local SET_TYPE="$1"
  $RASDL -p | egrep --quiet  "\b$SET_TYPE\b"
  if [ $? -ne 0 ]; then
    $RASDL -r "$IMPORT_SCRIPT_DIR/types.dl" -i > /dev/null
  fi
}


# ------------------------------------------------------------------------------
# check built-in types, if not present error is thrown
# arg 1: set type name
#
check_type()
{
  local SET_TYPE="$1"
  $RASDL -p | egrep --quiet  "\b$SET_TYPE\b"
  if [ $? -ne 0 ]; then
    error "rasdaman basic type $SET_TYPE not found, please insert with rasdl first."
  fi
}

# ------------------------------------------------------------------------------
# read rasdl types, given the file name from which to read
#
read_types_from()
{
  local types="$1"
  $RASDL -p | egrep --quiet  "\b$SET_TYPE\b"
  if [ $? -ne 0 ]; then
    if [ -e "$types" ]; then
      logn "importing types from file types.dl... "
      $RASDL -r "$types" -i > /dev/null 2>&1
      local rc=$?
      if [ $rc -ne 0 ]; then
        egrep -i "null +values +" > /dev/null
        if [ $? -eq 0 ]; then
          echo failed.
          log "warning: attempting to import types with null values in rasdaman community"
          logn "removing null values from type definition and retrying... "
          sed 's/null  *values  *\[.*\] //g' "$types" > /tmp/types.dl
          $RASDL -r "/tmp/types.dl" -i > /dev/null 2>&1
          if [ $? -ne 0 ]; then
            echo failed.
            exit $RC_ERROR
          else
            echo ok.
          fi
        else
          echo failed.
          exit $RC_ERROR
        fi
      else
        echo ok.
      fi
    fi
  fi
}

# ------------------------------------------------------------------------------
# read rasdl types, expects global vars SET_TYPE
#
read_types()
{
  read_types_from "$IMPORT_SCRIPT_DIR/types.dl"
}

get_types()
{
  MDD_TYPE=$1
  SET_TYPE=$2
}

# ------------------------------------------------------------------------------
# return rasdaman struct from a NetCDF input file
# arg 1: netcdf input file
nc2type()
{
  local f="$1"
  [ -f "$f" ] || error "file not found: $f"
  echo -n "struct Pixel {"
  ncdump -h "$f" | grep "variables:" -A1000 | sed '/^\t\t.*/d' | sed 's/(.*//' | sed 's/\\ /_/g' \
                 | sed 's/\\:/_/g' | sed 's/__/_/g' | sed '/variables/d' | sed '/}/d' | tr '\t' ' ' \
                 | tr '\n' ';' | sed 's/byte/char/g' | sed 's/int/long/g'
  echo " };"
}



# ------------------------------------------------------------------------------
# get dimensionality of a collection
# arg 1: collection name
# return: echo number of dimensions
get_dims_no()
{
  local c="$1"
  $RASQL -q "select sdom(c) from $c as c" --out string --quiet | tr -d '[' | tr -d ']' | tr ',' ' ' | tr ':' ',' | tr ' ' '\n' | wc -l
}

# ------------------------------------------------------------------------------
# get cell type of rasql collection
# arg 1: collection name
# return: cell type as printed by rasql
get_range_type()
{
  local c="$1"
  local dims=`get_dims_no "$c"`
  # generate subset domain for fast access
  subset=""
  for i in `seq 0 $(($dims-1))`; do
    low=`$RASQL -q "select sdom(c)[$i].lo from $c as c" --out string | grep Result | awk '{ print $4; }'`
    if [ -z "$subset" ]; then
      subset="$low:$low"
    else
      subset="$subset,$low:$low"
    fi
  done
  $RASQL -q "select r[$subset] from $c as r" --type --out string | grep "Element Type Schema" | awk -F '<' '{ print $2; }' | awk -F '>' '{ print $1; }' | sed 's/^ //' | sed 's/ $//'
}

# ------------------------------------------------------------------------------
# execute a rasql query by taking into account rasdaman availability. The rasql
# query is not passed directly here, as we can never account for all the
# possible cases. Instead, it's wrapped into a function, and the function name
# is passed here.
#
# This function will execute the function retrying maximum 5 times until the 
# called function returns a 0. As long as the called function returns non-zero,
# rasdaman is restarted. Also amount of free RAM is checked, if it's lower than
# 300MB then rasdaman is restarted.
#
# This function also computes import speed, and depends on global variable $f
# pointing to the file that is being imported. This is optional, if $f is not
# defined, then only the time in seconds is printed, instead of speed in MB/s.
#
# arg 1: function name to execute
# arg 2: minimum RAM, optional by default it's 500MB
run_rasql_query()
{
  local func="$1"
  local min_mem=300
  if [ $# -eq 2 ]; then
    min_mem=$2
  fi
  
  local filesize=0
  if [ -n "$f" -a -f "$f" ]; then
    filesize=$(stat -c%s "$f")
  fi
  
  local freemem=`free -m | grep Mem: | awk '{ print $4; }'`
  if [ $freemem -lt $min_mem ]; then
    echo ""
    log "memory too low:"
    echo -n "  "
    restart_rasdaman
    #echo -n "  "
    #restart_postgres
  fi
  
  local rc=1
  local times=0
  while [ $rc -ne 0 ]; do
    
    # repeat a failing query maximum 5 times
    if [ $times -gt 5 ]; then
      echo "failed importing to rasdaman"
      break
    fi
    
    local START=$(date +%s.%N)
    
    # execute function
    $func
    rc=$?
    
    local END=$(date +%s.%N)
    
    if [ $rc -ne 0 ]; then
      times=$(($times + 1))
      echo ""
      logn "failed, repeating $times... "
      restart_rasdaman
    else
      local DIFF=0
      if [ $filesize -eq 0 ]; then
        DIFF=$(echo "($END - $START)" | bc)
        echo "ok, $DIFF seconds."
      else
        DIFF=$(echo "scale=3; ($filesize / ($END - $START)) / 1048576" | bc)
        echo "ok, at $DIFF MB/s."
      fi
    fi
  done
}
