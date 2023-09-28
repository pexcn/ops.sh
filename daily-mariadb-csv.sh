#!/bin/bash
#
# @usage: see @cron section
# @cron: `30 08 * * * root OUTPUT2LOG=1 LOGIN_INFO="root/password@127.0.0.1:3306" /srv/ops.sh/daily-mariadb-csv.sh`
# @author: Sing Yu Chan
# @version: 20230928
#
# shellcheck disable=SC2155

# workaround for PATH environment variable incomplete
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

OUTPUT2LOG="${OUTPUT2LOG:=0}"
LOGIN_INFO="${LOGIN_INFO:=root/password@127.0.0.1:3306}"

MARIADB_PROCESS="mariadbd"

_exec_sql() {
  local token=${LOGIN_INFO%@*}
  local server=${LOGIN_INFO##*@}
  local user=${token%/*}
  local password=${token##*/}
  local host=${server%:*}
  local port=${server##*:}
  local sql="$1"
  docker exec -i mariadb mysql -u"$user" -p"$password" -h"$host" -P"$port" -N <<-EOF
	$sql
	EOF
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

get_max_connections() {
  # a.k.a.: `SHOW GLOBAL STATUS LIKE 'Max_used_connections';`
  _exec_sql "SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME='Max_used_connections';"
}

get_cur_connections() {
  # a.k.a.: `SHOW GLOBAL STATUS LIKE 'Threads_connected';`
  _exec_sql "SELECT VARIABLE_VALUE FROM INFORMATION_SCHEMA.GLOBAL_STATUS WHERE VARIABLE_NAME='Threads_connected';"
}

get_cpu_cores() {
  # or `nproc --all`
  grep -c "^processor" /proc/cpuinfo
}

real_mariadb_cpu_usage() {
  local pid=$(pgrep $MARIADB_PROCESS | head -1)
  ps -p "$pid" -o '%cpu' --no-headers | _trim
}

get_mariadb_cpu_usage() {
  local mariadb_cpu_usage=$(real_mariadb_cpu_usage)
  ! _is_start_with "$mariadb_cpu_usage" 0 || mariadb_cpu_usage=${mariadb_cpu_usage//0/1}
  echo "$mariadb_cpu_usage"
}

get_mem_size() {
  awk '/MemTotal/ { printf "%.1f\n", $2/1024/1024 }' /proc/meminfo | _ceil
}

get_mariadb_mem_usage() {
  local pid=$(pgrep $MARIADB_PROCESS | head -1)
  ps -p "$pid" -o '%mem' --no-headers | _trim
}

get_db_size() {
  _exec_sql "SELECT REPLACE(SYS.FORMAT_BYTES(SUM(SIZE)),'i','') FROM (SELECT SUM(DATA_LENGTH + INDEX_LENGTH) AS SIZE FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('information_schema','mysql','performance_schema','sys') GROUP BY TABLE_SCHEMA) T;"
}

combine_output() {
  get_max_connections
  get_cur_connections
  get_cpu_cores
  get_mariadb_cpu_usage
  get_mem_size
  get_mariadb_mem_usage
  get_db_size
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
