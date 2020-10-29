#!/bin/bash

# 2020, Laurent Ghigonis <ooookiwi@gmail.com>

usageexit() {
	cat <<-_EOF
~ ssh quick tunnel, ssh -w friendly ~
usage: $0 <remote_ip> (start | stop | status) [<routed_ip>]
_EOF
	exit 0
}

trace() { echo "# $*"; "$@"; }
fatal() { msg="$1"; echo "[!] error: $msg"; exit 1; }

tun_stop() {
	flag="$1"
	[[ "$flag" = "ok" ]] && echo -n "[+] " || echo -n -e "[!] error detected, "
	echo "stopping tunnel"
	trace pkill -x -f "$cmd_start_tun" ||true
	trace sudo ip l d dev $tun_local 2>/dev/null ||true
	trace ssh -T root@$remote "ip l del dev $tun_remote 2>/dev/null" ||true
	if [ ! -z "$routed_ip" ]; then
		# XXX we will be leaving remote gwiface forwarding to 1, even if it was not set initially
		trace ssh -T root@$remote "gwiface=\$(ip r get $routed_ip |head -n1 |sed 's/.*dev \([^ ]*\).*/\1/') && iptables -t nat -D POSTROUTING -s $TUN_LOCAL_IP -o \$gwiface -j MASQUERADE 2>/dev/null" ||true
	fi
	[[ "$flag" = "ok" ]] && echo "[*] OK, ssh tunnel to $remote is stopped" || echo "[!] failed to establish tunnel with $remote"
}

tun_status() {
	echo -n "interface $tun_local exists on local  : "
	ip_local=$(ip -o a s dev $tun_local 2>/dev/null |grep 'inet ' |awk '{print $4}')
	[ -z "$ip_local" ] && echo no || echo yes $ip_local
	echo -n "interface $tun_remote exists on remote : "
	ip_remote=$(ssh -T $remote "ip -o a s dev $tun_remote 2>/dev/null |grep 'inet ' |awk '{print \$4}'")
	[ -z "$ip_remote" ] && echo no || echo yes $ip_remote
	echo -n "tunnel running                  : "
	pgrep -x -f "$cmd_start_tun" >/dev/null && running=1 || running=0
	[ $running -eq 1 ] && echo yes || echo no
	echo -n "testing ping $TUN_REMOTE_IP       : "
	if [ $running -eq 1 ]; then
		ping -w 4 -c1 $TUN_REMOTE_IP >/dev/null && echo ok || (echo fail; return 1)
	else
		echo skipped
	fi
}

set -e

TUN_LOCAL_NUM=${TUN_LOCAL_NUM:-0}
TUN_LOCAL_IP="${TUN_LOCAL_IP:-192.168.21.1}"
TUN_REMOTE_NUM=${TUN_REMOTE_NUM:-0}
TUN_REMOTE_IP="${TUN_REMOTE_IP:-192.168.21.2}"

tun_local="tun$TUN_LOCAL_NUM"
tun_remote="tun$TUN_REMOTE_NUM"
local_user=$(id -u -n)

[ $# -lt 2 -o $# -gt 3 ] && usageexit
remote="$1"
action="$2"
[ $# -eq 3 ] && routed_ip="$3"
# -S none: disable ControlPath so the tunnel is not dependent of external connections
cmd_start_tun="ssh -S none -N -T -f -w $TUN_LOCAL_NUM:$TUN_REMOTE_NUM $remote"
cat <<-_EOF
parameters:
   TUN_LOCAL_NUM=${TUN_LOCAL_NUM}
   TUN_LOCAL_IP="${TUN_LOCAL_IP}"
   TUN_REMOTE_NUM=${TUN_REMOTE_NUM}
   TUN_REMOTE_IP="${TUN_REMOTE_IP}"

_EOF

case $action in
start)
	trap tun_stop EXIT
	echo "[+] getting remote informations"
	[[ $(ssh -T root@$remote "id -u -n") != "root" ]] && fatal "you must have root access on the remote machine"
	remote_user=$(ssh -T $remote "id -u -n")
	echo "remote_user: $remote_user"
	echo "[+] creating local tunnel interface"
	trace sudo ip l d dev $tun_local 2>/dev/null ||true
	trace sudo ip tuntap add $tun_local mode tun user $local_user
	trace sudo ip a a $TUN_LOCAL_IP/30 dev $tun_local
	trace sudo ip l s up dev $tun_local
	echo "[+] creating remote tunnel interface"
	trace ssh -T root@$remote "ip l del $tun_remote 2>/dev/null; ip tuntap add $tun_remote mode tun user $remote_user; ip a a $TUN_REMOTE_IP/30 dev $tun_remote && ip l s up dev $tun_remote"
	echo "[+] starting tunnel"
	trace $cmd_start_tun
	tun_status
	if [ ! -z "$routed_ip" ]; then
		echo "[+] adding local route"
		trace sudo ip r a $routed_ip via $TUN_REMOTE_IP
		echo "[+] setup routing on remote"
		trace ssh -T root@$remote "gwiface=\$(ip r get $routed_ip |head -n1 |sed 's/.*dev \([^ ]*\).*/\1/') && sysctl -w net.ipv4.conf.\$(echo \$gwiface |tr '.' '/').forwarding=1 && sysctl -w net.ipv4.conf.$tun_remote.forwarding=1 && iptables -t nat -A POSTROUTING -s $TUN_LOCAL_IP -o \$gwiface -j MASQUERADE"
	fi
	trap - EXIT
	echo "[*] OK, tunnel is established to $remote as $TUN_REMOTE_IP"
	;;
stop)
	tun_stop ok
	;;
status)
	tun_status
	;;
*)
	usageexit
	;;
esac
