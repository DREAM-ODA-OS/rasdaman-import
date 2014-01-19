#!/bin/bash
# ----------------------------------------------------------------------------
# Description   Utility methods for coverage metadata import to petascope.
# Dependencies  
#
# Date          2013-sep-02
# Author        Dimitar Misev
# ----------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Check if petascope is initialized and running
check_petascope()
{
  $PSQL --list | egrep "\b$PS_DB\b" > /dev/null
  if [ $? -ne 0 ]; then
    log "no petascope database present, please install petascope first."
    return 1
  fi
  $WGET -q $WCPS_URL -O /dev/null
  if [ $? -ne 0 ]; then
    log "failed connecting to petascope at $WCPS_URL, please deploy it first."
    return 1
  fi
  return 0
}

# ------------------------------------------------------------------------------
# check if coverage exists in petascope
# arg 1: coverage name
# return 0 on success, non-0 otherwise
check_petascope_cov()
{
  local c="$1"
  local ret=0
  id=`$PSQL -c  "select id from PS_Coverage where name = '$c' " | head -3 | tail -1`
  if [[ "$id" == \(0*\) ]]; then
    ret=1
  fi
  return $ret
}

# ------------------------------------------------------------------------------
# check if coverage exists in rasdaman and petascope
# arg 1: coverage name
# return 0 on success, non-0 otherwise
check_cov()
{
  local c="$1"
  check_petascope_cov "$c"
  local test1=$?

  $RASQL -q 'select r from RAS_COLLECTIONNAMES as r' --out string | egrep "\b$c\b" > /dev/null
  local test2=$?
  [ $test1 -eq 0 -a $test2 -eq 0 ]
}

# ------------------------------------------------------------------------------
# update petascope coverages list to be imported, based on global var $COLLS
# and outputing result in global var $COVS
update_covs()
{
  local tmpcolls=""
  for c in $COLLS; do
    check_petascope_cov "$c"
    if [ $? -ne 0 ]; then
      if [ -z "$tmpcolls" ]; then
        tmpcolls="$c"
      else
        tmpcolls="$tmpcolls $c"
      fi
    fi
  done
  COVS="$tmpcolls"
}

# ------------------------------------------------------------------------------
# drop metadata for coverages in global variable COLLS
drop_petascope()
{
  check_postgres
  for c in $COLLS; do
    logn "deleting coverage $c from petascope... "

    check_petascope_cov $c
    if [ $? -eq 0 ]; then
      # get the coverage id
      local c_id=$($PSQL -c "select id from PS_Coverage where name = '$c' " | head -3 | tail -1) > /dev/null

      $PSQL -c "delete from PS_Metadata where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_Coverage where id = $c_id" > /dev/null
      $PSQL -c "delete from PS_CellDomain where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_Domain where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_Range where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_InterpolationSet where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_NullSet where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_CrsDetails where coverage = $c_id" > /dev/null
      $PSQL -c "delete from PS_crsset where axis in (select id from PS_domain where coverage = $c_id)" > /dev/null

      echo ok.
    else
      echo not found.
    fi

  done
}

# ------------------------------------------------------------------------------
# remove collection with raserase
# arg 1: collection name
raserase_coll()
{
  local c=$1
  logn "deleting collection $c from rasdaman... "
  
  $RASQL -q 'select r from RAS_COLLECTIONNAMES as r' --out string | grep "$c" > /dev/null
  if [ $? -ne 0 ]; then
    echo not found.
  else
    $RASERASE -coll "$c" > /dev/null
    feedback
  fi
}

# ------------------------------------------------------------------------------
# remove collections in global var $COLLS with raserase
raserase_colls()
{
  check_rasdaman
  for c in $COLLS; do
    raserase_coll "$c"
  done
}

# ------------------------------------------------------------------------------
# compile WMS utilities if not present
compile_wms()
{
  if [ ! -e "$WMS_INIT_PATH/initpyramid" ]; then
    log Compiling initpyramid...
    cd "$WMS_INIT_PATH" && make
  fi

  if [ ! -e "$WMS_IMPORT_PATH/fillpyramid" ]; then
    log Compiling fillpyramid...
    cd "$WMS_IMPORT_PATH" && make
  fi
  export PATH=$PATH:$WMS_INIT_PATH:$WMS_IMPORT_PATH
}

# ------------------------------------------------------------------------------
# drop WMS coverage
drop_wms()
{
  check_postgres
  for c in $COLLS; do
    logn "deleting wms service $c from rasdaman... "
    $DROP_WMS "$c"_wms
    feedback
  done
}

# ------------------------------------------------------------------------------
# get X pixel resolution with gdalinfo
# arg 1: file name
#
get_resolution_x()
{
  gdalinfo "$1" | grep 'Pixel Size' | sed 's/.*(//' | tr -d ')' | tr ',' ' ' | awk '{ print $1; }'
}

# ------------------------------------------------------------------------------
# get Y pixel resolution with gdalinfo
# arg 1: file name
#
get_resolution_y()
{
  gdalinfo "$1" | grep 'Pixel Size' | sed 's/.*(//' | tr -d ')' | tr ',' ' ' | awk '{ print $2; }'
}

# ------------------------------------------------------------------------------
# get upper left X coordinate with gdalinfo
# arg 1: file name
#
get_upperleft_x()
{
  gdalinfo "$1" | grep 'Upper Left' | sed 's/) (.*//' |  sed 's/.*(//' | tr -d ',' | awk '{ print $1; }'
}

# ------------------------------------------------------------------------------
# get upper left Y coordinate with gdalinfo
# arg 1: file name
#
get_upperleft_y()
{
  gdalinfo "$1" | grep 'Upper Left' | sed 's/) (.*//' |  sed 's/.*(//' | tr -d ',' | tr -d ')' | awk '{ print $2; }'
}

# ------------------------------------------------------------------------------
# get lower right X coordinate with gdalinfo
# arg 1: file name
#
get_lowerright_x()
{
  gdalinfo "$1" | grep 'Lower Right' | sed 's/) (.*//' |  sed 's/.*(//' | tr -d ',' | awk '{ print $1; }'
}

# ------------------------------------------------------------------------------
# get lower right Y coordinate with gdalinfo
# arg 1: file name
#
get_lowerright_y()
{
  gdalinfo "$1" | grep 'Lower Right' | sed 's/) (.*//' |  sed 's/.*(//' | tr -d ',' | tr -d ')' | awk '{ print $2; }'
} 


# ------------------------------------------------------------------------------
# compute pixel shift based on geo coordinates and pixel resolution with gdalinfo
# arg 1: file name
# resutl: [X_shift, Y_shift]
#
compute_pixel_shift()
{
  xres=`get_resolution_x $f`
  yres=`get_resolution_y $f`
  ulx=`get_upperleft_x $f`
  uly=`get_upperleft_y $f`

  shift_x=`echo "$ulx / $xres" | bc`
  shift_y=`echo "$uly / $yres" | bc`
  
  echo "[$shift_x, $shift_y]"
}

# ------------------------------------------------------------------------------
# update the min_x_geo_coord, max_x_geo_coord, ..., with gdalinfo
# arg 1: file name
# result: no result, global variables are directly updated
#
update_geo_bbox()
{
  local f="$1"
  local minx=$(get_upperleft_x "$f")
  local maxx=$(get_lowerright_x "$f")
  local miny=$(get_lowerright_y "$f")
  local maxy=$(get_upperleft_y "$f")
  local up="0"
  
  up=$(echo "$minx < $min_x_geo_coord" | bc -l)
  [ "$up" == "1" ] && min_x_geo_coord="$minx"
  
  up=$(echo "$miny < $min_y_geo_coord" | bc -l)
  [ "$up" == "1" ] && min_y_geo_coord="$miny"
  
  up=$(echo "$maxx > $max_x_geo_coord" | bc -l)
  [ "$up" == "1" ] && max_x_geo_coord="$maxx"
  
  up=$(echo "$maxy > $max_y_geo_coord" | bc -l)
  [ "$up" == "1" ] && max_y_geo_coord="$maxy"
}

# ------------------------------------------------------------------------------
# expects a list of comma-separated values,
# returns the value at the specificed position.
# arg 1: list of values, e.g. "a,b,c,d"
# arg 2: 0-based position, e.g. 2 = c
get_axis_name()
{
  local names=$1
  local ind=$2
  names=`echo $names | tr ',' ' '`
  local ret=""
  i=0
  for name in $names; do
    if [ $i -eq $ind ]; then
      ret=$name
      break
    fi 
    i=$(($i+1))
  done
  echo "$ret"
}

# ------------------------------------------------------------------------------
# get petascope type corresponding to ps_datatype, from the rasdaman type
# arg 1: rasdaman type
# return: petascope type
get_ps_type()
{
  local ret="$1"
  echo "$ret" | egrep '^u' > /dev/null
  if [ $? -eq 0 ]; then
    ret=`echo "$ret" | sed 's/^u//'`
    ret="unsigned $ret"
  fi
  echo $ret
}

# ------------------------------------------------------------------------------
# construct nulldefault value
# arg 1: number of bands
# return: nulldefault value
get_nulldefault()
{
  local rangecomp_no="$1"
  
  if [ $rangecomp_no -gt 1 ]; then
    local ret=""
    for i in `seq $rangecomp_no`; do
      if [ -z "$ret" ]; then
        ret="0"
      else
        ret="$ret,0"
      fi
    done
    echo "{$ret}"
  else
    echo "0"
  fi
}

# ------------------------------------------------------------------------------
#
# import petascope metadata
#
# arg 1: coverage name
# arg 2: axis names (CSV list)
# arg 3: coverage crs
#
import_petascope()
{
  local c="$1"
  local axisnames="$2"
  local crs="$3"
  
  #
  # import
  #
  logn "importing coverage $c to petascope... "
  
  check_coll "$c"
  if [ $? -ne 0 ]; then
    echo "skipping, $c not found in rasdaman."
    return 1
  fi
  
  # get sdom of collection
  local domains=`$RASQL -q "select sdom(c) from $c as c" --out string --quiet | tr -d '[' | tr -d ']' | tr ',' ' ' | tr ':' ','`
  local dims_no=`get_dims_no "$c"`
  
  local rangetype=`get_range_type $c $dims_no`
  local rangecomp=`echo $rangetype | sed 's/, /-/g' | sed 's/struct{ //g' | sed 's/ }//' | sed 's/ /:/g' | tr '-' ' '`
  local rangecomp_no=`echo $rangecomp | tr ' ' '\n' | wc -l`
  
  local nulldefault=`get_nulldefault $rangecomp_no`
  
  local covtype='RectifiedGridCoverage'
  if [ "$crs" == "CRS:1" ]; then
    covtype="GridCoverage"
  fi

  # general coverage information (name, type, ...)
  $PSQL -c "insert into PS_Coverage (name, nulldefault, interpolationtypedefault, nullresistancedefault, type) values ( '$c','$nulldefault', 5, 2, '$covtype')" > /dev/null

  # get the coverage id
  local c_id=$($PSQL -c  "select id from PS_Coverage where name = '$c' " | head -3 | tail -1) > /dev/null

  # describe the pixel domain
  local i=0
  for domain in $domains; do
    $PSQL -c "insert into PS_CellDomain (coverage, i, lo, hi )  values ( $c_id, $i, $domain)" > /dev/null
    i=$(($i + 1))
  done

  # describe the geo domain
  local i=0
  local dom=""
  local type=0
  local name=""
  
  for domain in $domains; do
    name=`get_axis_name "$axisnames" $i`
    if [ $name == "x" ]; then
      if [ -z "$min_x_geo_coord" -o -z "$max_x_geo_coord" ]; then
        dom="$domain"
      else
        dom="$min_x_geo_coord, $max_x_geo_coord"
      fi
      xdomain="$dom"
      type=1
    elif [ $name == "y" ]; then
      if [ -z "$min_y_geo_coord" -o -z "$max_y_geo_coord" ]; then
        dom="$domain"
      else
        dom="$min_y_geo_coord, $max_y_geo_coord"
      fi
      ydomain="$dom"
      type=2
    else
      dom="$domain"
      type=5
    fi
    $PSQL -c "insert into PS_Domain (coverage, i, name, type, numLo, numHi) values ( $c_id, $i, '$name', $type, $dom )" > /dev/null
    i=$(($i + 1))
  done

  # describe the datatype of the coverage cell values
  local i=0
  for comp in $rangecomp; do
    echo "$comp" | grep ':' > /dev/null
    if [ $? -ne 0 ]; then
      local tmptype=`get_ps_type "$rangecomp"`
      $PSQL -c "insert into PS_Range (coverage, i, name, type) values ($c_id, $i, 'value', (select max(id) from ps_datatype where datatype = '$tmptype'))" > /dev/null
    else
      local comptype=`echo $comp | awk -F ':' '{ print $1; }'`
      local compname=`echo $comp | awk -F ':' '{ print $2; }'`
      local tmptype=`get_ps_type "$comptype"`
      $PSQL -c "insert into PS_Range (coverage, i, name, type) values ($c_id, $i, '$compname', (select max(id) from ps_datatype where datatype = '$tmptype'))" > /dev/null
    fi
    i=$(($i + 1))
  done

  # set of interpolation methods and null values for the coverage
  $PSQL -c "insert into PS_InterpolationSet (coverage, interpolationType, nullResistance) values ( $c_id, 5, 2)" > /dev/null
  $PSQL -c "insert into PS_NullSet (coverage, nullValue) values ( $c_id, '$nulldefault')" > /dev/null

  # geo-referecing information about the coverage
  if [ -n "$xdomain" -a -n "$ydomain" ]; then
    $PSQL -c "insert into PS_CrsDetails (coverage, low1, high1, low2, high2) values ( $c_id, $xdomain, $ydomain)" > /dev/null
  fi
  
  # insert crs if not inserted already
  local exists=$($PSQL -c "select count(*) from PS_Crs where name = '$crs'" | head -3 | tail -1) > /dev/null
  if [ $exists -eq 0 ]; then
    $PSQL -c "insert into PS_Crs (id, name)  values ((select max(id)+1 from PS_Crs), '$crs')" > /dev/null
  fi
  local crs_id=$($PSQL -c "select id from PS_Crs where name = '$crs'" | head -3 | tail -1) > /dev/null

  # set the crs for the geo axes
  $PSQL -c "insert into PS_crsset ( axis, crs) values ( (select id from PS_domain where coverage = $c_id and type=1), $crs_id)" > /dev/null
  $PSQL -c "insert into PS_crsset ( axis, crs) values ( (select id from PS_domain where coverage = $c_id and type=2), $crs_id)" > /dev/null
  
  # crs for other axes
  local crs1_id=$($PSQL -c "select id from PS_Crs where name = 'CRS:1'" | head -3 | tail -1) > /dev/null
  local axes_list=`$PSQL -c "select id from PS_domain where coverage = $c_id and (type<>1 and type<>2)" | egrep " [0-9]+" | sed 's/^ //g'`
  for axis in $axes_list; do
    $PSQL -c "insert into PS_crsset ( axis, crs) values ( $axis, $crs1_id)" > /dev/null
  done

  echo ok.
}

# ------------------------------------------------------------------------------
#
# update petascope metadata
#
# arg 1: coverage name
# arg 2: axis names (CSV list)
# arg 3: coverage crs
#
import_petascope()
{
  local c="$1"
  local axisnames="$2"
  
  #
  # import
  #
  logn "updating coverage $c in petascope... "
  
  check_coll "$c"
  if [ $? -ne 0 ]; then
    echo "skipping, $c not found in rasdaman."
    return 1
  fi
  
  # get sdom of collection
  local domains=`$RASQL -q "select sdom(c) from $c as c" --out string --quiet | tr -d '[' | tr -d ']' | tr ',' ' ' | tr ':' ','`
  local dims_no=`get_dims_no "$c"`
  
  local rangetype=`get_range_type $c $dims_no`
  local rangecomp=`echo $rangetype | sed 's/, /-/g' | sed 's/struct{ //g' | sed 's/ }//' | sed 's/ /:/g' | tr '-' ' '`
  local rangecomp_no=`echo $rangecomp | tr ' ' '\n' | wc -l`
  
  local nulldefault=`get_nulldefault $rangecomp_no`
  
  local covtype='RectifiedGridCoverage'
  if [ "$crs" == "CRS:1" ]; then
    covtype="GridCoverage"
  fi
  
  # get the coverage id
  local c_id=$($PSQL -c  "select id from PS_Coverage where name = '$c' " | head -3 | tail -1) > /dev/null

  # describe the pixel domain
  local i=0
  for domain in $domains; do
    local lo=$(echo "$domain" | awk -F "," "{ print $1; }")
    local hi=$(echo "$domain" | awk -F "," "{ print $2; }")
    $PSQL -c "update PS_CellDomain set lo = $lo, hi = $hi where coverage = $c_id and i = $i" > /dev/null
    i=$(($i + 1))
  done

  # describe the geo domain
  local i=0
  local dom=""
  local type=0
  local name=""
  
  for domain in $domains; do
    name=`get_axis_name "$axisnames" $i`
    if [ $name == "x" ]; then
      if [ -z "$min_x_geo_coord" -o -z "$max_x_geo_coord" ]; then
        dom="$domain"
      else
        dom="$min_x_geo_coord,$max_x_geo_coord"
      fi
      xdomain="$dom"
      type=1
    elif [ $name == "y" ]; then
      if [ -z "$min_y_geo_coord" -o -z "$max_y_geo_coord" ]; then
        dom="$domain"
      else
        dom="$min_y_geo_coord,$max_y_geo_coord"
      fi
      ydomain="$dom"
      type=2
    else
      dom="$domain"
      type=5
    fi
    local lo=$(echo "$dom" | awk -F "," "{ print $1; }")
    local hi=$(echo "$dom" | awk -F "," "{ print $2; }")
    $PSQL -c "update PS_Domain set numLo = $lo, numHi = $hi where coverage = $c_id and i = $i" > /dev/null
    i=$(($i + 1))
  done
  
  # geo-referecing information about the coverage
  if [ -n "$xdomain" -a -n "$ydomain" ]; then
    local lo=$(echo "$xdomain" | awk -F "," "{ print $1; }")
    local hi=$(echo "$xdomain" | awk -F "," "{ print $2; }")
    $PSQL -c "update PS_CrsDetails set low1 = $lo, high1 = $hi where coverage = $c_id" > /dev/null
    lo=$(echo "$ydomain" | awk -F "," "{ print $1; }")
    hi=$(echo "$ydomain" | awk -F "," "{ print $2; }")
    $PSQL -c "update PS_CrsDetails set low2 = $lo, high2 = $hi where coverage = $c_id" > /dev/null
  fi

  echo ok.
}
