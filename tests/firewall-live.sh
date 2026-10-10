#!/usr/bin/env bash
# Run only in disposable CI, inside separate network AND mount namespaces.
set -Eeuo pipefail
source "$(dirname -- "$0")/support/guard.sh"
need_ci_root
trap 'echo "Firewall test failed at line $LINENO"; ufw show added || true; iptables-save || true' ERR
[[ $(readlink /proc/self/ns/net) != "$(readlink /proc/1/ns/net)" ]] || exit 1
[[ $(readlink /proc/self/ns/mnt) != "$(readlink /proc/1/ns/mnt)" ]] || exit 1
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
mount --make-rprivate /
cp -a /etc/ufw "$work/etc-ufw"
cp /etc/default/ufw "$work/ufw-default"
mount --bind "$work/etc-ufw" /etc/ufw
mount --bind "$work/ufw-default" /etc/default/ufw
server=''
cleanup() {
    [[ -z $server ]] || kill "$server" 2>/dev/null || true
    ip netns del srm-hop-client 2>/dev/null || true
    ufw --force disable >/dev/null || true
    umount /etc/ufw
    umount /etc/default/ufw
    rm -rf "$work"
}
trap cleanup EXIT
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw allow 22222/tcp comment 'existing SSH' >/dev/null
ufw allow 23999/tcp comment 'existing application' >/dev/null
ufw --force enable >/dev/null
LC_ALL=C ufw show added > "$work/original.rules"
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/state.json
mkdir -p "$SRM_ROOT" "$DATA"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
printf '{"nodes":[{"port":23999,"type":"anytls","enabled":true},{"port":24000,"type":"hysteria2","enabled":true}]}\n' > "$STATE"
firewall_sync "$STATE"
ufw show added | grep -q 'srm-23999-tcp'
ufw show added | grep -q 'srm-24000-udp'
iptables-save | grep -- '--dport 24000 ' | grep -q -- '-j ACCEPT'
ufw show added | grep -q 'existing application'
echo 'PASS real UFW TCP/UDP rules coexist with pre-existing allow on same port'
firewall_sync "$STATE"
[[ $(ufw show added | grep -c 'srm-24000-udp') == 1 ]] || exit 1
echo 'PASS repeated sync is idempotent'
firewall_sync "$STATE" 443
ufw show added | grep -q 'srm-443-tcp'
firewall_sync "$STATE"
! ufw show added | grep -q 'srm-443-tcp' || exit 1
echo 'PASS temporary certificate port is removed while node ports remain'
mkdir -p "$SRM_ROOT/acme-accounts/example.com"
printf '443\n' > "$SRM_ROOT/acme-accounts/example.com/challenge-port"
acme_call() { return 1; }
if firewall_renew example.com; then echo 'FAIL expected ACME failure'; exit 1; fi
! ufw show added | grep -q 'srm-443-tcp' || exit 1
echo 'PASS failed certificate renewal also cleans temporary port'
jq '.nodes[0].port=24001|.nodes[1].enabled=false' "$STATE" > "$work/new-state"
firewall_sync "$work/new-state"
! ufw show added | grep -q 'srm-23999-tcp' || exit 1
! ufw show added | grep -q 'srm-24000-udp' || exit 1
ufw show added | grep -q 'srm-24001-tcp'
ufw show added | grep -q 'existing application'
echo 'PASS change port and disable remove only owned rules'
firewall_clear
LC_ALL=C ufw show added > "$work/final.rules"
cmp "$work/original.rules" "$work/final.rules"
echo 'PASS cleanup preserves original rules exactly'
printf 'ufw\tglobal\tboth\t24002\ttcp\n' > "$DATA/firewall/ufw-global-both-24002-tcp"
firewall_clear
[[ ! -e /etc/ufw/applications.d/srm-24002-tcp ]] || exit 1
LC_ALL=C ufw show added > "$work/final.rules"
cmp "$work/original.rules" "$work/final.rules"
echo 'PASS interrupted profile creation can be cleaned without touching original rules'
printf 'foreign file\n' > /etc/ufw/applications.d/srm-24003-tcp
if firewall_add ufw global both 24003 tcp; then echo 'FAIL foreign profile overwritten'; exit 1; fi
[[ $(cat /etc/ufw/applications.d/srm-24003-tcp) == 'foreign file' ]] || exit 1
[[ ! -e $DATA/firewall/ufw-global-both-24003-tcp ]] || exit 1
rm /etc/ufw/applications.d/srm-24003-tcp
echo 'PASS conflicting application file is preserved'
ufw --force disable >/dev/null
[[ $(firewall_detect) == none ]] || exit 1
firewall_sync "$STATE"
[[ $(firewall_detect) == none ]] || exit 1
echo 'PASS disabled UFW is never enabled by manager'
# Oracle-like image: no UFW/firewalld, INPUT ends in REJECT, netfilter-persistent
# saves the rules (simulated: the real package would remove ufw from the runner).
ip link set lo up
# Disabled UFW leaves jumps to its emptied chains; detection above ignored them.
iptables -S INPUT
iptables -F INPUT
ip6tables -F INPUT
[[ $(iptables -S INPUT) == '-P INPUT ACCEPT' && $(ip6tables -S INPUT) == '-P INPUT ACCEPT' ]] || exit 1
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 22222 -j ACCEPT
iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited
ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
ip6tables -A INPUT -j REJECT
iptables -S > "$work/ipt-original.v4"
ip6tables -S > "$work/ipt-original.v6"
mkdir -p "$work/bin"
printf '#!/bin/sh\n[ "$1" = save ] && iptables-save > %q/saved.v4 && ip6tables-save > %q/saved.v6\n' "$work" "$work" > "$work/bin/netfilter-persistent"
chmod 755 "$work/bin/netfilter-persistent"
PATH=$work/bin:$PATH
python3 -m http.server 24010 --bind 127.0.0.1 --directory "$work" >/dev/null 2>&1 &
server=$!
for _ in $(seq 50); do [[ -z $(ss -Hltn 'sport = :24010') ]] || break; sleep 0.1; done
if curl -s --max-time 3 -o /dev/null http://127.0.0.1:24010/; then echo 'FAIL REJECT did not block the node port'; exit 1; fi
[[ $(firewall_detect) == iptables ]] || exit 1
printf '{"nodes":[{"port":24010,"type":"anytls","enabled":true},{"port":24011,"type":"hysteria2","enabled":true}]}\n' > "$STATE"
firewall_sync "$STATE"
curl -s --max-time 3 -o /dev/null http://127.0.0.1:24010/
iptables -S INPUT | tail -n 1 | grep -q -- '-j REJECT'
iptables -S INPUT | grep -q -- '--dport 24010 -m comment --comment srm -j ACCEPT'
ip6tables -S INPUT | grep -q -- '--dport 24011 -m comment --comment srm -j ACCEPT'
grep -q -- '--comment srm' "$work/saved.v4" && grep -q -- '--comment srm' "$work/saved.v6"
echo 'PASS real iptables: the node port opens before the REJECT, rules commented srm are saved for IPv4 and IPv6'
jq 'del(.nodes[0])' "$STATE" > "$work/new-state"
firewall_sync "$work/new-state"
if curl -s --max-time 3 -o /dev/null http://127.0.0.1:24010/; then echo 'FAIL deleted node port still open'; exit 1; fi
! grep -q -- '--dport 24010 ' "$work/saved.v4" || exit 1
ip6tables -S INPUT | grep -q -- '--dport 24011 -m comment --comment srm -j ACCEPT'
echo 'PASS real iptables: deleting a node closes only its port'
# The temporary import link opens its port before the REJECT only while it serves.
jq -n '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[{id:"1000000000000001",name:"ss",type:"shadowsocks",enabled:true,
  host:"127.0.0.1",port:24011,method:"2022-blake3-aes-128-gcm",password:"YctPZ6U7xPPcU+gp3u+0tw=="}]}' > "$STATE"
firewall_sync "$STATE"
profile_link clash '' 24030 30 > "$work/link.out" 2>&1 &
link=$!
for _ in $(seq 100); do grep -q '^http://' "$work/link.out" && break; sleep 0.1; done
url=$(grep -m 1 '^http://' "$work/link.out")
iptables -S INPUT | grep -q -- '--dport 24030 -m comment --comment srm -j ACCEPT'
curl -s --max-time 3 -o "$work/profile.yaml" "$url"
grep -q '^proxies:$' "$work/profile.yaml"
wait "$link"
! iptables -S INPUT | grep -q -- '--dport 24030 ' || exit 1
! ip6tables -S INPUT | grep -q -- '--dport 24030 ' || exit 1
iptables -S INPUT | grep -q -- '--dport 24011 -m comment --comment srm -j ACCEPT'
if curl -s --max-time 3 -o /dev/null "$url"; then echo 'FAIL temporary link still served'; exit 1; fi
echo 'PASS real iptables: the temporary import link opens its port before the REJECT while serving and removes the rule after one download; node rules stay'
firewall_clear
iptables -S | cmp - "$work/ipt-original.v4"
ip6tables -S | cmp - "$work/ipt-original.v6"
! grep -q -- '--comment srm' "$work/saved.v4" "$work/saved.v6" || exit 1
echo 'PASS real iptables: uninstall restores the original rules exactly'
# Port hopping with real packets: a client in another network namespace sends UDP to
# ports of the hop range and gets the answer of the node port (through the REJECT above,
# which only the node port passes), first with iptables, then with nftables.
ip netns add srm-hop-client
ip link add srm-hop0 type veth peer name srm-hop1 netns srm-hop-client
ip addr add 10.77.0.1/24 dev srm-hop0
ip addr add fd77::1/64 dev srm-hop0 nodad
ip link set srm-hop0 up
ip netns exec srm-hop-client ip addr add 10.77.0.2/24 dev srm-hop1
ip netns exec srm-hop-client ip addr add fd77::2/64 dev srm-hop1 nodad
ip netns exec srm-hop-client ip link set srm-hop1 up
ip netns exec srm-hop-client ip link set lo up
# The IPv6 REJECT above also drops neighbour discovery; a server allows ICMPv6 anyway.
ip6tables -I INPUT -p ipv6-icmp -j ACCEPT
cat > "$work/udp.py" <<'PY'
import socket, sys
if sys.argv[1] == "serve":
    s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
    s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    s.bind(("::", int(sys.argv[2])))
    while True:
        data, peer = s.recvfrom(100)
        s.sendto(b"node:" + data, peer)
host, port = sys.argv[2], int(sys.argv[3])
s = socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)
# Connected: an answer from any other address or port than the one asked is dropped.
s.connect((host, port))
s.send(b"hop")
try:
    sys.exit(0 if s.recv(100) == b"node:hop" else 1)
except OSError:
    sys.exit(1)
PY
kill "$server"; wait "$server" 2>/dev/null || true
python3 "$work/udp.py" serve 24020 >/dev/null 2>&1 &
server=$!
for _ in $(seq 50); do [[ -z $(ss -Hlun 'sport = :24020') ]] || break; sleep 0.1; done
answers() { ip netns exec srm-hop-client python3 "$work/udp.py" ask "$1" "$2"; }
jq -n '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[{id:"1000000000000001",name:"hy2",type:"hysteria2",enabled:true,
  host:"10.77.0.1",port:24020,sni:"hy.example.com",cert_dir:"/certs",password:"pw",hop:{start:20000,end:20999}}]}' > "$STATE"
if answers 10.77.0.1 20500; then echo 'FAIL a hop port answered before any rule'; exit 1; fi
firewall_sync "$STATE"
iptables -t nat -S PREROUTING | grep -Fq -- '-p udp -m addrtype --dst-type LOCAL -m udp --dport 20000:20999 -m comment --comment srm-hop -j REDIRECT --to-ports 24020'
for port in 20000 20500 20999 24020; do answers 10.77.0.1 "$port" || { echo "FAIL IPv4 port $port"; exit 1; }; done
answers fd77::1 20777 || { echo 'FAIL IPv6 hop port'; exit 1; }
if answers 10.77.0.1 21000; then echo 'FAIL a port outside the range answered'; exit 1; fi
iptables -S INPUT | grep -q -- '--dport 24020 -m comment --comment srm -j ACCEPT'
! iptables -S INPUT | grep -q -- '--dport 20000' || exit 1
grep -q -- '--comment srm-hop' "$work/saved.v4" || exit 1
echo 'PASS real iptables: UDP to the hop range (IPv4 and IPv6) reaches the node port and answers from the port asked; only the node port is allowed in INPUT'
jq '.nodes[0].enabled=false' "$STATE" > "$work/new-state"
firewall_sync "$work/new-state"
! iptables -t nat -S PREROUTING | grep -q srm-hop && ! ip6tables -t nat -S PREROUTING | grep -q srm-hop || exit 1
if answers 10.77.0.1 20500; then echo 'FAIL hop port answers after the node was disabled'; exit 1; fi
firewall_sync "$STATE"
answers 10.77.0.1 20500
jq 'del(.nodes[0].hop)' "$STATE" > "$work/new-state"
firewall_sync "$work/new-state"
! iptables -t nat -S PREROUTING | grep -q srm-hop || exit 1
if answers 10.77.0.1 20500; then echo 'FAIL hop port answers after hopping was turned off'; exit 1; fi
answers 10.77.0.1 24020
echo 'PASS real iptables: disabling the node or turning hopping off removes the redirect; the node port keeps working'
hop_backend() { printf 'nft\n'; }
firewall_sync "$STATE"
nft list table inet srm_hop | grep -Eq 'fib daddr type local udp dport 20000-20999 .*redirect to :24020 comment "srm-hop"'
! iptables -t nat -S PREROUTING | grep -q srm-hop || exit 1
for port in 20000 20999; do answers 10.77.0.1 "$port" || { echo "FAIL nft IPv4 port $port"; exit 1; }; done
answers fd77::1 20321 || { echo 'FAIL nft IPv6 hop port'; exit 1; }
firewall_clear
if nft list table inet srm_hop >/dev/null 2>&1; then echo 'FAIL nft table left after uninstall'; exit 1; fi
if answers 10.77.0.1 20500; then echo 'FAIL hop port answers after uninstall'; exit 1; fi
ip6tables -D INPUT -p ipv6-icmp -j ACCEPT
iptables -S | cmp - "$work/ipt-original.v4"
ip6tables -S | cmp - "$work/ipt-original.v6"
[[ ! -e $DATA/port-hopping ]] || exit 1
echo 'PASS real nftables: the table inet srm_hop redirects the range (IPv4 and IPv6); uninstall deletes it and the original rules are back'
