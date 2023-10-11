#!/bin/sh
#
# @usage: `./csv-fetcher.sh --help`
# @author: Sing Yu Chan
# @version: `./csv-fetcher.sh --version`
#
# shellcheck disable=SC2155,SC3060

PROG_NAME="${0##*/}"
PROG_VER=20231011

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

_print_version() {
  local green='\e[0;32m'
  local clear='\e[0m'
  printf "${green}%s${clear}\n" "$PROG_VER"
}

_print_usage() {
  cat <<EOF
$PROG_NAME $PROG_VER
ops.sh exclusive csv data fetcher.

USAGE:
    $PROG_NAME [OPTIONS]

OPTIONS:
    -t, --type [FETCH_TYPE]       Fetch type, optional: daily-csv (default), daily-dm-csv,
                                                        daily-mariadb-csv, daily-oracle-csv.
    -m, --month [FETCH_MONTH]     Fetch month, default is current month.
    -T, --target <TARGET_FILE>    Targets and credential information.
    -s, --scp                     Use scp instead of curl.
    -v, --verbose                 Verbose logging.
    -V, --version                 Show version.
    -h, --help                    Show this help message then exit.
EOF
}

parse_args() {
  local args="$*"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -t | --type)
        FETCH_TYPE="$2"
        shift 2
        ;;
      -m | --month)
        FETCH_MONTH="$2"
        shift 2
        ;;
      -T | --target)
        TARGET_FILE="$2"
        shift 2
        ;;
      -s | --scp)
        USE_SCP=1
        shift 1
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
  debug "received arguments: $args"

  [ -n "$FETCH_TYPE" ] || FETCH_TYPE="daily-csv"
  [ -n "$FETCH_MONTH" ] || FETCH_MONTH="$(date +%Y-%m)"
  [ -n "$TARGET_FILE" ] || {
    error "\`-T\` parameter must be specified."
    exit 1
  }
  [ -z "$USE_SCP" ] || {
    warn "downloading csv via scp is not recommended, unless the server does not support sftp."
    command -v sshpass >/dev/null || {
      error "scp requires sshpass, but \`sshpass\` command not found."
      exit 1
    }
  }
}

get_csv_path() {
  local base="/srv/ops.sh"
  local dir="${FETCH_TYPE}_logs"
  local _f1="$FETCH_TYPE"
  local _f2="${2//./-}"
  local _f3="$FETCH_MONTH"
  local file="${_f1}_${_f2}_${_f3}.csv"
  echo "${base}/${dir}/${file}"
}

download_csv() {
  local user="${1%@*}"
  local host="${1##*@}"
  local path="$(get_csv_path "$1" "$host")"
  debug "target: ${user}@${host}:${path}"

  if curl -sSk --user "$user" "sftp://${host}/${path}" -O --create-dirs --output-dir "${FETCH_TYPE}_logs"; then
    info "[$host] => OK."
  else
    error "[$host] => NOK!"
  fi
}

download_csv_via_scp() {
  local user="${1%@*}"
  local host="${1##*@}"
  local path="$(get_csv_path "$1" "$host")"
  debug "target: ${user}@${host}:${path}"

  local output_dir="${FETCH_TYPE}_logs"
  [ -d "$output_dir" ] || mkdir -p "$output_dir"
  local username="${user%:*}"
  local password="${user##*:}"
  if sshpass -p "$password" scp -O -q -o "StrictHostKeyChecking=no" "${username}@${host}:${path}" "$output_dir" 2>/dev/null; then
    info "[$host] => OK."
  else
    error "[$host] => NOK!"
  fi
}

main() {
  while read -r target; do
    if [ "$USE_SCP" != 1 ]; then
      download_csv "$target"
    else
      download_csv_via_scp "$target"
    fi
  done <"$TARGET_FILE"
}

parse_args "$@"
main
