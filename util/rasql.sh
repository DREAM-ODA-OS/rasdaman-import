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
function base_to_coll_type()
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
function coll_empty()
{
  local c="$1"
  $RASQL -q "select oid($c) from $c" | grep "Query result collection has 0 element(s):"
  return $?
}

# ------------------------------------------------------------------------------
# drop rasdaman types, set in global vars $SET_TYPE, $MDD_TYPE, $BASE_TYPE
function drop_types()
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
function update_colls()
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
function check_coll()
{
  local coll_name="$1"
  $RASQL -q 'select r from RAS_COLLECTIONNAMES as r' --out string | egrep "\b$coll_name\b" > /dev/null
}

# check if collection exists in rasdaman
# arg 1: collection name
# arg 2: error message in case collection doesn't exist
function check_collection()
{
  check_coll "$1"
  if [ $? -ne 0 ]; then
    error "$2"
  fi
}


# ------------------------------------------------------------------------------
# drop collections as specified by the arguments. If no collections are given
# it assumes global var $COLLS
function drop_colls()
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
function check_user_type()
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
function check_type()
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
function read_types_from()
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
function read_types()
{
  read_types_from "$IMPORT_SCRIPT_DIR/types.dl"
}

function get_types()
{
  MDD_TYPE=$1
  SET_TYPE=$2
}

# ------------------------------------------------------------------------------
# return rasdaman struct from a NetCDF input file
# arg 1: netcdf input file
function nc2type()
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
function get_dims_no()
{
  local c="$1"
  $RASQL -q "select sdom(c) from $c as c" --out string --quiet | tr -d '[' | tr -d ']' | tr ',' ' ' | tr ':' ',' | tr ' ' '\n' | wc -l
}

# ------------------------------------------------------------------------------
# get cell type of rasql collection
# arg 1: collection name
# return: cell type as printed by rasql
function get_range_type()
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
