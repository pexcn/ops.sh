#!/bin/sh
#
# @usage: `./date-checker.sh --help`
# @author: Sing Yu Chan
# @version: `./date-checker.sh --version`
#
# shellcheck disable=SC2155,SC3024,SC3045

PROG_NAME="${0##*/}"
PROG_VER=20240207

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
date checker.

USAGE:
    $PROG_NAME [OPTIONS]

OPTIONS:
    -t, --target <TARGET_FILE>    Targets and credential information.
    -o, --offset <OFFSET_SEC>     Allowed seconds of offset from local machine, the default value is 60.
    -c, --callback <CALLBACK>     Callback function when warnings.
    -w, --warning                 Only print host with incorrect time.
    -v, --verbose                 Verbose logging.
    -V, --version                 Show version.
    -h, --help                    Show this help message then exit.
EOF
}

_callback() {
  local login="${1%@*}"
  local username="${login%%:*}"
  local password="${login#*:}"
  local host="${1##*@}"
  local cmd="$CALLBACK"
  # FIXME: no output?
  sshpass -p "$password" ssh -n -q -o "StrictHostKeyChecking=no" -o "ConnectTimeout=3" "$username"@"$host" "$cmd"
}

_check_date() {
  local login="${1%@*}"
  local username="${login%%:*}"
  local password="${login#*:}"
  local host="${1##*@}"
  # ref: https://stackoverflow.com/questions/37066540/bash-while-loop-is-not-looping
  local server_time="$(sshpass -p "$password" ssh -n -q -o "StrictHostKeyChecking=no" -o "ConnectTimeout=3" "$username"@"$host" "date '+%s'" 2>/dev/null)"
  local local_time="$(date '+%s')"
  local diff_sec=$((server_time-local_time))
  local diff_sec_abs=${diff_sec#-}
  debug "username: ${username}, password: ${password}, host: ${host}"
  if [ "$diff_sec_abs" -gt "$OFFSET_SEC" ]; then
    warn "$host -> [NOK], offset ${diff_sec}s"
    [ -z "$CALLBACK" ] || _callback "$1"
  else
    [ "$WARNING_ONLY" = 1 ] || info "$host -> [OK], offset ${diff_sec}s"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -t | --target)
        TARGET_FILE="$2"
        shift 2
        ;;
      -o | --offset)
        OFFSET_SEC="$2"
        shift 2
        ;;
      -c | --callback)
        CALLBACK="$2"
        shift 2
        ;;
      -w | --warning)
        WARNING_ONLY=1
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

  # parameters initialize
  [ -n "$OFFSET_SEC" ] || OFFSET_SEC=60
  [ -n "$WARNING_ONLY" ] || WARNING_ONLY=0
  [ -n "$VERBOSE" ] || VERBOSE=0

  # parameters checking
  command -v sshpass >/dev/null || {
    error "$PROG_NAME requires sshpass, but \`sshpass\` command not found."
    exit 1
  }
  if [ -z "$TARGET_FILE" ]; then
    error "\`-t | --target\` parameter must be specified."
    exit 1
  fi
}

date_check() {
  while read -r target; do
    # ignore empty lines
    [ -n "$target" ] || continue
    # ignore comment lines
    [ -n "${target%%#*}" ] || continue
    _check_date "$target"
  done <"$TARGET_FILE"
}

parse_args "$@"
date_check
