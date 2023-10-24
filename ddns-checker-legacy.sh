#!/bin/sh
set -o pipefail

_get_time() {
  date '+%Y-%m-%d %T'
}

info() {
  local green='\e[0;32m'
  local clear='\e[0m'
  local time=$(_get_time)
  printf "${green}[${time}] [INFO]: ${clear}%s\n" "$*"
}

warn() {
  local yellow='\e[1;33m'
  local clear='\e[0m'
  local time=$(_get_time)
  printf "${yellow}[${time}] [WARN]: ${clear}%s\n" "$*" >&2
}

_split_by_space() {
  [ -n "$1" ] || return 0
  echo "$1" | tr ',' ' '
}

_get_addr_by_domain() {
  local domain="$1"
  local dns="${2:-119.29.29.29}"
  nslookup -type=a $domain $dns | grep "Address:" | awk '{print $2}' | tail -n 1 || cat /tmp/${1} 2>/dev/null
}

ip_changed_callback() {
  # TODO: bad code
  if [ "$1" = "example.com" ]; then
    sleep 180
    /srv/restart-container.sh nginx
  fi
}

do_check() {
  local old_ip=$(cat /tmp/${1} 2>/dev/null)
  local new_ip=$(_get_addr_by_domain "$1")

  if [ "$old_ip" != "$new_ip" ]; then
    warn "[${domain}]: ip changed: ${old_ip:-NULL} -> ${new_ip:-NULL}"
    echo "$new_ip" > /tmp/${1}
    ip_changed_callback "$1"
  else
    info "[${domain}]: ip not changed."
  fi
}

ddns_checker() {
  local domains="$@"
  for domain in $(_split_by_space "$domains"); do
    do_check $domain
    sleep 1
  done
}

ddns_checker "$@"
