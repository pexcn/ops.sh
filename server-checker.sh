#!/bin/sh
#
# @usage: `./server-checker.sh --help`
# @author: Sing Yu Chan
# @version: `./server-checker.sh --version`
#
# shellcheck disable=SC2155

PROG_NAME="${0##*/}"
PROG_VER=20240226

_get_time() {
  date '+%Y-%m-%d %T'
}

debug() {
  [ "$VERBOSE" = 1 ] || return 0
  local time="$(_get_time)"
  printf "[${time}] [DEBUG]: %s\n" "$*"
}

info() {
  local green='\e[0;32m'
  local clear='\e[0m'
  local time="$(_get_time)"
  printf "${green}[${time}] [INFO]: ${clear}%s\n" "$*"
}

warn() {
  local yellow='\e[1;33m'
  local clear='\e[0m'
  local time="$(_get_time)"
  printf "${yellow}[${time}] [WARN]: ${clear}%s\n" "$*" >&2
}

error() {
  local red='\e[0;31m'
  local clear='\e[0m'
  local time="$(_get_time)"
  printf "${red}[${time}] [ERROR]: ${clear}%s\n" "$*" >&2
}

execute() {
  local login="${1%@*}"
  local username="${login%%:*}"
  local password="${login#*:}"
  local host="${1##*@}"
  local args="$*"
  local cmd="${args#* }"
  debug "$cmd"
  # ref: https://stackoverflow.com/questions/37066540/bash-while-loop-is-not-looping
  sshpass -p "$password" ssh -n -q -o "StrictHostKeyChecking=no" -o "ConnectTimeout=5" "$username"@"$host" "$cmd"
}

_print_version() {
  local green='\e[0;32m'
  local clear='\e[0m'
  printf "${green}%s${clear}\n" "$PROG_VER"
}

_print_usage() {
  cat <<EOF
$PROG_NAME $PROG_VER
server checker.

USAGE:
    $PROG_NAME [OPTIONS]

OPTIONS:
    -t, --target <TARGET_FILE>    Targets and credential information.
    -o, --output <OUTPUT_FILE>    Path to output csv file.
    -v, --verbose                 Verbose logging.
    -V, --version                 Show version.
    -h, --help                    Show this help message then exit.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -t | --target)
        TARGET_FILE="$2"
        shift 2
        ;;
      -o | --output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      -v | --verbose)
        VERBOSE=1
        shift 1
        ;;
      -V | --version)
        _print_version
        exit 0
        ;;
      -h | --help)
        _print_usage
        exit 0
        ;;
      *)
        error "unknown option: $1"
        exit 2
        ;;
    esac
  done

  # parameters checking
  command -v sshpass >/dev/null || {
    error "$PROG_NAME requires sshpass, but \`sshpass\` command not found."
    exit 1
  }
  if [ -z "$TARGET_FILE" ]; then
    error "\`-t | --target\` parameter must be specified."
    exit 1
  fi
  if [ -n "$OUTPUT_FILE" ]; then
    local output_dir="$(dirname "$OUTPUT_FILE")"
    [ -d "$output_dir" ] || {
      warn "output directory does not exist, created it automatically."
      mkdir -p "$output_dir"
    }
    [ ! -f "$OUTPUT_FILE" ] || warn "output file existed, csv will be override to it."
  fi
}

CSV_HEADER="ip_address,cpu_usage,mem_total,mem_usage,mem_avail,mem_usage_pct,disk_total,disk_usage,disk_avail,disk_usage_pct,data_total,data_usage,data_avail,data_usage_pct"

_byte2gb() {
  awk '{printf "%.1f\n", $1/1024/1024/1024}'
}

_kb2gb() {
  awk '{printf "%.1f\n", $1/1024/1024}'
}

_ceil() {
  awk 'function ceil(x, y){y=int(x); return(x>y?y+1:y)} {print ceil($0)}'
}

_to_csv() {
  sed ':a;N;$!ba;s/\n/,/g'
}

_check_cpu_usage() {
  local token="$1"
  local cpu_usage_cmd="awk '{u=\$2+\$4; t=\$2+\$4+\$5; if (NR==1){u1=u; t1=t;} else printf \"%.1f\\n\", (\$2+\$4-u1) * 100 / (t-t1); }' <(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat)"
  local cpu_usage="$(execute "$token" "$cpu_usage_cmd")"
  echo "${cpu_usage:=0}"
}

_check_mem_total() {
  local token="$1"
  local mem_total_cmd="awk '/MemTotal/ { print \$2*1024 }' /proc/meminfo"
  local mem_total="$(execute "$token" "$mem_total_cmd")"
  echo "${mem_total:=0}"
}

_check_mem_avail() {
  local token="$1"
  local mem_avail_cmd="awk '/MemAvailable/ { print \$2*1024 }' /proc/meminfo"
  local mem_avail="$(execute "$token" "$mem_avail_cmd")"
  echo "${mem_avail:=0}"
}

_check_mem_usage() {
  local token="$1"
  local mem_total="$(_check_mem_total "$token")"
  local mem_avail="$(_check_mem_avail "$token")"
  echo $((mem_total - mem_avail))
}

_check_mem_usage_pct() {
  local token="$1"
  local mem_total="$(_check_mem_total "$token")"
  local mem_usage="$(_check_mem_usage "$token")"
  [ "$mem_total" != 0 ] || mem_total=1
  echo $((mem_usage * 100 / mem_total))%
}

_get_disk_info() {
  local token="$1"
  # see also the `-P | --portability` option
  local cmd="df -l -t vfat -t xfs -t ext4 --output=size,used,avail,pcent --total | tail -1"
  execute "$token" "$cmd"
}

_check_disk_total() {
  local token="$1"
  local val="$(_get_disk_info "$token" | awk '{print $1}')"
  echo "${val:=0}"
}

_check_disk_usage() {
  local token="$1"
  local val="$(_get_disk_info "$token" | awk '{print $2}')"
  echo "${val:=0}"
}

_check_disk_avail() {
  local token="$1"
  local val="$(_get_disk_info "$token" | awk '{print $3}')"
  echo "${val:=0}"
}

_check_disk_usage_pct() {
  local token="$1"
  local val="$(_get_disk_info "$token" | awk '{print $4}')"
  echo "${val:=0%}"
}

_get_data_info() {
  local token="$1"
  local disk_val="$(_get_disk_info "$token")"
  # see also the `-P | --portability` option
  local root_cmd="df -l -t vfat -t xfs -t ext4 --output=size,used,avail,pcent --total / /boot | tail -1"
  local root_val="$(execute "$token" "$root_cmd")"
  echo | awk \
    -v disk_size="$(echo "$disk_val" | awk '{print $1}')" \
    -v root_size="$(echo "$root_val" | awk '{print $1}')" \
    -v disk_used="$(echo "$disk_val" | awk '{print $2}')" \
    -v root_used="$(echo "$root_val" | awk '{print $2}')" \
    -v disk_avail="$(echo "$disk_val" | awk '{print $3}')" \
    -v root_avail="$(echo "$root_val" | awk '{print $3}')" \
    '{
      if (disk_size==root_size) {
        disk_size+=1
      }
      printf "%s %s %s %.f%\n", disk_size-root_size, disk_used-root_used, disk_avail-root_avail, (disk_used-root_used)*100/(disk_size-root_size)
    }'
}

_check_data_total() {
  local token="$1"
  local val="$(_get_data_info "$token" | awk '{print $1}')"
  echo "${val:=0}"
}

_check_data_usage() {
  local token="$1"
  local val="$(_get_data_info "$token" | awk '{print $2}')"
  echo "${val:=0}"
}

_check_data_avail() {
  local token="$1"
  local val="$(_get_data_info "$token" | awk '{print $3}')"
  echo "${val:=0}"
}

_check_data_usage_pct() {
  local token="$1"
  local val="$(_get_data_info "$token" | awk '{print $4}')"
  echo "${val:=0%}"
}

_check_server() {
  local token="$1"
  local ip_address="${token##*@}"
  echo "$ip_address"
  _check_cpu_usage "$token"
  _check_mem_total "$token" | _byte2gb | _ceil
  _check_mem_usage "$token" | _byte2gb
  _check_mem_avail "$token" | _byte2gb
  _check_mem_usage_pct "$token"
  _check_disk_total "$token" | _kb2gb | _ceil
  _check_disk_usage "$token" | _kb2gb
  _check_disk_avail "$token" | _kb2gb
  _check_disk_usage_pct "$token"
  _check_data_total "$token" | _kb2gb | _ceil
  _check_data_usage "$token" | _kb2gb
  _check_data_avail "$token" | _kb2gb
  _check_data_usage_pct "$token"
}

server_check() {
  [ -z "$OUTPUT_FILE" ] || echo "$CSV_HEADER" >"$OUTPUT_FILE"
  while read -r target; do
    # ignore empty lines
    [ -n "$target" ] || continue
    # ignore comment lines
    [ -n "${target%%#*}" ] || continue
    # output to csv
    if [ -n "$OUTPUT_FILE" ]; then
      _check_server "$target" | _to_csv | tee -a "$OUTPUT_FILE"
    else
      _check_server "$target" | _to_csv | column -s ',' -t
    fi
  done <"$TARGET_FILE"
}

parse_args "$@"
server_check
