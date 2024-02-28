#!/bin/sh
#
# OS initialize script for "CentOS 7"
#

_get_os() {
  case "$(grep "^ID=" /etc/os-release)" in
    ID=\"centos\") os=centos ;;
    ID=\"kylin\") os=kylin ;;
    ID=\"neokylin\") os=neokylin ;;
    *) os="unknown" ;;
  esac
  echo $os
}

_get_default_iface_addr() {
  ip route get 8.8.8.8 | sed 's/^.*src \([^ ]*\).*$/\1/;q'
}

check_env() {
  # shellcheck disable=SC3028
  [ "$EUID" = 0 ] || {
    echo "please run as root."
    exit 1
  }
  ! [ -f /.initialized ] || {
    echo "os has been initialized."
    exit 2
  }
  [ "$(_get_os)" = "$1" ] || {
    echo "os does not support."
    exit 3
  }
}

set_hostname() {
  local hostname="$1"
  [ -n "$hostname" ] || {
    echo "the hostname parameter must be specified."
    exit 255
  }
  hostnamectl set-hostname --static "$hostname"
  hostnamectl set-hostname --pretty "$hostname"
  hostnamectl set-hostname --transient "$hostname"

  cat <<-EOF >>/etc/hosts

	$(_get_default_iface_addr) $hostname
	EOF
}

update_bashrc() {
  cat <<-EOF >>/root/.bashrc

	PS1='\[\033[01;32m\]\u\[\033[01;33m\]@\[\033[01;31m\]\h\[\033[00m\] \[\033[01;34m\]\w\[\033[00m\] \\$ '
	export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "
	EOF
}

set_sysctl() {
  cat <<-EOF >/etc/sysctl.d/80-optimize.conf
	# system tuning
	vm.swappiness = 30
	fs.file-max = 1048576
	# tcp tuning
	net.ipv4.tcp_mtu_probing = 1
	net.ipv4.tcp_fin_timeout = 30
	net.ipv4.tcp_max_tw_buckets = 5000
	net.ipv4.tcp_syncookies = 1
	net.ipv4.tcp_tw_reuse = 1
	net.ipv4.tcp_tw_recycle = 0
	net.ipv4.tcp_keepalive_time = 600
	net.ipv4.tcp_max_syn_backlog = 8192
	net.ipv4.tcp_slow_start_after_idle = 0
	net.ipv4.tcp_orphan_retries = 1
	net.ipv4.ip_local_port_range = 10001 65000
	net.ipv4.ip_unprivileged_port_start = 0
	net.core.netdev_max_backlog = 32768
	net.core.somaxconn = 4096
	net.netfilter.nf_conntrack_max = 32768
	#net.ipv4.tcp_fastopen = 3
	EOF
  sysctl -q --system
}

set_limits() {
  cat <<-EOF >/etc/security/limits.d/90-limits.conf
	* soft nofile 1048576
	* hard nofile 1048576
	root soft nofile 1048576
	root hard nofile 1048576
	* soft nproc 51200
	* hard nproc 51200
	root soft nproc 51200
	root hard nproc 51200
	EOF
  cat <<-EOF >>/etc/systemd/system.conf
	DefaultLimitNOFILE=1048576
	DefaultLimitNPROC=51200
	EOF
  cat <<-EOF >>/etc/systemd/user.conf
	DefaultLimitNOFILE=1048576
	DefaultLimitNPROC=51200
	EOF
}

set_misc() {
  chmod -x /etc/cron.daily/mlocate
}

finish_work() {
  date +%s >/.initialized
}

check_env centos
set_hostname "$1"
update_bashrc
set_sysctl
set_limits
set_misc
finish_work
