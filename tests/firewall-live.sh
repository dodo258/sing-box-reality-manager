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
iptables -S INPUT | grep -q '^-A' && { echo 'FAIL INPUT not empty after UFW disable'; exit 1; }
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
firewall_clear
iptables -S | cmp - "$work/ipt-original.v4"
ip6tables -S | cmp - "$work/ipt-original.v6"
! grep -q -- '--comment srm' "$work/saved.v4" "$work/saved.v6" || exit 1
echo 'PASS real iptables: uninstall restores the original rules exactly'
