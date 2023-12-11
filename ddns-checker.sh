#!/bin/sh
#
# @usage: `./ddns-checker.sh --help`
# @author: Sing Yu Chan
# @version: `./ddns-checker.sh --version`
#
# shellcheck disable=SC2155

PROG_NAME="${0##*/}"
PROG_VER=20231024

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
  local time="$(date '+%Y-%m-%d %T')"
  printf "${green}[${time}] [INFO]: ${clear}%s\n" "$*"
}

warn() {
  local yellow='\e[1;33m'
  local clear='\e[0m'
  local time="$(date '+%Y-%m-%d %T')"
  printf "${yellow}[${time}] [WARN]: ${clear}%s\n" "$*" >&2
}

error() {
  local red='\e[0;31m'
  local clear='\e[0m'
  local time="$(date '+%Y-%m-%d %T')"
  printf "${red}[${time}] [ERROR]: ${clear}%s\n" "$*" >&2
}

_get_addr_by_domain() {
  local domain="$1"
  local dns="$2"
  if [ -z "$dns" ]; then
    nslookup -type=a "$domain" | grep "Address:" | awk '{print $2}' | tail -n 1
  else
    nslookup -type=a "$domain" "$dns" | grep "Address:" | awk '{print $2}' | tail -n 1
  fi
}

_is_ip_connectivity() {
  local ip="$1"
  ping -c 4 -W 1 -q "$ip" >/dev/null 2>&1
}

_print_usage() {
  cat <<EOF
$PROG_NAME $PROG_VER
DDNS checker, used to ensure network connectivity.

USAGE:
    $PROG_NAME [OPTIONS]

OPTIONS:
    -d, --domain <DOMAIN>       Detect DDNS domain.
    -w, --watch <IP_ADDR>       IP address to detect peer connectivity.
    -D, --dns [NAMESERVER]      DNS server to resolve domain, use system DNS by default.
    -a, --action <COMMANDS>     Actions when network blocked is detected.
    -r, --retry [COUNT]         Max retries of actions, default is 10 times
    -i, --interval [SECONDS]    Network connectivity check interval, default is 5 mins.
    -s, --strict                Strict mode, the target IP must be pingable.
    -v, --verbose               Verbose logging.
    -V, --version               Show version.
    -h, --help                  Show this help message then exit.
EOF
}

parse_args() {
  local args="$*"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -d | --domain)
        DOMAIN="$2"
        shift 2
        ;;
      -w | --watch)
        WATCH_IP="$2"
        shift 2
        ;;
      -D | --dns)
        DNS="$2"
        shift 2
        ;;
      -a | --action)
        ACTION="$2"
        shift 2
        ;;
      -r | --retry)
        RETRY="$2"
        shift 2
        ;;
      -i | --interval)
        INTERVAL="$2"
        shift 2
        ;;
      -s | --strict)
        STRICT=1
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

  # parameters initialize
  [ -n "$RETRY" ] || RETRY=10
  [ -n "$INTERVAL" ] || INTERVAL=300

  # parameters checking
  if [ -z "$DOMAIN" ]; then
    error "\`-d | --domain\` parameter must be specified."
    exit 1
  fi
  if [ -z "$WATCH_IP" ]; then
    error "\`-w | --watch\` parameter must be specified."
    exit 1
  fi
  if [ -z "$ACTION" ]; then
    error "\`-a | --action\` parameter must be specified."
    exit 1
  fi
  if [ "$RETRY" -gt 50 ]; then
    warn "if max retries exceed 50 times, the effect may not be good."
  fi
  if [ "$INTERVAL" -lt 60 ]; then
    warn "detection interval cannot be too short, force set to 60 seconds."
    INTERVAL=60
  fi
  if [ "$STRICT" = 1 ]; then
    warn "strict mode is enabled, please make sure the target ip can be pingable."
  fi
}

ddns_check() {
  while true; do
    local cur_ip new_ip retry_cnt=1
    new_ip="$(_get_addr_by_domain "$DOMAIN" "$DNS")"
    debug "[${DOMAIN}] now resolved to: ${new_ip}"

    if [ "$cur_ip" != "$new_ip" ]; then
      info "[${DOMAIN}] ip changed: ${cur_ip:-NULL} -> ${new_ip:-NULL}"
      cur_ip=$new_ip
    fi

    if ! _is_ip_connectivity "$cur_ip"; then
      if [ "$STRICT" = 1 ]; then
        warn "ddns ip blocked detected, trying to resolve again."
        continue
      fi
    fi

    while ! _is_ip_connectivity "$WATCH_IP"; do
      warn "network blocked detected, executing the $retry_cnt time action..."
      eval "$ACTION"
      debug "action exit code: $?"
      retry_cnt=$((retry_cnt + 1))
      if [ $retry_cnt -gt "$RETRY" ]; then
        warn "max retries of actions reached, skip it."
        break
      fi
    done

    debug "waiting check interval $INTERVAL seconds..."
    sleep "$INTERVAL"
  done
}

parse_args "$@"
ddns_check
