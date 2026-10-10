#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
need_core
CORE=${TEST_CORE:?set TEST_CORE to the validated sing-box binary}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
STATE=$work/state.json
pair=$("$CORE" generate reality-keypair)
private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
uuid=$("$CORE" generate uuid)
jq -n --arg private "$private" --arg public "$public" --arg uuid "$uuid" \
 '{schema:1,nodes:[{id:"1111111111111111",name:"test",type:"vless",enabled:true,host:"127.0.0.1",port:18101,sni:"www.microsoft.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"}],policies:[],unlock_dns:null,egress:null}' > "$STATE"
cp "$STATE" "$work/original.json"
reality_target_check() { [[ ${probe_failure:-0} == 0 ]]; }
apply_state() {
    render_config "$1" > "$work/config.json" && "$CORE" check -c "$work/config.json" || return 1
    [[ ${apply_failure:-0} == 0 ]] || return 1
    cp "$1" "$STATE"
}
node_change 1111111111111111 retarget www.ctrip.com
jq -e '.nodes[0].sni=="www.ctrip.com"' "$STATE" >/dev/null
[[ $(jq -c 'del(.nodes[0].sni)' "$STATE") == "$(jq -c 'del(.nodes[0].sni)' "$work/original.json")" ]] || exit 1
jq -e '.inbounds[0].tls.server_name=="www.ctrip.com" and .inbounds[0].tls.reality.handshake.server=="www.ctrip.com"' "$work/config.json" >/dev/null
node_json "$STATE" 1111111111111111 | share_uri | grep -q 'sni=www.ctrip.com'
node_change 1111111111111111 retarget www.ixigua.com
node_json "$STATE" 1111111111111111 | share_uri | grep -q 'sni=www.ixigua.com'
echo 'PASS Reality switch updates handshake, SNI and raw URI while preserving credentials and port'
before=$(sha256 "$STATE")
probe_failure=1
! node_change 1111111111111111 retarget www.ctrip.com || exit 1
[[ $(sha256 "$STATE") == "$before" ]] || exit 1
probe_failure=0; apply_failure=1
! node_change 1111111111111111 retarget www.ctrip.com || exit 1
[[ $(sha256 "$STATE") == "$before" ]] || exit 1
node_change 1111111111111111 retarget www.ixigua.com >/dev/null
[[ $(sha256 "$STATE") == "$before" ]] || exit 1
! node_change 1111111111111111 retarget custom.example.com 2>/dev/null || exit 1
[[ $(sha256 "$STATE") == "$before" ]] || exit 1
echo 'PASS failed target check, failed apply, same target and unsupported target do not change state'
apply_failure=0
jq '.nodes[0].type="anytls"' "$STATE" > "$work/anytls.json"
cp "$work/anytls.json" "$STATE"
! node_change 1111111111111111 retarget www.ctrip.com 2>/dev/null || exit 1
cmp "$STATE" "$work/anytls.json"
echo 'PASS non-Reality nodes reject a Reality target switch'
cp "$work/original.json" "$STATE"
jq '.unlock_dns="1.1.1.1"|.egress={type:"socks",version:"5",server:"127.0.0.1",server_port:18111}|.policies=[{name:"DNS",mode:"dns",domains:["example.com"]},{name:"Proxy",mode:"proxy",domains:["video.example.com"]}]' "$STATE" > "$work/routing.json"
! routing_check_conflicts "$work/routing.json" > /dev/null 2>&1 || exit 1
jq '.policies|=reverse' "$work/routing.json" > "$work/reverse.json"
! routing_check_conflicts "$work/reverse.json" >/dev/null 2>&1 || exit 1
jq '.policies[1].domains=["example.com"]' "$work/routing.json" > "$work/exact.json"
! routing_check_conflicts "$work/exact.json" >/dev/null 2>&1 || exit 1
jq '.policies[1].domains=["notexample.com","example.com.invalid"]' "$work/routing.json" > "$work/distinct.json"
routing_check_conflicts "$work/distinct.json"
jq '.policies[1].mode="dns"' "$work/routing.json" > "$work/same-mode.json"
routing_check_conflicts "$work/same-mode.json"
echo 'PASS routing overlap detects parent/child in both directions without lookalike or same-mode false positives'
# Reject an ambiguous new rule before apply_state. Preserve legacy rules and let
# the owner edit unrelated platforms without silently rewriting existing routing.
jq '.policies=[.policies[0]]' "$work/routing.json" > "$STATE"
before=$(sha256 "$STATE")
! routing_menu <<< $'4\nProxy\nvideo.example.com\nproxy' > "$work/result" 2>&1 || exit 1
[[ $(sha256 "$STATE") == "$before" ]] || exit 1
grep -q '范围重叠' "$work/result"
cp "$work/routing.json" "$STATE"
before=$(sha256 "$STATE")
routing_menu <<< 1 > "$work/result" 2>&1
[[ $(sha256 "$STATE") == "$before" ]] || exit 1
grep -q '已有规则保持原状' "$work/result"
routing_menu <<< $'4\nOther\nexample.org\ndns' >/dev/null 2>&1
jq -e '.policies|length==3' "$STATE" >/dev/null
jq -e '.route.final=="direct" and .dns.final=="local"' "$work/config.json" >/dev/null
echo 'PASS conflicting menu edits are blocked; legacy policies and default direct traffic remain intact'
