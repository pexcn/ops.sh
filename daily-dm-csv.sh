#!/bin/bash
#
# @usage: see @cron section
# @cron: `30 08 * * * root OUTPUT2LOG=1 LOGIN_INFO="SYSDBA/SYSDBA@127.0.0.1:5236" /srv/ops.sh/daily-dm-csv.sh`
# @author: Sing Yu Chan
# @version: 20230926-2
#
# shellcheck disable=SC2155

# workaround for PATH environment variable incomplete
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# dameng addition
DM_HOME=/dm/dmdbms
PATH=$PATH:$DM_HOME/bin
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$DM_HOME/bin
export LD_LIBRARY_PATH

OUTPUT2LOG="${OUTPUT2LOG:=0}"
LOGIN_INFO="${LOGIN_INFO:=SYSDBA/SYSDBA@127.0.0.1:5236}"

DM_PROCESS="dmserver"
DM_DATA_DIR="/dm/dmdata"

_exec_sql() {
  local sql="$1"
  LANG=en_US disql -S "$LOGIN_INFO" <<-EOF
	$sql
	EOF
}

_extract_value() {
  grep '-' -A 1 | tail -1 | awk '{print $2}'
}

_trim() {
  awk '{$1=$1};1'
}

_is_start_with() {
  local str="$1"
  local sub="$2"
  [[ $str == ${sub}* ]]
}

_ceil() {
  awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}'
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
  local p3=$(date +%Y-%m)
  echo "${p1}_${p2}_${p3}.csv"
}

get_all_sessions() {
  _exec_sql "SELECT COUNT(1) FROM SYS.V\$SESSIONS;" | _extract_value
}

get_active_sessions() {
  _exec_sql "SELECT COUNT(1) FROM SYS.V\$SESSIONS WHERE STATE='ACTIVE';" | _extract_value
}

get_cpu_cores() {
  # or `nproc --all`
  grep -c "^processor" /proc/cpuinfo
}

real_dm_cpu_usage() {
  local pid=$(pgrep $DM_PROCESS | head -1)
  ps -p "$pid" -o '%cpu' --no-headers | _trim
}

get_dm_cpu_usage() {
  local dm_cpu_usage=$(real_dm_cpu_usage)
  ! _is_start_with "$dm_cpu_usage" 0 || dm_cpu_usage=${dm_cpu_usage//0/1}
  echo "$dm_cpu_usage"
}

get_mem_size() {
  awk '/MemTotal/ { printf "%.1f\n", $2/1024/1024 }' /proc/meminfo | _ceil
}

get_dm_mem_usage() {
  local pid=$(pgrep $DM_PROCESS | head -1)
  ps -p "$pid" -o '%mem' --no-headers | _trim
}

get_tablespace_maximum_size() {
  echo "65T"
}

get_tablespace_size() {
  find $DM_DATA_DIR -type d -name "tablespace" -exec du -csh {} + | tail -1 | awk '{print $1}'
}

combine_output() {
  get_all_sessions
  get_active_sessions
  get_cpu_cores
  get_dm_cpu_usage
  get_mem_size
  get_dm_mem_usage
  get_tablespace_maximum_size
  get_tablespace_size
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
