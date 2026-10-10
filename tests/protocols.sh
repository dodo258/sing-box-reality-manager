#!/usr/bin/env bash
# Protocol registry: every protocol is one block of hooks, unknown names are
# rejected, and other modules dispatch only through the registry.
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
mkdir -p "$SRM_ROOT" "$DATA/current"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"

[[ $PROTOCOLS == 'vless anytls hysteria2 shadowsocks tuic vlesstls trojan vmess naive hysteria' ]] || fail "registered: $PROTOCOLS"
for type in $PROTOCOLS; do
    for hook in $PROTO_HOOKS; do declare -F "proto_${type}_$hook" >/dev/null || fail "$type lacks $hook"; done
done
[[ $(proto_call hysteria2 transport) == udp && $(proto_call vless transport) == tcp ]] || fail transport
echo 'PASS every registered protocol has every hook'

if proto_register socks 2> "$work/err"; then fail 'protocol without hooks registered'; fi
grep -q 'proto_socks_label' "$work/err" || fail 'missing hook not reported'
proto_partial_label() { printf 'Partial'; }
if proto_register partial 2>/dev/null; then fail 'protocol with missing hooks registered'; fi
if proto_register 'Bad-Name' 2>/dev/null; then fail 'invalid protocol name registered'; fi
(
    for hook in $PROTO_HOOKS; do eval "proto_half_$hook() { :; }"; done
    proto_half_retarget() { :; }
    if proto_register half 2>/dev/null; then fail 'incomplete optional hook group registered'; fi
    proto_half_retarget_select() { :; }; proto_half_retarget_label() { :; }
    proto_register half || fail 'complete optional hook group rejected'
) || exit 1
[[ $PROTOCOLS == 'vless anytls hysteria2 shadowsocks tuic vlesstls trojan vmess naive hysteria' ]] || fail "registry changed: $PROTOCOLS"
if proto_call socks label 2> "$work/err"; then fail 'unknown protocol dispatched'; fi
grep -q '不支持的协议：socks' "$work/err" || fail 'unknown protocol message'
if proto_known '' || proto_known socks || proto_known 'vless anytls'; then fail 'proto_known accepted unknown name'; fi
if proto_call anytls retarget '{}' www.ctrip.com 2>/dev/null; then fail 'optional hook dispatched to a protocol without it'; fi
echo 'PASS registry rejects unknown names, incomplete protocols and missing hooks'

jq -n '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
 {id:"1111111111111111",name:"r",type:"vless",enabled:true,host:"192.0.2.1",port:18101,sni:"www.ctrip.com",uuid:"0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a5b",private_key:"private",public_key:"public",short_id:"0123456789abcdef"},
 {id:"2222222222222222",name:"h",type:"hysteria2",enabled:true,host:"192.0.2.1",port:18103,sni:"test.example.com",password:"password",cert_dir:"/certs"}]}' > "$work/state.json"
validate_state "$work/state.json" || fail 'valid state rejected'
jq '.nodes[0].type="socks"' "$work/state.json" > "$work/unknown.json"
if validate_state "$work/unknown.json" 2>/dev/null; then fail 'unknown node type accepted'; fi
if node_json "$work/unknown.json" 1111111111111111 | share_uri >/dev/null 2>&1; then fail 'share link for unknown type'; fi
[[ $(jq -c ".nodes[]|$(proto_jq_transports)" "$work/state.json" | tr '\n' ' ') == '["tcp"] ["udp"] ' ]] || fail 'transport dispatch'
echo 'PASS state validation, links and transport dispatch reject an unknown node type'

# Deploying an unknown protocol fails before prompting, setup or any change.
setup() { touch "$work/setup-called"; }
cp "$work/state.json" "$STATE"
before=$(sha256 "$STATE")
if node_add self socks --name x --host 192.0.2.1 --port 20000 --yes > "$work/out" 2>&1; then fail 'node_add accepted socks'; fi
grep -q '不支持的协议：socks' "$work/out" || fail 'node_add message'
[[ $(sha256 "$STATE") == "$before" && ! -e $work/setup-called ]] || fail 'unknown protocol changed state'
if node_add self anytls --yes > "$work/out" 2>&1; then fail 'non-interactive add without --host accepted'; fi
grep -q '非交互模式缺少参数' "$work/out" || fail 'missing option message'
if node_add self vless --host 192.0.2.1 --bogus 1 --yes 2>/dev/null; then fail 'unknown option accepted'; fi
if node_add self vless --host 192.0.2.1 --sni example.com --yes 2>/dev/null; then fail 'unverified Reality target accepted'; fi
[[ $(sha256 "$STATE") == "$before" ]] || fail 'rejected adds changed state'
echo 'PASS deploying an unknown protocol or with missing/invalid options changes nothing'

# Non-interactive Reality deployment: each node gets its own random shortId.
printf '#!/usr/bin/env bash\ncase $2 in reality-keypair) printf "PrivateKey: priv%%s\\nPublicKey: pub%%s\\n" $RANDOM $RANDOM;; uuid) printf "%%s\\n" 0f2a6c1e-3b4d-4e5f-8a9b-$(openssl rand -hex 6);; esac\n' > "$work/core"
chmod 755 "$work/core"
CORE=$work/core
ensure_dependencies() { return 0; }
reality_target_check() { [[ $1 == www.ctrip.com || $1 == www.ixigua.com ]]; }
ss() { return 0; }
sysctl() { return 1; }
apply_state() { validate_state "$1" && cp "$1" "$STATE"; }
jq '.nodes=[]' "$work/state.json" > "$STATE"
node_add self vless --name one --host 192.0.2.1 --port 20001 --yes > "$work/out" 2>&1 || { cat "$work/out"; fail 'non-interactive add'; }
node_add self vless --name two --host 192.0.2.1 --port random --sni www.ixigua.com --yes > "$work/out" 2>&1 || { cat "$work/out"; fail 'second add'; }
grep -q '^vless://' "$work/out" || fail 'share link printed after deploy'
[[ $(jq '.nodes|length' "$STATE") == 2 ]] || fail 'two nodes expected'
a=$(jq -r '.nodes[0].short_id' "$STATE"); b=$(jq -r '.nodes[1].short_id' "$STATE")
[[ $a =~ ^[a-f0-9]{16}$ && $b =~ ^[a-f0-9]{16}$ && $a != "$b" && $a != 0123456789abcdef ]] || fail "shortIds $a $b"
jq -e '.nodes[0].sni=="www.ctrip.com" and .nodes[1].sni=="www.ixigua.com" and .nodes[1].port>=10000 and .nodes[1].port<=50000' "$STATE" >/dev/null || fail 'defaults'
[[ ! -e $work/setup-called ]] || fail 'setup called on an installed system'
echo 'PASS non-interactive Reality deploy; every node gets its own random shortId'

id=$(jq -r '.nodes[0].id' "$STATE")
old=$(jq -r '.nodes[0].uuid' "$STATE")
node_change "$id" rotate
[[ $(jq -r '.nodes[0].uuid' "$STATE") != "$old" && $(jq -r '.nodes[0].short_id' "$STATE") == "$a" ]] || fail rotate
echo 'PASS credential rotation dispatches through the registry'

# QR codes come only from local qrencode; without it, only the link is shown.
mkdir "$work/min"
ln -s "$(command -v jq)" "$work/min/jq"
(PATH=$work/min; export_node "$id" qr) > "$work/qr" 2>&1 || fail 'qr without qrencode'
grep -q '^vless://' "$work/qr" && grep -q '未安装 qrencode' "$work/qr" || fail 'qr fallback'
printf '#!/bin/bash\n/bin/cat > %s/qr-input\necho QR\n' "$work" > "$work/min/qrencode"; chmod 755 "$work/min/qrencode"
(PATH=$work/min; export_node "$id" qr) > "$work/qr" 2>&1 || fail 'qr with qrencode'
grep -q '^QR$' "$work/qr" && grep -q '^vless://' "$work/qr-input" || fail 'qrencode input'
if grep -rqiE 'qrserver|api\.qr|chart\.googleapis' lib/; then fail 'third-party QR service referenced'; fi
echo 'PASS QR codes use only local qrencode and fall back to the link'

# Adding a protocol is one block of hooks; config, links and firewall follow.
(
    proto_demo_label() { printf 'Demo'; }
    proto_demo_transport() { printf 'udp'; }
    proto_demo_validate() { printf '%s' '(.password|text)'; }
    proto_demo_render_inbound() { printf '%s' '[base_inbound + {type:"demo",password:.password}]'; }
    proto_demo_share_uri() { printf '%s' '"demo://\(.password)@\(uri_host):\(.port)"'; }
    proto_demo_client_outbound() { printf '%s' 'base_outbound + {type:"demo"}'; }
    proto_demo_secrets() { printf '%s' '.password'; }
    proto_demo_prompt() { sni=$host; }
    proto_demo_create() { REPLY='{"password":"pw"}'; }
    proto_demo_rotate() { REPLY='{"password":"new"}'; }
    proto_register demo
    [[ $PROTOCOLS == 'vless anytls hysteria2 shadowsocks tuic vlesstls trojan vmess naive hysteria demo' ]] || fail 'demo not registered'
    jq '.nodes += [{id:"4444444444444444",name:"d",type:"demo",enabled:true,host:"2001:db8::1",port:18104,sni:"demo.example.com",password:"pw"}]' "$work/state.json" > "$work/demo.json"
    render_config "$work/demo.json" | jq -e '.inbounds[-1]=={tag:"4444444444444444",listen:"::",listen_port:18104,type:"demo",password:"pw"}' >/dev/null || fail 'demo render'
    [[ $(node_json "$work/demo.json" 4444444444444444 | share_uri) == 'demo://pw@[2001:db8::1]:18104' ]] || fail 'demo link'
    [[ $(jq -c ".nodes[-1]|$(proto_jq_transports)" "$work/demo.json") == '["udp"]' ]] || fail 'demo transport'
) || exit 1
echo 'PASS a new protocol plugs in by adding one block of hooks'

# Only the registry may branch on protocol type names.
if grep -nwE "$(tr ' ' '|' <<< "$PROTOCOLS")" lib/*.sh | grep -v '^lib/protocols.sh:'; then fail 'protocol type matched outside lib/protocols.sh'; fi
echo 'PASS no module outside lib/protocols.sh matches protocol type names'
