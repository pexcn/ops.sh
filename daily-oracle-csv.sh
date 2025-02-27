#!/bin/bash
#
# @usage: see @cron section
# @cron: `30 08 * * * root OUTPUT2LOG=1 LOGIN_INFO="SYSTEM/password@127.0.0.1:1521/DEV" /srv/ops.sh/daily-oracle-csv.sh`
# @author: Sing Yu Chan
# @version: 20250227
#
# shellcheck disable=SC2155

# workaround for PATH environment variable incomplete
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

OUTPUT2LOG="${OUTPUT2LOG:=0}"
LOGIN_INFO="${LOGIN_INFO:=SYSTEM/password@127.0.0.1:1521/DEV}"

ORACLE_CONTAINER="oracle-ee"

_exec_sql() {
  local sql="$1"
  docker exec -i $ORACLE_CONTAINER sqlplus -S /NOLOG <<-EOF
	SET HEADING OFF;
	SET FEEDBACK OFF;
	SET NEWPAGE NONE;
	SET MARK CSV ON QUOTE OFF;
	CONNECT $LOGIN_INFO
	$sql
	exit;
	EOF
}

_ceil() {
  awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}'
}

_is_start_with() {
  local str="$1"
  local sub="$2"
  [[ $str == ${sub}* ]]
}

_to_csv() {
  sed ':a;N;$!ba;s/\n/,/g'
}

_get_default_iface() {
  ip route get 8.8.8.8 | sed 's/^.*src \([^ ]*\).*$/\1/;q'
}

_get_log_dir() {
  local cur_dir=$(dirname "$0")
  local sub_dir=$(basename "$0" .sh)
  echo "${cur_dir}/${sub_dir}_logs"
}

_get_log_file() {
  local p1=$(basename "$0" .sh)
  local p2=$(_get_default_iface | sed 's/\./-/g')
  local p3=${LOGIN_INFO##*/}
  local p4=$(date +%Y-%m)
  echo "${p1}_${p2}_${p3}_${p4}.csv"
}

get_date() {
  date +%Y%m%d
}

get_all_sessions() {
  _exec_sql "SELECT COUNT(1) FROM V\$SESSION;"
}

get_active_sessions() {
  _exec_sql "SELECT COUNT(1) FROM V\$SESSION WHERE STATUS='ACTIVE';"
}

get_cpu_cores() {
  # or `nproc --all`
  grep -c "^processor" /proc/cpuinfo
}

get_oracle_cpu_usage() {
  docker stats $ORACLE_CONTAINER --no-stream --format "{{.CPUPerc}}"
}

get_mem_size() {
  awk '/MemTotal/ { printf "%.1f\n", $2/1024/1024 }' /proc/meminfo | _ceil
}

get_oracle_mem_usage() {
  docker stats $ORACLE_CONTAINER --no-stream --format "{{.MemPerc}}"
}

get_tablespace_maximum_size() {
  _exec_sql "SELECT ROUND(SUM(MAXBYTES)/1024/1024/1024)||' GB' FROM DBA_DATA_FILES WHERE TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX','UNDOTBS1');"
}

get_tablespace_total_size() {
  #_exec_sql "SELECT ROUND(SUM(SUM(BYTES))/1024/1024/1024,2)||' GB' FROM DBA_DATA_FILES GROUP BY TABLESPACE_NAME HAVING TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX','UNDOTBS1');"
  local value=$(_exec_sql "SELECT ROUND(SUM(BYTES)/1024/1024/1024,2)||' GB' FROM DBA_DATA_FILES WHERE TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX','UNDOTBS1');")
  ! _is_start_with "$value" . || value=${value//./0.}
  echo "$value"
}

#get_tablespace_free_size() {
#  _exec_sql "SELECT ROUND(SUM(SUM(BYTES))/1024/1024/1024,2)||' GB' FROM DBA_FREE_SPACE GROUP BY TABLESPACE_NAME HAVING TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX','UNDOTBS1');"
#}

get_tablespace_used_percentage() {
  local value=$(_exec_sql "SELECT ROUND((SUM(BYTES)/SUM(MAXBYTES))*100,2)||'%' FROM DBA_DATA_FILES WHERE TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX','UNDOTBS1');")
  ! _is_start_with "$value" . || value=${value//./0.}
  echo "$value"
}

combine_output() {
  get_date
  get_all_sessions
  get_active_sessions
  get_cpu_cores
  get_oracle_cpu_usage
  get_mem_size
  get_oracle_mem_usage
  get_tablespace_maximum_size
  get_tablespace_total_size
  get_tablespace_used_percentage
}

main() {
  if [ "$OUTPUT2LOG" = 1 ]; then
    local log_dir=$(_get_log_dir)
    local log_file=$(_get_log_file)
    [ -d "$log_dir" ] || mkdir "$log_dir"
    combine_output | _to_csv | tee -a "$log_dir/$log_file"
  else
    combine_output | _to_csv
  fi
}

main
