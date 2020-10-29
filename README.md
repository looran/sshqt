# sshqt - ssh quick tunnel, ssh -w friendly

`sshqt` will create a tun IP tunnel with a remote host where you have root ssh access.

Optionally you can ask it to prepare routing to reach hosts behind the remote ssh server.

You need to have "PermitTunnel yes" or "PermitTunnel point-to-point" in /etc/ssh/sshd_config of the server.

``` bash
$ sshqt -h
~ ssh quick tunnel, ssh -w friendly ~
usage: /usr/local/bin/sshqt <remote_ip> (start | stop | status) [<routed_ip>]
```

## Example: route 8.8.8.8 through a remote server

### Start the tunnel

``` bash
$ sshqt my_ssh_server start 8.8.8.8
```

"my_ssh_server" can be an IP, a DNS name or ssh alias.

Output:
``` bash
parameters:
   TUN_LOCAL_NUM=0
   TUN_LOCAL_IP="192.168.21.1"
   TUN_REMOTE_NUM=0
   TUN_REMOTE_IP="192.168.21.2"

[+] getting remote informations
remote_user: u
[+] creating local tunnel interface
# sudo ip l d dev tun0
# sudo ip tuntap add tun0 mode tun user u
# sudo ip a a 192.168.21.1/30 dev tun0
# sudo ip l s up dev tun0
[+] creating remote tunnel interface
# ssh -T root@my_ssh_server ip l del tun0 2>/dev/null; ip tuntap add tun0 mode tun user u; ip a a 192.168.21.2/30 dev tun0 && ip l s up dev tun0
[+] starting tunnel
# ssh -S none -N -T -f -w 0:0 my_ssh_server
interface tun0 exists on local  : yes 192.168.21.1/30
interface tun0 exists on remote : yes 192.168.21.2/30
tunnel running                  : yes
testing ping 192.168.21.2       : ok
[+] adding local route
# sudo ip r a 8.8.8.8 via 192.168.21.2
[+] setup routing on remote
# ssh -T root@my_ssh_server gwiface=$(ip r get 8.8.8.8 |head -n1 |sed 's/.*dev \([^ ]*\).*/\1/') && sysctl -w net.ipv4.conf.$(echo $gwiface |tr '.' '/').forwarding=1 && sysctl -w net.ipv4.conf.tun0.forwarding=1 && iptables -t nat -A POSTROUTING -s 192.168.21.1 -o $gwiface -j MASQUERADE
net.ipv4.conf.enp0s25.forwarding = 1
net.ipv4.conf.tun0.forwarding = 1
[*] OK, tunnel is established to my_ssh_server as 192.168.21.2
```

### Check that 8.8.8.8 is routed through my_ssh_server

``` bash
 $ ip r get 8.8.8.8
8.8.8.8 via 192.168.21.2 dev tun0 src 192.168.21.1 uid 1000 
    cache 
```
``` bash
$ traceroute -n 8.8.8.8 |head -n2
traceroute to 8.8.8.8 (8.8.8.8), 30 hops max, 60 byte packets
 1  192.168.21.2  1.561 ms  2.526 ms  2.520 ms
```

### See status of tunnel

``` bash
$ sshqt my_ssh_server status 
parameters:
   TUN_LOCAL_NUM=0
   TUN_LOCAL_IP="192.168.21.1"
   TUN_REMOTE_NUM=0
   TUN_REMOTE_IP="192.168.21.2"

interface tun0 exists on local  : yes 192.168.21.1/30
interface tun0 exists on remote : yes 192.168.21.2/30
tunnel running                  : yes
testing ping 192.168.21.2       : ok
```

### Stop the tunnel

``` bash
$ sshqt my_ssh_server stop 8.8.8.8
```

Output:
``` bash
parameters:
   TUN_LOCAL_NUM=0
   TUN_LOCAL_IP="192.168.21.1"
   TUN_REMOTE_NUM=0
   TUN_REMOTE_IP="192.168.21.2"

[+] stopping tunnel
# pkill -x -f ssh -S none -N -T -f -w 0:0 my_ssh_server
# sudo ip l d dev tun0
# ssh -T root@my_ssh_server ip l del dev tun0 2>/dev/null
# ssh -T root@my_ssh_server gwiface=$(ip r get 8.8.8.8 |head -n1 |sed 's/.*dev \([^ ]*\).*/\1/') && iptables -t nat -D POSTROUTING -s 192.168.21.1 -o $gwiface -j MASQUERADE 2>/dev/null
[*] OK, ssh tunnel to my_ssh_server is stopped
```

## Installation

``` bash
$ sudo make install
```

## Compatibility

The client and server must be running linux with iptools utilities and OpenSSH client and server.

You need to have "PermitTunnel yes" or "PermitTunnel point-to-point" in /etc/ssh/sshd_config of the server.
