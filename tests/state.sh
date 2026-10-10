#!/usr/bin/env bash
# State schema 2: migration from schema 1, several nodes of one protocol,
# node-scoped routing rules and the 1–65535 port range. No core or root needed.
# Assertions use `|| fail` because `! cmd` never trips set -e, and bash 3.2
# (macOS) also ignores a failing [[ ]].
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/current/state.json
mkdir -p "$SRM_ROOT" "$DATA/current" "$DATA/generations"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"

# A schema 1 state as written by the v4 skeleton: three Reality nodes, a global rule.
jq -n '{schema:1,policies:[{name:"Netflix",mode:"dns",domains:["netflix.com"]}],unlock_dns:"192.0.2.53",egress:null,nodes:[
 {id:"1111111111111111",name:"r1",type:"vless",enabled:true,host:"192.0.2.1",port:18101,sni:"www.python.org",uuid:"0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a51",private_key:"private1",public_key:"public1",short_id:"0123456789abcde1"},
 {id:"2222222222222222",name:"r2",type:"vless",enabled:true,host:"192.0.2.1",port:18102,sni:"www.mozilla.org",uuid:"0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a52",private_key:"private2",public_key:"public2",short_id:"0123456789abcde2"},
 {id:"3333333333333333",name:"r3",type:"vless",enabled:false,host:"192.0.2.1",port:18103,sni:"www.python.org",uuid:"0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a53",private_key:"private3",public_key:"public3",short_id:"0123456789abcde3"}]}' > "$work/v1.json"
cp "$work/v1.json" "$work/v1-original.json"

state_upgrade "$work/v1.json" > "$work/v2.json" || fail 'upgrade schema 1'
jq -e '.schema==2' "$work/v2.json" >/dev/null || fail 'schema not 2'
[[ $(jq -cS 'del(.schema)' "$work/v2.json") == "$(jq -cS 'del(.schema)' "$work/v1.json")" ]] || fail 'migration changed nodes or policies'
cmp -s "$work/v1.json" "$work/v1-original.json" || fail 'upgrade modified its input'
validate_state "$work/v2.json" || fail 'migrated state invalid'
if validate_state "$work/v1.json" 2>/dev/null; then fail 'schema 1 accepted without migration'; fi
state_upgrade "$work/v2.json" > "$work/again.json" || fail 'upgrade schema 2'
[[ $(jq -cS . "$work/again.json") == "$(jq -cS . "$work/v2.json")" ]] || fail 'schema 2 not passed through'
for bad in '.schema=3' '.schema=0' '.schema="1"' 'del(.schema)'; do
    jq "$bad" "$work/v1.json" > "$work/bad.json"
    if state_upgrade "$work/bad.json" > /dev/null 2> "$work/err"; then fail "upgrade accepted $bad"; fi
    grep -q '不受支持' "$work/err" || fail "message for $bad"
done
printf 'not json' > "$work/bad.json"
if state_upgrade "$work/bad.json" > /dev/null 2>&1; then fail 'upgrade accepted garbage'; fi
echo 'PASS schema 1 migrates to 2 with nodes and rules unchanged; unknown or newer schemas are refused'

# Every change reads the current state through the upgrade, so the first change
# after a script update writes schema 2 and keeps the nodes.
apply_state() { validate_state "$1" && cp "$1" "$STATE"; }
cp "$work/v1.json" "$STATE"
node_change 2222222222222222 name renamed > /dev/null || fail 'change on schema 1 state'
jq -e '.schema==2 and .nodes[1].name=="renamed"' "$STATE" >/dev/null || fail 'change did not migrate'
[[ $(jq -cS 'del(.schema)|.nodes[1].name="r2"' "$STATE") == "$(jq -cS 'del(.schema)' "$work/v1.json")" ]] || fail 'migration during change altered nodes'
cp "$work/v1.json" "$STATE"
routing_change dns 192.0.2.54 > /dev/null || fail 'routing change on schema 1 state'
jq -e '.schema==2 and .unlock_dns=="192.0.2.54" and (.nodes|length)==3' "$STATE" >/dev/null || fail 'routing change did not migrate'
jq '.schema=3' "$work/v1.json" > "$STATE"
before=$(sha256 "$STATE")
if node_change 1111111111111111 name x > /dev/null 2>&1; then fail 'change on newer schema accepted'; fi
[[ $(sha256 "$STATE") == "$before" ]] || fail 'newer schema state modified'
echo 'PASS the first change after an update migrates schema 1 and keeps the nodes; a newer schema is left untouched'

# The real transaction stores the migrated copy, so rolling back to a schema 1
# generation works and the old generation file itself is not rewritten.
unset -f apply_state
source lib/system.sh
chgrp() { :; }
systemctl() { case $1 in is-active) return 3;; *) return 0;; esac; }
service_healthy() { return 0; }
firewall_sync() { return 0; }
# BSD mv has no -T; the real atomic switch is covered by tests/install-live.sh.
switch_generation() { rm -f "$DATA/current" && ln -s "$1" "$DATA/current"; }
printf '#!/bin/sh\nexit 0\n' > "$work/core"; chmod 755 "$work/core"
CORE=$work/core
rm -f "$STATE"; rmdir "$DATA/current"
apply_state "$work/v1.json" > /dev/null || fail 'apply schema 1 state'
jq -e '.schema==2' "$STATE" >/dev/null || fail 'applied generation not migrated'
[[ $(jq -cS 'del(.schema)' "$STATE") == "$(jq -cS 'del(.schema)' "$work/v1.json")" ]] || fail 'applied generation changed nodes'
cmp -s "$work/v1.json" "$work/v1-original.json" || fail 'apply_state modified its input'
jq -e '[.inbounds[].tag]==["1111111111111111","2222222222222222"]' "$DATA/current/config.json" >/dev/null || fail 'rendered config'
[[ ! -e $DATA/pending.json ]] || fail 'pending marker left behind'
echo 'PASS the configuration transaction applies a schema 1 file as schema 2 without rewriting it'

# Policies may name the nodes they apply to.
cp "$work/v2.json" "$work/s.json"
jq '.policies[0].inbounds=["2222222222222222"]' "$work/s.json" > "$work/scoped.json"
validate_state "$work/scoped.json" || fail 'scoped policy rejected'
for bad in '.policies[0].inbounds=[]' '.policies[0].inbounds=["9999999999999999"]' '.policies[0].inbounds=["1111111111111111","1111111111111111"]' \
           '.policies[0].inbounds="1111111111111111"' '.policies[0].inbounds=[1]'; do
    jq "$bad" "$work/s.json" > "$work/bad.json"
    if validate_state "$work/bad.json" 2>/dev/null; then fail "accepted $bad"; fi
done
echo 'PASS policy inbounds must be a non-empty list of distinct existing node IDs'

# Rendering: a scoped rule carries the inbound list everywhere it is matched;
# a global rule has none; a rule for a stopped node never becomes global.
jq '.egress={type:"socks",version:"5",server:"192.0.2.80",server_port:1080} |
    .policies=[{name:"Global",mode:"dns",domains:["netflix.com"]},
               {name:"Scoped",mode:"proxy",domains:["youtube.com"],inbounds:["2222222222222222"]},
               {name:"Stopped",mode:"dns",domains:["disneyplus.com"],inbounds:["3333333333333333"]}]' "$work/s.json" > "$work/r.json"
render_config "$work/r.json" > "$work/config.json" || fail render
jq -e '
  ([.route.rules[]|select(.domain_suffix==["youtube.com"])]==[{inbound:["2222222222222222"],domain_suffix:["youtube.com"],action:"route",outbound:"media-proxy"}]) and
  ([.dns.rules[]|select(.domain_suffix==["youtube.com"])|.inbound]==[["2222222222222222"]]) and
  ([.route.rules[]|select(.domain_suffix==["netflix.com"])|has("inbound")]==[false,false]) and
  ([.dns.rules[]|select(.domain_suffix==["netflix.com"])|has("inbound")]==[false]) and
  ([.route.rules[]|select(.domain_suffix==["disneyplus.com"])|.inbound]==[["3333333333333333"],["3333333333333333"]]) and
  ([.inbounds[].tag]|index("3333333333333333"))==null and
  ([.route.rules[]|select(.domain_suffix)|.outbound // .action]==["media-proxy","resolve","direct","resolve","direct"]) and
  .route.final=="direct" and .dns.final=="local"' "$work/config.json" >/dev/null || { cat "$work/config.json"; fail 'scoped render'; }
echo 'PASS scoped rules match only their inbounds; global rules stay global; proxy rules still come first'

# Overlapping domains in opposite modes conflict only when the node sets meet.
jq '.unlock_dns="192.0.2.53"|.egress={type:"socks",version:"5",server:"192.0.2.80",server_port:1080}|
    .policies=[{name:"A",mode:"dns",domains:["example.com"],inbounds:["1111111111111111"]},{name:"B",mode:"proxy",domains:["video.example.com"],inbounds:["2222222222222222"]}]' "$work/s.json" > "$work/c.json"
routing_check_conflicts "$work/c.json" || fail 'disjoint nodes reported as conflict'
jq '.policies[1].inbounds=["2222222222222222","1111111111111111"]' "$work/c.json" > "$work/c2.json"
if routing_check_conflicts "$work/c2.json" 2>/dev/null; then fail 'shared node not reported'; fi
jq '.policies[1]|=del(.inbounds)' "$work/c.json" > "$work/c3.json"
if routing_check_conflicts "$work/c3.json" 2>/dev/null; then fail 'global vs scoped not reported'; fi
echo 'PASS conflict check considers which nodes each rule applies to'

# Non-interactive: --nodes limits a rule; unknown IDs or a missing value change nothing.
apply_state() { validate_state "$1" && cp "$1" "$STATE"; }
cp "$work/v2.json" "$STATE"
if routing_change add Video proxy youtube.com --nodes 2222222222222222,1111111111111111 < /dev/null > /dev/null 2>&1; then
    fail 'proxy rule without egress accepted'
fi
routing_change egress 192.0.2.80 1080 > /dev/null || fail 'egress'
routing_change add Video proxy youtube.com --nodes 2222222222222222,1111111111111111 > /dev/null || fail 'add --nodes'
jq -e '.policies[-1]=={name:"Video",mode:"proxy",domains:["youtube.com"],inbounds:["1111111111111111","2222222222222222"]}' "$STATE" >/dev/null || fail 'stored inbounds'
routing_change add Video proxy --nodes 2222222222222222 googlevideo.com youtube.com > /dev/null || fail '--nodes before domains'
jq -e '.policies[-1]=={name:"Video",mode:"proxy",domains:["googlevideo.com","youtube.com"],inbounds:["2222222222222222"]}' "$STATE" >/dev/null || fail 'replace scoped rule'
# Replacing a rule without --nodes keeps its nodes; only "all" widens it on purpose.
routing_change add Video proxy youtube.com > /dev/null || fail 'replace without --nodes'
jq -e '.policies[-1]=={name:"Video",mode:"proxy",domains:["youtube.com"],inbounds:["2222222222222222"]}' "$STATE" >/dev/null || fail 'replacement widened the rule'
routing_change add Video proxy youtube.com --nodes all > /dev/null || fail '--nodes all'
jq -e '.policies[-1]=={name:"Video",mode:"proxy",domains:["youtube.com"]}' "$STATE" >/dev/null || fail '--nodes all should make the rule global'
routing_change add Video proxy youtube.com --nodes 2222222222222222 > /dev/null || fail 'scope again'
before=$(sha256 "$STATE")
for bad in 'add X dns a.com --nodes 9999999999999999' 'add X dns a.com --nodes' 'add X dns a.com --nodes ,' 'add X dns --nodes 1111111111111111'; do
    # shellcheck disable=SC2086 # split the argument list
    if routing_change $bad > /dev/null 2>&1 < /dev/null; then fail "accepted routing $bad"; fi
done
[[ $(sha256 "$STATE") == "$before" ]] || fail 'rejected routing changes modified state'
routing_show > "$work/show" 2>&1 || fail 'routing show'
grep -q '"r2"' "$work/show" && grep -q '全部节点' "$work/show" || { cat "$work/show"; fail 'show lists node names'; }
echo 'PASS srm routing add --nodes stores the node scope; unknown IDs and missing values are rejected'

# Menu: pick nodes by number; Enter keeps the rule on every node.
routing_menu <<< $'4\nN2\nnetflix.com\ndns\n1 3' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu scoped rule'; }
grep -q '1. r1 | vless | 端口 18101' "$work/out" || fail 'menu lists nodes'
jq -e '.policies[]|select(.name=="N2")|.inbounds==["1111111111111111","3333333333333333"]' "$STATE" >/dev/null || fail 'menu stored inbounds'
routing_menu <<< $'4\nN3\nhulu.com\ndns\n' > /dev/null 2>&1 || fail 'menu default scope'
jq -e '.policies[]|select(.name=="N3")|has("inbounds")|not' "$STATE" >/dev/null || fail 'Enter should mean every node'
# Replacing a scoped rule from the menu offers its current nodes as the default.
routing_menu <<< $'4\nN2\nnetflix.com nflxvideo.net\ndns\n' > "$work/out" 2>&1 || fail 'menu replace'
grep -q '\[1 3\]' "$work/out" || fail 'current nodes not offered as default'
jq -e '.policies[]|select(.name=="N2")|.inbounds==["1111111111111111","3333333333333333"] and .domains==["netflix.com","nflxvideo.net"]' "$STATE" >/dev/null || fail 'menu replace widened the rule'
routing_menu <<< $'4\nN2\nnetflix.com\ndns\n全部' > /dev/null 2>&1 || fail 'menu choose all'
jq -e '.policies[]|select(.name=="N2")|has("inbounds")|not' "$STATE" >/dev/null || fail 'choosing 全部 should make the rule global'
before=$(sha256 "$STATE")
for bad in '4' '1 9' 'x' '*' '1,2'; do
    routing_menu <<< $'4\nN4\nmax.com\ndns\n'"$bad" > "$work/out" 2>&1 || true
    grep -q '请输入 1–3 的序号' "$work/out" || fail "no message for node choice $bad"
done
routing_menu <<< $'4\nN4\nmax.com\ndns\n0' > /dev/null 2>&1 || fail '0 should return quietly'
[[ $(sha256 "$STATE") == "$before" ]] || fail 'bad menu choices modified state'
echo 'PASS routing menu picks nodes by number, Enter means every node, 0 returns, bad numbers change nothing'

# Deleting a node removes it from scoped rules; a rule left with no node goes too.
jq '.policies=[{name:"Only1",mode:"dns",domains:["a.com"],inbounds:["1111111111111111"]},
               {name:"Both",mode:"dns",domains:["b.com"],inbounds:["1111111111111111","2222222222222222"]},
               {name:"All",mode:"dns",domains:["c.com"]}]' "$work/v2.json" > "$STATE"
node_change 1111111111111111 delete > "$work/out" || fail delete
grep -q '分流规则「Only1」只作用于这个节点，已一并删除' "$work/out" || fail 'delete message'
jq -e '[.nodes[].id]==["2222222222222222","3333333333333333"] and
       .policies==[{name:"Both",mode:"dns",domains:["b.com"],inbounds:["2222222222222222"]},{name:"All",mode:"dns",domains:["c.com"]}]' "$STATE" >/dev/null || fail 'policies after delete'
echo 'PASS deleting a node prunes scoped rules without widening any of them'

# Ports: 1–65535 accepted in state and when deploying; random stays in 10000–50000.
for port in 1 443 65535; do
    jq --argjson p "$port" '.nodes[0].port=$p' "$work/v2.json" > "$work/p.json"
    validate_state "$work/p.json" || fail "port $port rejected"
done
for port in 0 65536 1.5 '"443"'; do
    jq --argjson p "$port" '.nodes[0].port=$p' "$work/v2.json" > "$work/p.json"
    if validate_state "$work/p.json" 2>/dev/null; then fail "port $port accepted"; fi
done
printf '#!/usr/bin/env bash\ncase $2 in reality-keypair) printf "PrivateKey: priv%%s\\nPublicKey: pub%%s\\n" $RANDOM $RANDOM;; uuid) printf "%%s\\n" 0f2a6c1e-3b4d-4e5f-8a9b-$(openssl rand -hex 6);; esac\n' > "$work/core"
ensure_dependencies() { return 0; }
reality_target_check() { return 0; }
# Certificate domains resolve to the node's address.
resolve_domain() { printf '192.0.2.1\n'; }
ss() { return 0; }
sysctl() { return 1; }
cp "$work/v2.json" "$STATE"
node_add self vless --host 192.0.2.1 --port 443 --yes > /dev/null 2>&1 || fail 'deploy on 443'
node_add self vless --host 192.0.2.1 --port 1 --yes > /dev/null 2>&1 || fail 'deploy on 1'
node_add self vless --host 192.0.2.1 --yes > /dev/null 2>&1 || fail 'deploy random'
jq -e '[.nodes[-3:][].port][0:2]==[443,1] and (.nodes[-1].port>=10000 and .nodes[-1].port<=50000)' "$STATE" >/dev/null || fail 'ports stored'
before=$(sha256 "$STATE")
for port in 0 65536 443 abc; do
    if node_add self vless --host 192.0.2.1 --port "$port" --yes > /dev/null 2>&1; then fail "deploy accepted port $port"; fi
done
if node_change 2222222222222222 port 443 > /dev/null 2>&1; then fail 'port taken by another node accepted'; fi
[[ $(sha256 "$STATE") == "$before" ]] || fail 'rejected ports modified state'
node_change 2222222222222222 port 8443 > /dev/null || fail 'change to 8443'
echo 'PASS ports 1–65535 deploy and validate; out-of-range or taken ports are refused; random stays 10000–50000'

# Several nodes of one protocol: numbered default names; the menu needs no extra screen.
[[ $(jq -r '[.nodes[-3:][].name]|join(" ")' "$STATE") == 'vless vless-2 vless-3' ]] || fail "default names: $(jq -c '[.nodes[].name]' "$STATE")"
node_change "$(jq -r '.nodes[-2].id' "$STATE")" delete > /dev/null || fail 'delete vless-2'
node_add self vless --host 192.0.2.1 --yes > /dev/null 2>&1 || fail 'another vless'
[[ $(jq -r '.nodes[-1].name' "$STATE") == vless-2 ]] || fail 'first free numbered name reused'
[[ $(jq '[.nodes[]|select(.type=="vless")]|length' "$STATE") == 6 ]] || fail 'six vless nodes'
jq -e '[.nodes[].port]|length==(unique|length)' "$STATE" >/dev/null || fail 'ports unique'
echo 'PASS repeated deploys of one protocol give independent nodes with numbered default names'

# Certificate renewal validates on TCP 80 or 443. A TCP node may not take the
# port a renewed certificate needs; UDP nodes and other ports are fine.
jq '.nodes += [{id:"4444444444444444",name:"a",type:"anytls",enabled:true,host:"192.0.2.1",port:18104,sni:"test.example.com",password:"pw",cert_dir:"/certs"}]' "$work/v2.json" > "$STATE"
mkdir -p "$DATA/certs/test.example.com/active" "$SRM_ROOT/acme-accounts/test.example.com"
printf 'acme\n' > "$DATA/certs/test.example.com/active/renewal-source"
printf '443\n' > "$SRM_ROOT/acme-accounts/test.example.com/challenge-port"
if cert_port_ok 443 tcp 2> "$work/err"; then fail 'renewal port accepted for tcp'; fi
grep -q 'TCP 443 要留给证书 test.example.com 自动续期验证' "$work/err" || fail 'renewal port message'
cert_port_ok 443 udp || fail 'udp node on 443 refused'
cert_port_ok 80 tcp || fail '80 refused although renewal uses 443'
before=$(sha256 "$STATE")
if node_add self vless --host 192.0.2.1 --port 443 --yes > /dev/null 2>&1; then fail 'deploy on renewal port accepted'; fi
if node_change 1111111111111111 port 443 > /dev/null 2>&1; then fail 'move onto renewal port accepted'; fi
[[ $(sha256 "$STATE") == "$before" ]] || fail 'renewal-port refusals modified state'
issue_certificate() { :; }
node_add self hysteria2 --host 192.0.2.1 --port 443 --sni test.example.com --yes > /dev/null 2>&1 || fail 'udp node on 443'
# A certificate issued (or reused) during deploy that validates on the node's own
# port is caught after issuing, before anything is applied.
issue_certificate() {
    mkdir -p "$DATA/certs/$1/active" "$SRM_ROOT/acme-accounts/$1"
    printf 'acme\n' > "$DATA/certs/$1/active/renewal-source"
    printf '80\n' > "$SRM_ROOT/acme-accounts/$1/challenge-port"
}
before=$(sha256 "$STATE")
if node_add self anytls --host 192.0.2.1 --port 80 --sni new.example.com --yes > "$work/out" 2>&1; then fail 'node on its own renewal port accepted'; fi
grep -q 'TCP 80 要留给证书 new.example.com' "$work/out" && grep -q '换一个端口重新部署时会直接复用' "$work/out" || fail 'post-issue message'
[[ $(sha256 "$STATE") == "$before" ]] || fail 'post-issue refusal modified state'
# Automatic validation steers clear of the port the new node will use.
cert_avoid_port=''; [[ $(cert_auto_mode) == http ]] || fail 'auto mode default'
cert_avoid_port=80; [[ $(cert_auto_mode) == alpn ]] || fail 'auto mode avoids 80'
cert_avoid_port=443; [[ $(cert_auto_mode) == http ]] || fail 'auto mode avoids 443'
ss() { [[ $* == *':80'* ]] && printf 'LISTEN 0 0 *:80 *:*\n'; return 0; }
if cert_avoid_port=443 cert_auto_mode > /dev/null; then fail 'auto mode picked a busy or reserved port'; fi
cert_avoid_port=''
# A stopped TCP node on 443 still owns it; a UDP node on 443 does not.
jq '.nodes[0].port=443 | .nodes[0].enabled=false' "$work/v2.json" > "$STATE"
if cert_auto_mode > /dev/null; then fail 'auto mode took the port of a stopped TCP node'; fi
jq '.nodes += [{id:"5555555555555555",name:"h",type:"hysteria2",enabled:true,host:"192.0.2.1",port:443,sni:"test.example.com",password:"pw",cert_dir:"/certs"}]' "$work/v2.json" > "$STATE"
[[ $(cert_auto_mode) == alpn ]] || fail 'UDP node on 443 should not block alpn'
echo 'PASS TCP nodes cannot take a certificate renewal port; automatic validation avoids the new node port'
