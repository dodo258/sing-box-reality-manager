#!/usr/bin/env bash
# Model iptables/ip6tables and netfilter-persistent (an Oracle-like image whose
# INPUT ends in REJECT, no UFW/firewalld) without touching the host.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
SRM_ROOT=$work/root
DATA=$work/data
mkdir -p "$SRM_ROOT" "$DATA" "$work/saved"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
fail() { echo "FAIL $*"; exit 1; }
ufw() { printf 'Status: inactive\n'; }
firewall-cmd() { return 252; }
# Rules are kept as `iptables -S INPUT` lines; -C/-D match the exact spec.
ipt_mock() {
    local rules=$work/ipt-$1 action spot line rule n=0 hit=0; shift
    [[ $1 != -w ]] || shift 2
    action=$1; shift 2
    case $action in
      -S) cat "$rules";;
      -C) grep -Fxq -- "-A INPUT $*" "$rules";;
      -A) printf '%s\n' "-A INPUT $*" >> "$rules";;
      -I|-D)
        [[ $action == -D ]] || { spot=$1; shift; }
        line="-A INPUT $*"
        while IFS= read -r rule; do
            if [[ $rule == '-A INPUT '* ]]; then n=$((n + 1)); fi
            if [[ $action == -I && $hit == 0 && $rule == '-A INPUT '* && $n == "$spot" ]]; then printf '%s\n' "$line"; hit=1; fi
            if [[ $action == -D && $hit == 0 && $rule == "$line" ]]; then hit=1; continue; fi
            printf '%s\n' "$rule"
        done < "$rules" > "$rules.new"
        mv "$rules.new" "$rules"
        [[ $hit == 1 ]] || return 1;;
      *) return 2;;
    esac
}
iptables() { ipt_mock ipv4 "$@"; }
ip6tables() { ipt_mock ipv6 "$@"; }
saves=0
netfilter-persistent() {
    [[ $1 == save ]] || return 2
    saves=$((saves + 1))
    cp "$work/ipt-ipv4" "$work/saved/rules.v4" && cp "$work/ipt-ipv6" "$work/saved/rules.v6"
}
cat > "$work/ipt-ipv4" <<'EOF'
-P INPUT ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 23999 -j ACCEPT
-A INPUT -j REJECT --reject-with icmp-host-prohibited
EOF
printf -- '-P INPUT ACCEPT\n' > "$work/ipt-ipv6"
cp "$work/ipt-ipv4" "$work/original-v4"
cp "$work/ipt-ipv6" "$work/original-v6"
srm_rules() { grep -c -- '--comment srm -j ACCEPT' "$work/ipt-$1" || true; }

[[ $(firewall_detect) == iptables ]] || fail 'a REJECT at the end of INPUT selects the iptables backend'
printf '{"nodes":[{"port":23999,"type":"vless","enabled":true},{"port":24000,"type":"hysteria2","enabled":true},{"port":24001,"type":"shadowsocks","enabled":true}]}\n' > "$work/state"
firewall_sync "$work/state" > "$work/out"
for spec in 'tcp -m tcp --dport 23999' 'udp -m udp --dport 24000' 'tcp -m tcp --dport 24001' 'udp -m udp --dport 24001'; do
    grep -Fxq -- "-A INPUT -p $spec -m comment --comment srm -j ACCEPT" "$work/ipt-ipv4" || fail "missing $spec"
done
[[ $(srm_rules ipv4) == 4 ]] || fail 'expected four srm rules'
[[ $(tail -n 1 "$work/ipt-ipv4") == '-A INPUT -j REJECT --reject-with icmp-host-prohibited' ]] || fail 'REJECT is no longer last'
# The existing rules keep their order; srm rules sit right before REJECT.
grep -v -- '--comment srm' "$work/ipt-ipv4" | cmp -s - "$work/original-v4" || fail 'existing rules changed'
[[ $(sed -n 7p "$work/ipt-ipv4") == *'--comment srm -j ACCEPT' && $(sed -n 10p "$work/ipt-ipv4") == *'--comment srm -j ACCEPT' ]] || fail 'srm rules are not right before REJECT'
cmp -s "$work/ipt-ipv6" "$work/original-v6" || fail 'IPv6 without a blocking rule was changed'
[[ -f $DATA/firewall/iptables-ipv4-both-24000-udp && ! -e $DATA/firewall/iptables-ipv6-both-24000-udp ]] || fail 'ownership records'
[[ $saves == 1 ]] && cmp -s "$work/saved/rules.v4" "$work/ipt-ipv4" || fail 'rules were not saved once with netfilter-persistent'
grep -q 'iptables 拦截规则之前放行' "$work/out" || fail 'no iptables message'
echo 'PASS adding nodes inserts ACCEPT rules commented srm before the REJECT and saves them with netfilter-persistent'

firewall_sync "$work/state" > /dev/null
[[ $(srm_rules ipv4) == 4 && $saves == 1 ]] || fail 'repeated sync changed rules or saved again'
echo 'PASS repeated sync adds nothing and does not save again'

jq 'del(.nodes[1])' "$work/state" > "$work/state-deleted"
firewall_sync "$work/state-deleted" > /dev/null
if grep -q -- '--dport 24000 ' "$work/ipt-ipv4"; then fail 'deleted node rule remains'; fi
[[ ! -e $DATA/firewall/iptables-ipv4-both-24000-udp && $(srm_rules ipv4) == 3 ]] || fail 'other srm rules changed'
[[ $saves == 2 ]] && cmp -s "$work/saved/rules.v4" "$work/ipt-ipv4" || fail 'removal was not saved'
grep -v -- '--comment srm' "$work/ipt-ipv4" | cmp -s - "$work/original-v4" || fail 'existing rules changed'
echo 'PASS deleting a node removes only its srm rule and saves'

firewall_clear > /dev/null
cmp -s "$work/ipt-ipv4" "$work/original-v4" && cmp -s "$work/saved/rules.v4" "$work/original-v4" || fail 'uninstall did not restore the original rules'
[[ -z $(find "$DATA/firewall" -type f) ]] || fail 'records left after uninstall'
grep -Fxq -- '-A INPUT -p tcp -m tcp --dport 23999 -j ACCEPT' "$work/ipt-ipv4" || fail 'existing allow on the same port removed'
echo 'PASS uninstall removes every srm rule and keeps the existing allow on the same port'

# Only a DROP policy: rules are appended. A foreign rule commented srm for another port stays.
printf -- '-P INPUT DROP\n-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT\n-A INPUT -p tcp -m tcp --dport 9000 -m comment --comment srm -j ACCEPT\n' > "$work/ipt-ipv6"
cp "$work/ipt-ipv6" "$work/original-v6"
firewall_sync "$work/state" > /dev/null
[[ $(tail -n 1 "$work/ipt-ipv6") == '-A INPUT -p udp -m udp --dport 24001 -m comment --comment srm -j ACCEPT' && $(srm_rules ipv6) == 5 ]] || fail 'IPv6 DROP policy rules not appended'
[[ $(srm_rules ipv4) == 4 ]] || fail 'IPv4 rules missing'
firewall_clear > /dev/null
cmp -s "$work/ipt-ipv6" "$work/original-v6" && cmp -s "$work/ipt-ipv4" "$work/original-v4" || fail 'cleanup changed foreign rules'
echo 'PASS a DROP policy gets appended rules per family; cleanup keeps rules it did not add'

unset -f netfilter-persistent
if command -v netfilter-persistent >/dev/null; then
    echo 'SKIP netfilter-persistent is installed on this machine'
else
    firewall_sync "$work/state" > "$work/out"
    [[ $(srm_rules ipv4) == 4 ]] || fail 'rules not added without netfilter-persistent'
    grep -q '没有 netfilter-persistent，服务器重启后由 srm 服务启动时补回' "$work/out" || fail 'missing persistence hint'
    firewall_clear > /dev/null
    echo 'PASS without netfilter-persistent rules still apply and a reboot warning is printed'
fi

# After a reboot without netfilter-persistent the system's REJECT may come back while
# srm's rules do not: srm.service runs firewall-restore before every start, which
# syncs the current nodes' rules when no other operation holds srm's lock.
service_unit | grep -Fxq "ExecStartPre=-+$SRM_ROOT/manager.sh firewall-restore" || fail 'the unit does not restore the rules before starting'
STATE=$work/data/current/state.json
SRM_LOCK=$work/srm.lock
mkdir -p "$DATA/current" && cp "$work/state" "$STATE"
lock_busy=0
flock() { [[ $1 == -n && $2 == 9 ]] || return 2; [[ $lock_busy == 0 ]]; }
firewall_sync "$STATE" > /dev/null
[[ $(srm_rules ipv4) == 4 ]] || fail 'rules before the reboot'
cp "$work/original-v4" "$work/ipt-ipv4"
firewall_restore > /dev/null || fail 'restore failed'
[[ $(srm_rules ipv4) == 4 && $(tail -n 1 "$work/ipt-ipv4") == '-A INPUT -j REJECT --reject-with icmp-host-prohibited' ]] || fail 'rules not restored before the REJECT'
grep -v -- '--comment srm' "$work/ipt-ipv4" | cmp -s - "$work/original-v4" || fail 'restore changed existing rules'
cp "$work/ipt-ipv4" "$work/restored"
firewall_restore > /dev/null && cmp -s "$work/ipt-ipv4" "$work/restored" || fail 'restoring again changed rules'
# A locked operation (maybe the one restarting the service) syncs the rules itself.
cp "$work/original-v4" "$work/ipt-ipv4"
lock_busy=1
firewall_restore > /dev/null || fail 'restore failed while the lock was held'
[[ $(srm_rules ipv4) == 0 ]] || fail 'rules changed while another operation held the lock'
lock_busy=0
unset -f flock
rm -rf "$DATA/current"
firewall_clear > /dev/null
echo 'PASS the unit restores missing rules before every start, only when no other operation holds the lock'

printf -- '-P INPUT ACCEPT\n-A INPUT -s 192.0.2.1/32 -j DROP\n' > "$work/ipt-ipv4"
printf -- '-P INPUT ACCEPT\n' > "$work/ipt-ipv6"
[[ $(firewall_detect) == none ]] || fail 'iptables that only drops one address is not a firewall to open'
firewall_sync "$work/state" > "$work/out"
[[ $(srm_rules ipv4) == 0 && -z $(find "$DATA/firewall" -type f) ]] || fail 'rules added without a blocking rule'
grep -q '没有拦截入站的 iptables 规则' "$work/out" || fail 'missing none message'
echo 'PASS without a catch-all REJECT/DROP nothing is changed'

# A family that disappears later (IPv6 disabled) must not block node changes forever.
printf -- '-P INPUT ACCEPT\n-A INPUT -j REJECT\n' > "$work/ipt-ipv4"
cp "$work/ipt-ipv4" "$work/ipt-ipv6"
firewall_sync "$work/state" > /dev/null
[[ -f $DATA/firewall/iptables-ipv6-both-24001-udp ]] || fail 'IPv6 records missing'
ip6tables() { printf 'ip6tables: Address family not supported by protocol\n' >&2; return 3; }
firewall_sync "$work/state-deleted" > /dev/null || fail 'sync failed after IPv6 went away'
[[ ! -e $DATA/firewall/iptables-ipv6-both-24001-udp && -f $DATA/firewall/iptables-ipv4-both-24001-udp ]] || fail 'IPv6 records kept'
echo 'PASS records of a family that is no longer available are dropped instead of failing every change'

ip6tables() { ipt_mock ipv6 "$@"; }
printf -- '-P INPUT ACCEPT\n-A INPUT -j REJECT\n' > "$work/ipt-ipv6"
firewall_sync "$work/state" > /dev/null
ip6tables() { [[ $3 != -S ]] || return 4; ipt_mock ipv6 "$@"; }
if firewall_clear > /dev/null 2>&1; then fail 'a lock timeout dropped records'; fi
[[ -f $DATA/firewall/iptables-ipv6-both-24001-udp ]] || fail 'IPv6 record dropped on a temporary failure'
ip6tables() { ipt_mock ipv6 "$@"; }
firewall_clear > /dev/null
[[ -z $(find "$DATA/firewall" -type f) && $(srm_rules ipv4) == 0 && $(srm_rules ipv6) == 0 ]] || fail 'retry did not clean'
echo 'PASS a temporary iptables failure (exit 4) keeps the records so a retry cleans the rules'

# Missing comment module: -C fails with 2; nothing is recorded, so later changes and uninstall still work.
iptables() { [[ $3 != -C ]] || { printf "iptables: Couldn't load match 'comment'\n" >&2; return 2; }; ipt_mock ipv4 "$@"; }
printf -- '-P INPUT ACCEPT\n-A INPUT -j REJECT\n' > "$work/ipt-ipv4"
printf -- '-P INPUT ACCEPT\n' > "$work/ipt-ipv6"
if firewall_sync "$work/state" > /dev/null 2> "$work/err"; then fail 'sync without the comment module succeeded'; fi
grep -q 'comment 模块' "$work/err" || fail 'no hint about the comment module'
[[ -z $(find "$DATA/firewall" -type f) ]] || fail 'a failed query left records'
printf '{"nodes":[]}\n' > "$work/empty"
firewall_sync "$work/empty" > /dev/null && firewall_clear || fail 'cleanup blocked after a failed query'
echo 'PASS a failed query (no comment module) records nothing, so later syncs and uninstall still succeed'
