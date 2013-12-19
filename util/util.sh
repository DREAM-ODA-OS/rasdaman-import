#!/bin/bash
# ----------------------------------------------------------------------------
# Description   Utility methods for rasdaman import scripts.
# Dependencies  
#
# Date          2013-mar-16
# Author        Dimitar Misev
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# script initialization
# ----------------------------------------------------------------------------

# return codes
RC_OK=0    # everything went fine
RC_ERROR=1 # something went wrong

# determine script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# include configuration details
. $SCRIPT_DIR/../conf/import.var


# ------------------------------------------------------------------------------
# WMS paths
export WMS_PATH=$RMANSRC/applications/rasgeo/wms-import
export WMS_UTIL_PATH=$WMS_PATH/utilities
export WMS_INIT_PATH=$WMS_PATH/inittools
export WMS_IMPORT_PATH=$WMS_PATH/importtools

export INIT_WMS="init_wms.sh"
export FILL_WMS="fill_pyramid.sh"
export DROP_WMS="drop_wms.sh"

# ------------------------------------------------------------------------------
# command shortcuts
export RASLOGIN="rasadmin:d293a15562d3e70b6fdc5ee452eaed40"
export RASQL="rasql --server $RASMGR_HOST --port $RASMGR_PORT --user $RASMGR_ADMIN_USER \
                    --passwd $RASMGR_ADMIN_PASSWD --database $RASDB"
export RASCONTROL="rascontrol --host $RASMGR_HOST --port $RASMGR_PORT"
export RASMGR="rasmgr"
export RASDL="rasdl -d $RASDB"
export PSQL="psql -d $PS_DB --port $PS_PORT"
export INITMDD="initmdd --user $RASMGR_ADMIN_USER --passwd $RASMGR_ADMIN_PASSWD \
                --port $RASMGR_PORT -d $RASDB --server $RASMGR_HOST"
export RASIMPORT="rasimport"
export RASERASE="raserase"
export INSERTPPM="insertppm -u $RASMGR_ADMIN_USER -p $RASMGR_ADMIN_PASSWD -d $RASDB -s $RASMGR_HOST --port $RASMGR_PORT"
export INSERTBIN="$SCRIPT_DIR/insertbin/insertbin $RASMGR_HOST $RASMGR_PORT $RASMGR_ADMIN_USER $RASMGR_ADMIN_PASSWD $RASDB"
export INSERTDAT="$SCRIPT_DIR/insertdat/insertdat $RASMGR_HOST $RASMGR_PORT $RASMGR_ADMIN_USER $RASMGR_ADMIN_PASSWD $RASDB"
export GETTYPE="$SCRIPT_DIR/gettype.py"

# ------------------------------------------------------------------------------
# build depending utilities only as necessary
if [ -n "$RMANSRC" ]; then
  echo "$IMPORT_SCRIPT_DIR" | grep "import/climate/" > /dev/null
  rc=$?
  if [ ! -e "$SCRIPT_DIR/insertbin/insertbin" -a $rc -eq 0 ]; then
    pushd "$SCRIPT_DIR/insertbin" > /dev/null
    make -i insertbin
    popd > /dev/null
  fi
  echo "$IMPORT_SCRIPT_DIR" | grep "import/timeseries/" > /dev/null
  rc=$?
  if [ ! -e "$SCRIPT_DIR/insertdat/insertdat" -a $rc -eq 0 ]; then
    pushd "$SCRIPT_DIR/insertdat" > /dev/null
    make -i insertdat
    popd > /dev/null
  fi
fi

# ------------------------------------------------------------------------------
# logging
#
LOG="$IMPORT_SCRIPT_DIR/log"
OLDLOG="$LOG."`stat log --printf="%y" | tr ':' '-' | tr ' ' '_' | awk -F '.' '{ print $1; }'`

log()
{
  echo "$PROG: $*"
}

loge()
{
  echo "$*"
}

logn()
{
  echo -n "$PROG: $*"
}

feedback()
{
  if [ $? -ne 0 ]; then
    loge failed.
  else
    loge ok.
  fi
}

error()
{
  echo "$PROG: $*"
  echo "$PROG: exiting."
  exit $RC_ERROR
}

# ------------------------------------------------------------------------------
# check if all variables in import.var are set accordingly
if [ -z "$DATAROOTDIR" -o -z "$RMANHOME" -o -z "$RMANSRC" -o -z "$TMP_DIR" ]; then
  error "failed loading configuration, please set all variables in $SCRIPT_DIR/../conf/import.var"
fi

# ------------------------------------------------------------------------------
# setup log
if [ -n "$IMPORT_SCRIPT_DIR" ]; then
  if [ -f $LOG ]; then
    log "old logfile found, moving to $OLDLOG"
    rm -f $OLDLOG
    mv $LOG $OLDLOG
  fi
  
  # all output that goes to stdout is redirected to log too
  log "redirecting all script output to $LOG"
  exec >  >(tee -a $LOG)
  exec 2> >(tee -a $LOG >&2)

  NOW=`date`
  log "starting import at $NOW"
  log ""
fi

# ------------------------------------------------------------------------------
# setup tmp dir
mkdir -p $TMP_DIR
if [ $? -ne 0 ]; then
  log "warning: failed creating temporary directory $TMP_DIR, using /tmp"
  export TMP_DIR=/tmp
fi

# ------------------------------------------------------------------------------
# dependency checks
#
check_rasdaman()
{
  which rasmgr > /dev/null
  if [ $? -ne 0 ]; then
    error "rasdaman not installed, please add rasdaman bin directory to the PATH."
  fi
  pgrep rasmgr > /dev/null
  if [ $? -ne 0 ]; then
    error "rasdaman not started, please start with start_rasdaman.sh"
  fi
  $RASCONTROL -x 'list srv -all' > /dev/null
  if [ $? -ne 0 ]; then
    error "no rasdaman servers started."
  fi
}

check_postgres()
{
  which psql > /dev/null
  if [ $? -ne 0 ]; then
    error "PostgreSQL missing, please add psql to the PATH."
  fi
  pgrep postgres > /dev/null
  if [ $? -ne 0 ]; then
    pgrep postmaster > /dev/null || error "The PostgreSQL service is not started."
  fi
  $PGSQL --list > /dev/null 2>&1
  if [ $? -eq 2 ]; then
    error "Wrong PostgreSQL credentials for current user"
  fi
}

check_netcdf()
{
  which ncdump > /dev/null
  if [ $? -ne 0 ]; then
    error "netcdf tools missing, please add ncdump and ncgen to the PATH."
  fi
}

check_wget()
{
  which wget > /dev/null
  if [ $? -ne 0 ]; then
    error "wget missing, please install."
  fi
}

check_netcdf()
{
  which ncdump > /dev/null
  if [ $? -ne 0 ]; then
    error "netcdf tools missing, please add ncdump to the PATH."
  fi
}

check_gdal()
{
  which gdal_translate > /dev/null
  if [ $? -ne 0 ]; then
    error "gdal missing, please add gdal_translate to the PATH."
  fi
}

check_nco()
{
  which ncks > /dev/null
  if [ $? -ne 0 ]; then
    error "NCO tools (http://nco.sourceforge.net/) missing, please add ncks to the PATH."
  fi
}

check_ncl()
{
  which ncl_convert2nc > /dev/null
  if [ $? -ne 0 ]; then
    error "NCL tools missing, please add ncl_convert2nc to the PATH. \
       The NCL tools can be downloaded from http://www.earthsystemgrid.org/dataset/ncl.html"
  fi
}

#
# print variables from a netcdf file in the form: "type name"
# arg 1: netcdf file
#
get_nc_vars()
{
  ncdump -h "$1" | grep "variables:" -A1000 | sed '/^\t\t.*/d' | sed 's/(.*//' | sed '/variables/d' | sed '/}/d' | sed 's/[ \t]*//' | sed 's/byte/char/g' | sed 's/int/long/g'
}

#
# put first word in variable FIRST, the rest in REST
# arg 1: a list of words
#
split_first()
{
  FIRST=`echo "$1" | awk '{ print $1; }'`
  REST=`echo "$1" | sed 's/^[^ ]* //'`
}

# -------------------------
# cleanup intermediate files
cleanup()
{
  rm -rf $TMP_DIR/*
}

# -------------------------
# move to next day
# arg1: year
# arg2: month
# arg3: day
# return: variables year, month, day
next_date()
{
  year=`date -d "$1-$2-$3 +1 day" +"%Y"`
  month=`date -d "$1-$2-$3 +1 day" +"%m"`
  day=`date -d "$1-$2-$3 +1 day" +"%d"`
}


# ------------------------------------------------------------------------------
# rasdaman administration
#
restart_rasdaman()
{
  logn "restarting rasdaman... "
  which stop_rasdaman.sh > /dev/null
  if [ $? -ne 0 ]; then
    sudo service rasdaman restart > /dev/null 2>&1
  else
    stop_rasdaman.sh > /dev/null 2>&1
    sleep 2
    start_rasdaman.sh > /dev/null 2>&1
  fi
  feedback
}

# ------------------------------------------------------------------------------
# restart postgres
#
restart_postgres()
{
  logn "restarting postgres... "
  sudo service postgresql restart > /dev/null 2>&1
  feedback
}


#
# load all modules
#
. "$SCRIPT_DIR"/rasql.sh
. "$SCRIPT_DIR"/petascope.sh
