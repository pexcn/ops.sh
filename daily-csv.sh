#!/bin/bash
#
# @usage: see @cron section
# @cron: `30 08 * * * root /srv/ops.sh/daily-csv.sh`
# @author: Sing Yu Chan
# @version: 20230925
#
# shellcheck disable=SC2155

OUTPUT2LOG="${OUTPUT2LOG:=0}"

_ceil() {
  awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}'
}

_is_start_with() {
  local str="$1"
  local sub="$2"
  [[ $str == ${sub}* ]]
}

_byte2gb() {
  awk '{ printf "%.2f\n", $1/1024/1024; }'
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

real_cpu_usage() {
  awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.2f\n", ($2+$4-u1) * 100 / (t-t1); }' <(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat)
}

get_cpu_cores() {
  # or `nproc --all`
  grep -c "^processor" /proc/cpuinfo
}

get_cpu_usage() {
  # another way: `top -bn1 | grep load | awk '{printf "%.2f\n", $(NF-2)}'`
  local cpu_usage=$(real_cpu_usage)
  ! _is_start_with "$cpu_usage" 0 || cpu_usage=${cpu_usage//0/1}
  echo "$cpu_usage"
}

get_mem_size() {
  awk '/MemTotal/ { printf "%.1f\n", $2/1024/1024 }' /proc/meminfo | _ceil
}

get_mem_usage() {
  local mem_size=$(get_mem_size)
  local mem_avail=$(get_mem_available)
  awk "BEGIN { printf \"%.2f\n\", ${mem_size}-${mem_avail} }"
}

get_mem_available() {
  awk '/MemAvailable/ { printf "%.1f\n", $2/1024/1024 }' /proc/meminfo
}

get_disk_info() {
  # see also the `-P` option
  df -l -t vfat -t xfs -t ext4 --output=size,used,avail,pcent --total | tail -1
}

get_disk_size() {
  get_disk_info | awk '{print $1}' | _byte2gb | _ceil
}

get_disk_usage() {
  get_disk_info | awk '{print $2}' | _byte2gb
}

get_disk_available() {
  get_disk_info | awk '{print $3}' | _byte2gb
}

get_disk_usage_percent() {
  get_disk_info | awk '{print $4}'
}

combine_output() {
  get_cpu_cores
  get_cpu_usage
  get_mem_size
  get_mem_usage
  get_mem_available
  get_disk_size
  get_disk_usage
  get_disk_available
  get_disk_usage_percent
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
