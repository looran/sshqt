#!/bin/bash

# 2020-2022, Laurent Ghigonis <ooookiwi@gmail.com>

usageexit() {
	cat <<-_EOF
~ ssh quick tunnel ~
usage: $(basename $0) <remote_ip> (start | stop | status) [<routed_ip>]
_EOF
	print_env_params
	exit 0
}

trace() { echo "# $*" >&2; "$@"; }
fatal() { msg="$1"; echo "[!] error: $msg"; exit 1; }

tun_stop() {
	reason="$1"
	[[ "$reason" = "user" ]] && echo -n "[+] " || echo -n -e "[!] error detected, "
	echo "stopping tunnel"
	trace pkill -x -f "$cmd_start_tun" ||true
	trace ip l d dev $tun_local 2>/dev/null ||true
	trace ssh $SSHQT_SSH_OPTS -T $remote "ip l del dev $tun_remote 2>/dev/null" ||true
	if [ ! -z "$routed_ip" ]; then
		# XXX we are leaving remote gwiface forwarding to 1, even if it was not set initially
		trace ssh $SSHQT_SSH_OPTS -T $remote "gwiface=\$(ip r get $routed_ip |head -n1 |sed 's/.*dev \([^ ]*\).*/\1/') && iptables -t nat -D POSTROUTING -s $SSHQT_LOCAL_IP -o \$gwiface -j MASQUERADE 2>/dev/null" ||true
	fi
	[[ "$reason" = "user" ]] && echo "[*] OK, ssh tunnel to $remote is stopped" || echo "[!] failed to establish tunnel with $remote"
}

tun_status() {
	echo -n "interface $tun_local exists on local  : "
	ip_local=$(ip -o a s dev $tun_local 2>/dev/null |grep 'inet ' |awk '{print $4}')
	[ -z "$ip_local" ] && echo no || echo yes $ip_local
	echo -n "interface $tun_remote exists on remote : "
	ip_remote=$(ssh $SSHQT_SSH_OPTS -T $remote "ip -o a s dev $tun_remote 2>/dev/null |grep 'inet ' |awk '{print \$4}'")
	[ -z "$ip_remote" ] && echo no || echo yes $ip_remote
	echo -n "tunnel running                  : "
	pgrep -x -f "$cmd_start_tun" >/dev/null && running=1 || running=0
	[ $running -eq 1 ] && echo yes || echo no
	echo -n "testing ping $SSHQT_REMOTE_IP       : "
	if [ $running -eq 1 ]; then
		ping -w 4 -c1 $SSHQT_REMOTE_IP >/dev/null && echo ok || (echo fail; return 1)
	else
		echo skipped
	fi
}

print_env_params() {
cat <<-_EOF
environment parameters:
   SSHQT_LOCAL_NUM=${SSHQT_LOCAL_NUM}
   SSHQT_LOCAL_IP="${SSHQT_LOCAL_IP}"
   SSHQT_REMOTE_NUM=${SSHQT_REMOTE_NUM}
   SSHQT_REMOTE_IP="${SSHQT_REMOTE_IP}"
   SSHQT_SSH_OPTS="${SSHQT_SSH_OPTS}"

_EOF
}

set -e

SSHQT_LOCAL_NUM=${SSHQT_LOCAL_NUM:-0}
SSHQT_LOCAL_IP="${SSHQT_LOCAL_IP:-192.168.21.1}"
SSHQT_REMOTE_NUM=${SSHQT_REMOTE_NUM:-0}
SSHQT_REMOTE_IP="${SSHQT_REMOTE_IP:-192.168.21.2}"
SSHQT_SSH_OPTS="${SSHQT_SSH_OPTS}"

tun_local="tun$SSHQT_LOCAL_NUM"
tun_remote="tun$SSHQT_REMOTE_NUM"

[ $# -lt 2 -o $# -gt 3 ] && usageexit
remote="$1"
action="$2"
[ $# -eq 3 ] && routed_ip="$3"
# -S none: disable ControlPath so the tunnel is not dependent of external connections
cmd_start_tun="ssh $SSHQT_SSH_OPTS -S none -N -T -f -w $SSHQT_LOCAL_NUM:$SSHQT_REMOTE_NUM $remote"
print_env_params

case $action in
start)
	[ $(id -u) -ne 0 ] && fatal "must be root to start a tunnel"
	trap tun_stop EXIT
	echo "[+] getting remote informations"
	[[ $(trace ssh $SSHQT_SSH_OPTS -T $remote "id -u -n") != "root" ]] && fatal "you must have root access on the remote machine"
	remote_user=$(ssh $SSHQT_SSH_OPTS -T $remote "id -u -n")
	echo "remote_user: $remote_user"
	pgrep -x -f "$cmd_start_tun" >/dev/null && fatal "tunnel ssh connection already running, use '$0 stop'"
	echo "[+] creating local tunnel interface"
	trace ip l d dev $tun_local 2>/dev/null ||true
	trace ip tuntap add $tun_local mode tun
	trace ip a a $SSHQT_LOCAL_IP/30 dev $tun_local
	trace ip l s up dev $tun_local
	echo "[+] creating remote tunnel interface"
	trace ssh $SSHQT_SSH_OPTS -T $remote "ip l del $tun_remote 2>/dev/null; ip tuntap add $tun_remote mode tun user $remote_user; ip a a $SSHQT_REMOTE_IP/30 dev $tun_remote && ip l s up dev $tun_remote"
	echo "[+] starting tunnel"
	trace $cmd_start_tun
	tun_status
	if [ ! -z "$routed_ip" ]; then
		echo "[+] adding local route"
		trace ip r a $routed_ip via $SSHQT_REMOTE_IP
		echo "[+] setup routing on remote"
		trace ssh $SSHQT_SSH_OPTS -T $remote "gwiface=\$(ip r get $routed_ip |head -n1 |sed 's/.*dev \([^ ]*\).*/\1/') && sysctl -w net.ipv4.conf.\$(echo \$gwiface |tr '.' '/').forwarding=1 && sysctl -w net.ipv4.conf.$tun_remote.forwarding=1 && iptables -t nat -A POSTROUTING -s $SSHQT_LOCAL_IP -o \$gwiface -j MASQUERADE"
	fi
	trap - EXIT
	echo "[*] OK, tunnel is established to $remote as $SSHQT_REMOTE_IP"
	;;
stop)
	[ $(id -u) -ne 0 ] && fatal "must be root to start a tunnel"
	tun_stop user
	;;
status)
	tun_status
	;;
*)
	usageexit
	;;
esac
