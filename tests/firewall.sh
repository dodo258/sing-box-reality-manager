#!/usr/bin/env bash
# Model firewalld's separate runtime/permanent stores without touching the host.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
SRM_ROOT=$work/root
DATA=$work/data
mkdir -p "$SRM_ROOT" "$DATA" "$work/rules"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
ufw() { printf 'Status: inactive\n'; }
iptables() { printf -- '-P INPUT ACCEPT\n'; }
ip6tables() { iptables "$@"; }
running=1
firewall-cmd() {
    local zone='' scope=runtime arg action='' port=''
    # A stopped firewalld answers nothing (exit 252, "FirewallD is not running").
    (( running )) || { printf 'FirewallD is not running\n' >&2; return 252; }
    for arg in "$@"; do
        case $arg in
          --state) printf 'running\n'; return 0;;
          --get-active-zones) printf 'public\n  interfaces: eth0\n'; return 0;;
          --zone=*) zone=${arg#*=};; --permanent) scope=permanent;;
          --query-port=*) action=query; port=${arg#*=};;
          --add-port=*) action=add; port=${arg#*=};;
          --remove-port=*) action=remove; port=${arg#*=};;
          *) return 2;;
        esac
    done
    port=${port/\//-}
    case $action in
      query) if [[ -f $work/rules/$zone-$scope-$port ]]; then printf 'yes\n'; else printf 'no\n'; return 1; fi;;
      add) touch "$work/rules/$zone-$scope-$port";;
      remove) rm "$work/rules/$zone-$scope-$port";;
    esac
}
touch "$work/rules/public-permanent-23999-tcp"
printf '{"nodes":[{"port":23999,"type":"vless","enabled":true},{"port":24000,"type":"hysteria2","enabled":true}]}\n' > "$work/state"
firewall_sync "$work/state"
[[ ! -e $DATA/firewall/firewalld-public-permanent-23999-tcp ]] || exit 1
[[ -f $DATA/firewall/firewalld-public-runtime-23999-tcp ]] || exit 1
[[ -f $work/rules/public-runtime-24000-udp && -f $work/rules/public-permanent-24000-udp ]] || exit 1
echo 'PASS firewalld keeps independent ownership of runtime and permanent rules'
firewall_sync "$work/state"
firewall_clear
[[ $(find "$work/rules" -type f | wc -l | tr -d ' ') == 1 ]] || exit 1
[[ -f $work/rules/public-permanent-23999-tcp ]] || exit 1
echo 'PASS cleanup retains pre-existing permanent permission'
# Shadowsocks listens on TCP and UDP of the same port; both are opened and both removed.
printf '{"nodes":[{"port":24001,"type":"shadowsocks","enabled":true}]}\n' > "$work/ss-state"
firewall_sync "$work/ss-state"
for rule in runtime-24001-tcp runtime-24001-udp permanent-24001-tcp permanent-24001-udp; do
    [[ -f $work/rules/public-$rule && -f $DATA/firewall/firewalld-public-$rule ]] || { echo "FAIL missing $rule"; exit 1; }
done
firewall_clear
[[ $(find "$work/rules" -type f | wc -l | tr -d ' ') == 1 ]] || exit 1
echo 'PASS a TCP+UDP protocol opens and later removes both transports'
# firewalld stopped for a while (or not up yet when srm.service starts at boot): syncs
# meanwhile, also deleting a node, keep its records and rules, so started again it lets
# the nodes through; the first sync after that removes what is no longer used.
firewall_sync "$work/state" > /dev/null
records=$(ls "$DATA/firewall")
running=0
[[ $(firewall_detect) == none ]] || { echo 'FAIL a stopped firewalld is detected'; exit 1; }
# A UFW that is off keeps the rule of a node still there without touching UFW.
printf 'ufw\tglobal\tboth\t23999\ttcp\n' > "$DATA/firewall/ufw-global-both-23999-tcp"
firewall_sync "$work/state" > "$work/out" || { echo 'FAIL sync failed while firewalld was stopped'; exit 1; }
grep -q 'firewalld / UFW 当前没有运行' "$work/out" || { echo 'FAIL no hint that the rules were kept'; exit 1; }
rm "$DATA/firewall/ufw-global-both-23999-tcp"
jq 'del(.nodes[1])' "$work/state" > "$work/state-deleted"
firewall_sync "$work/state-deleted" > /dev/null || { echo 'FAIL deleting a node failed while firewalld was stopped'; exit 1; }
[[ $(ls "$DATA/firewall") == "$records" ]] || { echo 'FAIL records dropped while firewalld was stopped'; exit 1; }
[[ -f $work/rules/public-runtime-24000-udp && -f $work/rules/public-permanent-24000-udp ]] || exit 1
# Started again: the runtime rules come back from the permanent ones.
running=1
rm "$work/rules"/public-runtime-*
for rule in "$work/rules"/public-permanent-*; do cp "$rule" "${rule/permanent/runtime}"; done
[[ $(firewall_detect) == firewalld ]] || exit 1
firewall_sync "$work/state-deleted" > /dev/null
[[ ! -e $work/rules/public-runtime-24000-udp && ! -e $work/rules/public-permanent-24000-udp ]] || { echo 'FAIL the deleted node kept its rules'; exit 1; }
[[ -z $(find "$DATA/firewall" -name '*-24000-udp') && -f $DATA/firewall/firewalld-public-runtime-23999-tcp && -f $work/rules/public-runtime-23999-tcp ]] || exit 1
firewall_clear
[[ $(ls "$work/rules") == public-permanent-23999-tcp ]] || exit 1
echo 'PASS firewalld stopped, synced (also deleting a node), started again: the rules of the remaining nodes are still there; the next sync removes the deleted one'
# Uninstalling while firewalld is stopped: the runtime records go (firewalld dropped
# those rules when it stopped), the permanent rules are removed from its configuration
# files with firewall-offline-cmd, which edits only permanent rules (no --permanent).
firewall-offline-cmd() {
    local arg
    for arg in "$@"; do [[ $arg != --permanent ]] || return 2; done
    running=1 firewall-cmd --permanent "$@"
}
firewall_sync "$work/state" > /dev/null
running=0
rm "$work/rules"/public-runtime-*
firewall_clear > "$work/out" 2>&1 || { cat "$work/out"; echo 'FAIL uninstalling failed while firewalld was stopped'; exit 1; }
[[ -z $(ls "$DATA/firewall") ]] || { echo 'FAIL records left after uninstalling while firewalld was stopped'; exit 1; }
[[ $(ls "$work/rules") == public-permanent-23999-tcp ]] || { echo 'FAIL the permanent rules were not removed (or the existing one was)'; exit 1; }
echo 'PASS uninstalling while firewalld is stopped removes its permanent rules offline and keeps the existing one'
# A permanent rule that cannot be removed would come back at firewalld's start, so its
# runtime record stays for the retry too.
running=1
firewall_sync "$work/state" > /dev/null
running=0
rm "$work/rules"/public-runtime-*
firewall-offline-cmd() { [[ $* != *--remove-port=24000/udp* ]] || return 1; running=1 firewall-cmd --permanent "$@"; }
if firewall_clear > /dev/null 2>&1; then echo 'FAIL a failed offline removal was ignored'; exit 1; fi
[[ $(ls "$DATA/firewall") == $'firewalld-public-permanent-24000-udp\nfirewalld-public-runtime-24000-udp' ]] || { echo 'FAIL the runtime record of a rule still there was dropped'; exit 1; }
running=1
for rule in "$work/rules"/public-permanent-*; do cp "$rule" "${rule/permanent/runtime}"; done
firewall_clear > /dev/null
# 23999/tcp now comes back at runtime from the permanent rule that was there before srm.
[[ -z $(ls "$DATA/firewall") && $(ls "$work/rules") == $'public-permanent-23999-tcp\npublic-runtime-23999-tcp' ]] || { echo 'FAIL retry after a failed offline removal'; exit 1; }
rm "$work/rules/public-runtime-23999-tcp"
echo 'PASS a permanent rule that fails to be removed offline keeps its runtime record'
# Without firewall-offline-cmd the permanent rules stay and the error says to start firewalld.
running=1
firewall_sync "$work/state" > /dev/null
records=$(ls "$DATA/firewall")
running=0
rm "$work/rules"/public-runtime-*
unset -f firewall-offline-cmd
if firewall_clear > "$work/out" 2>&1; then echo 'FAIL uninstalled without firewall-offline-cmd'; exit 1; fi
grep -q 'systemctl start firewalld' "$work/out" || { cat "$work/out"; echo 'FAIL no hint to start firewalld'; exit 1; }
[[ $(ls "$DATA/firewall") == "$records" ]] || { echo 'FAIL records dropped without firewall-offline-cmd'; exit 1; }
# Started: the runtime rules come back from the permanent ones, and the retry removes them.
running=1
for rule in "$work/rules"/public-permanent-*; do cp "$rule" "${rule/permanent/runtime}"; done
firewall_clear > /dev/null
[[ -z $(ls "$DATA/firewall") && $(ls "$work/rules") == public-permanent-23999-tcp ]] || { echo 'FAIL retry after starting firewalld'; exit 1; }
echo 'PASS without firewall-offline-cmd uninstalling stops with a hint to start firewalld, and works once it runs'
# firewalld removed from the system: nothing is left to clean.
firewall_sync "$work/state" > /dev/null
unset -f firewall-cmd
firewall_clear > /dev/null || { echo 'FAIL uninstalling failed after firewalld was removed'; exit 1; }
[[ -z $(ls "$DATA/firewall") ]] || { echo 'FAIL records left after firewalld was removed'; exit 1; }
echo 'PASS uninstalling after firewalld was removed drops its records'
firewall-cmd() {
    case $1 in --state) return 0;; --get-active-zones) printf 'public\n';; *) printf 'query failed\n'; return 254;; esac
}
if firewall_sync "$work/state"; then echo 'FAIL unknown firewall state accepted'; exit 1; fi
echo 'PASS query failures do not create permission records or mutate rules'
