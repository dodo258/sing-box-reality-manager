#!/usr/bin/env bash
# Hysteria2 port hopping: validation, the link and client formats, the redirect rules
# (iptables / ip6tables nat and nftables, modelled here; tests/firewall-live.sh sends
# real packets) and the menu. System commands are replaced; nothing touches the host.
# Assertions use `|| fail` because `! cmd` never trips set -e, and bash 3.2
# (macOS) also ignores a failing [[ ]].
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/current/state.json
HOP_LOCK=$work/hop.lock
mkdir -p "$SRM_ROOT" "$DATA/current" "$work/bin"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
for tool in curl wget; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/network-calls"\nexit 1\n' "$tool" "$work" > "$work/bin/$tool"
done
printf '#!/usr/bin/env bash\ncat > /dev/null\necho "[QR $*]"\n' > "$work/bin/qrencode"
chmod 755 "$work/bin/"*
export PATH="$work/bin:$PATH"
require_linux() { return 0; }
with_lock() { "$@"; }
systemctl() { case $1 in is-active|is-enabled) return 3;; esac; }
ensure_dependencies() { return 0; }
sysctl() { return 1; }
chgrp() { :; }
detect_public_ip() { PUBLIC_IP=192.0.2.10; PUBLIC_LOC=JP; }
# UDP listeners on this machine, "PORT" per line, for ss.
: > "$work/listening"
ss() {
    local filter=${*: -1} port
    while IFS= read -r port; do
        [[ -n $port ]] || continue
        if [[ $filter =~ ^sport\ \>=\ :([0-9]+)\ and\ sport\ \<=\ :([0-9]+)$ ]]; then
            (( port >= BASH_REMATCH[1] && port <= BASH_REMATCH[2] )) && printf 'UNCONN 0 0 0.0.0.0:%s 0.0.0.0:*\n' "$port"
        elif [[ $filter == "sport = :$port" ]]; then printf 'UNCONN 0 0 0.0.0.0:%s 0.0.0.0:*\n' "$port"; fi
    done < "$work/listening"
    return 0
}

# The nat table PREROUTING chain per family as `iptables -t nat -S PREROUTING` lists it;
# a Docker rule that is not ours must stay.
nat_mock() {
    local rules=$work/nat-$1 action; shift
    [[ $1 != -w ]] || shift 2
    [[ $1 == -t && $2 == nat ]] || return 2
    action=$3; shift 4
    case $action in
      -S) cat "$rules";;
      -A) printf '%s\n' "-A PREROUTING $*" >> "$rules"; printf '%s %s\n' "$action" "$*" >> "$work/nat-calls";;
      -D)
        grep -Fxq -- "-A PREROUTING $*" "$rules" || return 1
        grep -Fxv -- "-A PREROUTING $*" "$rules" > "$rules.new" || true
        mv "$rules.new" "$rules"; printf '%s %s\n' "$action" "$*" >> "$work/nat-calls";;
      *) return 2;;
    esac
}
iptables() { nat_mock ipv4 "$@"; }
ip6tables() { nat_mock ipv6 "$@"; }
docker_rule='-A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER'
for family in ipv4 ipv6; do printf -- '-P PREROUTING ACCEPT\n%s\n' "$docker_rule" > "$work/nat-$family"; done
cp "$work/nat-ipv4" "$work/nat-original"
hop_rules() { grep -c -- '--comment srm-hop ' "$work/nat-$1" || true; }
hop_rule() { printf -- '-A PREROUTING -p udp -m addrtype --dst-type LOCAL -m udp --dport %s -m comment --comment srm-hop -j REDIRECT --to-ports %s' "$1" "$2"; }
# nftables: the ruleset handed to `nft -f -` and the tables that exist.
nft() {
    printf '%s\n' "$*" >> "$work/nft-calls"
    case $1 in
      -f) cat > "$work/nft-ruleset"; touch "$work/nft-table";;
      list) [[ -e $work/nft-table ]];;
      delete) rm -f "$work/nft-table" "$work/nft-ruleset";;
      *) return 2;;
    esac
}
nat_backend=iptables
hop_backend() { printf '%s\n' "$nat_backend"; }

# Random node ports would now and then land in the ranges this test types in.
choose_port() { local p=30100; while ! port_free "$p"; do p=$((p+1)); done; printf '%s\n' "$p"; }
pin=$(printf 'a%.0s' $(seq 64))
pubkey=$(printf 'A%.0s' $(seq 43))=
cert='{sni:"hy.example.com",cert_dir:"/certs"}'
self="{sni:\"www.bing.com\",cert_dir:\"/self\",cert_sha256:\"$pin\",pubkey_sha256:\"$pubkey\"}"
jq -n "{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
  {id:\"1000000000000001\",name:\"hy2 跳\",type:\"hysteria2\",enabled:true,host:\"192.0.2.1\",port:24000,password:\"pw/1\",hop:{start:20000,end:20999}} + $cert,
  {id:\"1000000000000002\",name:\"hy2-self\",type:\"hysteria2\",enabled:true,host:\"2001:db8::1\",port:24001,password:\"pw\",hop:{start:21000,end:21999}} + $self,
  {id:\"1000000000000003\",name:\"plain\",type:\"hysteria2\",enabled:true,host:\"192.0.2.1\",port:24002,password:\"pw\"} + $cert,
  {id:\"1000000000000004\",name:\"tuic\",type:\"tuic\",enabled:true,host:\"192.0.2.1\",port:24003,uuid:\"0f2a6c1e-3b4d-4e5f-8a9b-000000000001\",password:\"pw\"} + $cert]}" > "$STATE"
node() { jq -c --arg id "$1" '.nodes[]|select(.id==$id)' "$STATE"; }

validate_state "$STATE" >/dev/null 2>&1 || fail 'valid hop ranges rejected'
bad() { jq "$1" "$STATE" > "$work/bad"; if validate_state "$work/bad" 2>/dev/null; then fail "accepted: $2"; fi; }
bad '.nodes[3].hop={start:30000,end:30999}' 'a hop range on a protocol without port hopping'
bad '.nodes[0].hop={start:20999,end:20000}' 'start after end'
bad '.nodes[0].hop={start:20000,end:20000}' 'a range of one port'
bad '.nodes[0].hop={start:80,end:2000}' 'a range below 1024'
bad '.nodes[0].hop={start:60000,end:70000}' 'a range above 65535'
bad '.nodes[0].hop={start:"20000",end:20999}' 'a port as text'
bad '.nodes[0].hop={start:20000,end:20999,step:2}' 'unknown hop fields'
bad '.nodes[0].hop={start:23000,end:24500}' 'the own node port inside the range'
bad '.nodes[2].port=20500' 'another node port inside a range'
bad '.nodes[1].hop={start:20500,end:21500}' 'overlapping ranges'
bad '.nodes[2]+={local_port:21500}' 'a helper port inside a range'
echo 'PASS validation accepts hop ranges only on protocols with port hopping, 1024–65535, start < end, never covering a node or helper port, never overlapping'

# Links: the port stays numeric and mport carries the range (v2rayN's System.Uri rejects
# the official "port,start-end"); the note gives the official multi-port form.
[[ $(node 1000000000000001 | share_uri) == 'hysteria2://pw%2F1@192.0.2.1:24000/?sni=hy.example.com&mport=20000-20999#hy2%20%E8%B7%B3' ]] || fail "link: $(node 1000000000000001 | share_uri)"
[[ $(node 1000000000000002 | share_uri) == "hysteria2://pw@[2001:db8::1]:24001/?sni=www.bing.com&insecure=1&pinSHA256=$pin&mport=21000-21999#hy2-self" ]] || fail "self-signed link: $(node 1000000000000002 | share_uri)"
[[ $(node 1000000000000003 | share_uri) == 'hysteria2://pw@192.0.2.1:24002/?sni=hy.example.com#plain' ]] || fail 'a node without hopping has no mport'
note=$(node 1000000000000001 | client_note)
[[ $note == *'服务器把 UDP 20000–20999 转到节点端口 24000'* && $note == *'只连 24000、不换端口'* ]] || fail "note: $note"
[[ $note == *'官方多端口写法'*'：hysteria2://pw%2F1@192.0.2.1:24000,20000-20999/?sni=hy.example.com#hy2%20%E8%B7%B3' ]] || fail "official form: $note"
note=$(node 1000000000000002 | client_note)
[[ $note == *"：hysteria2://pw@[2001:db8::1]:24001,21000-21999/?sni=www.bing.com&insecure=1&pinSHA256=$pin#hy2-self" ]] || fail "official form with pin: $note"
[[ -z $(node 1000000000000003 | client_note) ]] || fail 'a node without hopping has no note'
echo 'PASS share links keep the node port and carry the range in mport; the note gives the official port,start-end form'

out=$(node 1000000000000001 | client_outbound)
jq -e '.server_port == 24000 and .server_ports == ["24000:24000","20000:20999"]' <<< "$out" >/dev/null || fail "sing-box: $out"
node 1000000000000003 | client_outbound | jq -e 'has("server_ports")|not' >/dev/null || fail 'sing-box without hopping'
[[ $(node 1000000000000001 | clash_proxy) == '- {"name":"hy2 跳","server":"192.0.2.1","port":24000,"ports":"24000,20000-20999","type":"hysteria2","password":"pw/1","sni":"hy.example.com","alpn":["h3"]}' ]] || fail "clash: $(node 1000000000000001 | clash_proxy)"
node 1000000000000003 | clash_proxy | grep -qv '"ports"' || fail 'clash without hopping'
[[ $(node 1000000000000001 | surge_proxy) == 'hy2 跳 = hysteria2, 192.0.2.1, 24000, password="pw/1", sni=hy.example.com, port-hopping=24000;20000-20999' ]] || fail "surge: $(node 1000000000000001 | surge_proxy)"
[[ $(node 1000000000000002 | surge_proxy) == "hy2-self = hysteria2, 2001:db8::1, 24001, password=\"pw\", sni=www.bing.com, server-cert-fingerprint-sha256=$pin, port-hopping=24001;21000-21999" ]] || fail "surge self-signed: $(node 1000000000000002 | surge_proxy)"
node 1000000000000001 | surge_proxy | surge_form | grep -qxF '  端口跳跃（port-hopping）：24000;20000-20999' || fail 'Surge form field'
if [[ -n ${TEST_CORE:-} ]]; then
    node 1000000000000001 | client_outbound | jq '{outbounds:[.]}' > "$work/client.json"
    "$TEST_CORE" check -c "$work/client.json" || fail 'sing-box rejects the outbound with server_ports'
fi
if [[ -n ${TEST_MIHOMO:-} ]]; then
    { printf 'proxies:\n'; node 1000000000000001 | clash_proxy | sed 's/^/  /'; } > "$work/mihomo.yaml"
    "$TEST_MIHOMO" -t -f "$work/mihomo.yaml" -d "$work/mihomo" > "$work/mihomo.out" 2>&1 || { cat "$work/mihomo.out"; fail 'mihomo rejects ports'; }
fi
# The whole client profiles take the same snippets.
profile_render sing-box "$STATE" 1000000000000001 | jq -e '[.outbounds[]|select(.server_ports == ["24000:24000","20000:20999"])]|length == 1' >/dev/null || fail 'sing-box profile'
profile_render clash "$STATE" 1000000000000001 | grep -qF '"ports":"24000,20000-20999"' || fail 'mihomo profile'
profile_render surge "$STATE" 1000000000000001 | grep -qF 'port-hopping=24000;20000-20999' || fail 'Surge profile'
echo "PASS sing-box server_ports, Clash Meta ports and Surge port-hopping list the node port and the range, also in the whole profiles${TEST_CORE:+ (sing-box check)}${TEST_MIHOMO:+ (mihomo -t)}"

# Ports: the ranges are taken; the default range skips taken blocks and listeners.
if port_free 20500; then fail 'a port inside a hop range is free'; fi
port_free 22000 || fail 'a port outside the ranges'
( hop_range=$'30000 30999'; if port_free 30500; then exit 1; fi ) || fail 'the range being deployed is taken'
[[ $(hop_default) == '22000 22999' ]] || fail "default range: $(hop_default)"
[[ $(hop_default '' 22100) == '23000 23999' ]] || fail 'default range around the node port'
[[ $(hop_default 1000000000000001 24500) == '20000 20999' ]] || fail 'the own range is free for the node'
printf '22050\n' > "$work/listening"
[[ $(hop_default) == '23000 23999' ]] || fail 'default range skips a UDP listener'
reason=$(hop_range_free 22000 22999) && fail 'listener not reported'
[[ $reason == *'0.0.0.0:22050'* ]] || fail "reason: $reason"
: > "$work/listening"
reason=$(hop_range_free 20500 21500 '' 30000) && fail 'overlap not reported'
[[ $reason == '和节点「hy2 跳」的端口跳跃范围重叠' ]] || fail "overlap reason: $reason"
reason=$(hop_range_free 24000 24999) && fail 'node port not reported'
[[ $reason == '已有节点使用端口 24000' ]] || fail "port reason: $reason"
for value in 20000 20999-20000 80-90 20000-70000 a-b ''; do if hop_parse "$value" >/dev/null; then fail "parsed $value"; fi; done
[[ $(hop_parse 40000-40999) == '40000 40999' && $(hop_parse 40000:40999) == '40000 40999' ]] || fail 'parse'
echo 'PASS ports inside hop ranges are taken; the default range is the first free block of 1000 from 20000, skipping nodes, ranges and UDP listeners'

# Redirect rules, iptables: each enabled node with a range gets one rule per family.
cp "$STATE" "$work/state"
hop_sync "$work/state" || fail 'sync'
for family in ipv4 ipv6; do
    grep -Fxq -- "$(hop_rule 20000:20999 24000)" "$work/nat-$family" && grep -Fxq -- "$(hop_rule 21000:21999 24001)" "$work/nat-$family" || fail "rules $family"
    [[ $(hop_rules "$family") == 2 ]] && grep -Fxq -- "$docker_rule" "$work/nat-$family" || fail "rule count / Docker rule $family"
done
[[ $(head -n 1 "$DATA/port-hopping") == iptables ]] || fail record
echo 'PASS enabling port hopping adds an srm-hop REDIRECT rule per node to nat PREROUTING (IPv4 and IPv6), only for packets addressed here'

: > "$work/nat-calls"
hop_sync "$work/state"
[[ ! -s $work/nat-calls ]] || fail 'repeated sync changed rules'
echo 'PASS repeated sync changes nothing'

jq '.nodes[0].enabled=false' "$work/state" > "$work/s1"; hop_sync "$work/s1"
[[ $(hop_rules ipv4) == 1 && $(hop_rules ipv6) == 1 ]] && ! grep -q -- '--to-ports 24000$' "$work/nat-ipv4" || fail 'disabled node rule remains'
jq 'del(.nodes[1].hop)' "$work/s1" > "$work/s2"; hop_sync "$work/s2"
[[ $(hop_rules ipv4) == 0 && $(hop_rules ipv6) == 0 && ! -e $DATA/port-hopping ]] || fail 'turning hopping off left rules or the record'
cmp -s "$work/nat-ipv4" "$work/nat-original" || fail 'nat table not back to the original'
echo 'PASS disabling the node or turning hopping off removes its rule; the other rules stay'

jq '.nodes[0].hop={start:40000,end:40999}' "$work/state" > "$work/s3"; hop_sync "$work/s3"
grep -Fxq -- "$(hop_rule 40000:40999 24000)" "$work/nat-ipv4" && ! grep -q -- '--dport 20000:20999 ' "$work/nat-ipv4" || fail 'changed range'
jq 'del(.nodes[0])' "$work/s3" > "$work/s4"; hop_sync "$work/s4"
[[ $(hop_rules ipv4) == 1 ]] && ! grep -q -- '--to-ports 24000$' "$work/nat-ipv4" || fail 'deleted node rule remains'
mkdir -p "$DATA/firewall"
firewall_clear || fail 'uninstall'
[[ $(hop_rules ipv4) == 0 && $(hop_rules ipv6) == 0 && ! -e $DATA/port-hopping ]] || fail 'uninstall left rules'
cmp -s "$work/nat-ipv4" "$work/nat-original" || fail 'uninstall changed other nat rules'
echo 'PASS changing the range replaces the rule; deleting the node and uninstalling remove it'

: > "$work/nat-calls"
hop_sync "$work/s2"; firewall_clear
[[ ! -s $work/nat-calls && ! -e $work/nft-calls ]] || fail 'a system without port hopping was touched'
echo 'PASS a server that never used port hopping is not touched'

# nftables when there is no iptables: one table replaced in a single transaction.
nat_backend=nft
hop_sync "$work/state" || fail 'nft sync'
grep -q '^add table inet srm_hop$' "$work/nft-ruleset" && grep -q '^delete table inet srm_hop$' "$work/nft-ruleset" || fail 'not one transaction'
grep -q 'type nat hook prerouting priority -100; policy accept;' "$work/nft-ruleset" || fail 'chain'
grep -Fq 'fib daddr type local udp dport 20000-20999 counter redirect to :24000 comment "srm-hop"' "$work/nft-ruleset" &&
    grep -Fq 'fib daddr type local udp dport 21000-21999 counter redirect to :24001 comment "srm-hop"' "$work/nft-ruleset" || { cat "$work/nft-ruleset"; fail 'nft rules'; }
[[ $(head -n 1 "$DATA/port-hopping") == nft ]] || fail 'nft record'
hop_sync "$work/s2"
[[ ! -e $work/nft-table && ! -e $DATA/port-hopping ]] || fail 'nft table not deleted'
echo 'PASS without iptables the rules go into one nftables table inet srm_hop (comment srm-hop) replaced atomically, deleted when off'

# The backend changed since (iptables installed): the old backend's rules go.
hop_sync "$work/state"
nat_backend=iptables
hop_sync "$work/state"
[[ ! -e $work/nft-table && $(hop_rules ipv4) == 2 && $(head -n 1 "$DATA/port-hopping") == iptables ]] || fail 'backend switch'
firewall_clear
echo 'PASS rules of a previous backend are removed when the backend changes'

# Node management through the transaction (apply_state stands in: validation, the
# new generation and the redirect rules).
apply_state() { validate_state "$1" && cp "$1" "$STATE" && hop_sync "$STATE"; }
node_change 1000000000000003 hop off > /dev/null 2>&1 || fail 'off on a node without hopping'
node_change 1000000000000003 hop 40000-40999 > /dev/null || fail 'range'
node 1000000000000003 | jq -e '.hop == {start:40000,end:40999}' >/dev/null || fail 'range saved'
grep -Fxq -- "$(hop_rule 40000:40999 24002)" "$work/nat-ipv4" || fail 'range rule'
if node_change 1000000000000003 hop 20500-21500 2> "$work/err"; then fail 'overlap accepted'; fi
grep -q '和节点「hy2 跳」的端口跳跃范围重叠' "$work/err" || fail 'overlap message'
if node_change 1000000000000004 hop auto 2> "$work/err"; then fail 'hop on TUIC'; fi
grep -q '不支持端口跳跃' "$work/err" || fail 'unsupported message'
if node_change 1000000000000003 port 20500 2>/dev/null; then fail 'node port moved into a range'; fi
node_change 1000000000000003 hop auto > /dev/null
node 1000000000000003 | jq -e '.hop == {start:22000,end:22999}' >/dev/null || fail 'auto range'
node_change 1000000000000003 hop off > /dev/null
node 1000000000000003 | jq -e 'has("hop")|not' >/dev/null && ! grep -q -- '--to-ports 24002$' "$work/nat-ipv4" || fail 'off'
node_change 1000000000000001 toggle > /dev/null
! grep -q -- '--to-ports 24000$' "$work/nat-ipv4" || fail 'disabled node keeps its rule'
node_change 1000000000000001 toggle > /dev/null
grep -Fxq -- "$(hop_rule 20000:20999 24000)" "$work/nat-ipv4" || fail 'enabled node gets its rule back'
node_change 1000000000000001 delete > /dev/null
! grep -q -- '--to-ports 24000$' "$work/nat-ipv4" || fail 'deleted node keeps its rule'
echo 'PASS srm node ID hop off|auto|range turns hopping on and off; stop and delete remove the rule, enabling puts it back'

# The menu: deploy asks one port hopping question (Enter = off), then the port.
selfsigned_create() { REPLY=$(jq -nc --arg p "$pin" --arg k "$pubkey" '{cert_dir:"/self",cert_sha256:$p,pubkey_sha256:$k}'); }
questions() { perl -CSD -Mutf8 -ne 'while (/([^：\n]*? \[[^\]]*\]：)/g) { print "$1\n" }' "$1" | grep -vE '^请选择 ' || true; }
node_add self hysteria2 <<< $'2\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu deploy with hopping'; }
last=$(jq -c '.nodes[-1]' "$STATE")
jq -e '.type == "hysteria2" and .hop == {start:20000,end:20999} and (.port < 20000 or .port > 20999)' <<< "$last" >/dev/null || { cat "$work/out"; fail "deployed: $last"; }
[[ $(questions "$work/out" | tr '\n' '|') == '端口跳跃 [1]：|端口（1–65535，回车随机选一个空闲端口） [随机]：|' ]] || fail "questions: $(questions "$work/out")"
grep -qF '  2. 开启：客户端在 20000–20999 之间换端口，服务器转到节点端口' "$work/out" || fail 'default range offered'
grep -qF "放行入站 UDP $(jq .port <<< "$last")，以及端口跳跃的 UDP 20000-20999" "$work/out" || fail 'cloud security group range'
grep -q '&mport=20000-20999#' "$work/out" && grep -q '^说明：端口跳跃：服务器把 UDP 20000–20999' "$work/out" || fail 'summary link / note'
node_add self hysteria2 <<< $'\n\n' > "$work/out" 2>&1 || fail 'menu deploy without hopping'
jq -e '.nodes[-1]|has("hop")|not' "$STATE" >/dev/null || fail 'Enter turned hopping on'
node_add self hysteria2 <<< $'3\n20000-20100\n45000-45999\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'typed range'; }
grep -q '这段端口不能用：已有节点使用端口' "$work/out" || grep -q '这段端口不能用：和节点' "$work/out" || fail 'taken typed range accepted'
jq -e '.nodes[-1].hop == {start:45000,end:45999}' "$STATE" >/dev/null || fail 'typed range'
node_add self hysteria2 --hop 46000-46999 --yes > /dev/null 2>&1 || fail '--hop range --yes'
jq -e '.nodes[-1].hop == {start:46000,end:46999}' "$STATE" >/dev/null || fail '--hop range'
node_add self hysteria2 --hop auto --yes --json > "$work/json" 2>/dev/null || fail '--hop auto --json'
jq -e '.port_hopping == {start:22000,end:22999} and (.share_link|endswith("&mport=22000-22999#hysteria2-JP-5"))' "$work/json" >/dev/null || { cat "$work/json"; fail 'json'; }
count=$(jq '.nodes|length' "$STATE")
if node_add self vless --hop auto --yes > /dev/null 2>&1; then fail '--hop on VLESS Reality'; fi
if node_add self hysteria2 --hop 45500-45600 --yes > /dev/null 2>&1; then fail 'overlapping --hop'; fi
if node_add self hysteria2 --hop 1-2 --yes > /dev/null 2>&1; then fail 'bad --hop'; fi
[[ $(jq '.nodes|length' "$STATE") == "$count" ]] || fail 'a refused deploy changed nodes'
# docs/menu-preview.txt shows the question (its example uses 20000–20999 as well).
node_add self hysteria2 <<< $'1\n\n' > "$work/out" 2>&1 || fail 'menu deploy, 1 = off'
jq -e '.nodes[-1]|has("hop")|not' "$STATE" >/dev/null || fail '1 turned hopping on'
while IFS= read -r line; do
    grep -qxF -- "$line" docs/menu-preview.txt || fail "docs/menu-preview.txt is out of date: $line"
done < <(grep -E '^端口跳跃（|^  [123]\. ' "$work/out" | sed -E 's/[0-9]{5}–[0-9]{5}/20000–20999/')
# A port typed into the range picked just before is refused with the reason, then asked again.
node_add self hysteria2 <<< $'2\n23500\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'port inside the picked range'; }
grep -qF '端口 23500 在端口跳跃范围 23000–23999 里，换一个（或回车随机）。' "$work/out" || { cat "$work/out"; fail 'port in range message'; }
jq -e '.nodes[-1]|.hop == {start:23000,end:23999} and .port != 23500' "$STATE" >/dev/null || fail 'port in range deployed'
echo 'PASS deploying asks one question (Enter or 1 = off, 2 = the default range, 3 = typed and checked); --hop off|auto|range; the summary and JSON show the range; docs/menu-preview.txt shows it'

# Node management menu: the node line shows the range, and the extra item turns it off.
id=$(jq -r '.nodes[]|select(.hop.start == 22000)|.id' "$STATE")
index=$(jq --arg id "$id" '[.nodes[].id]|index($id) + 1' "$STATE")
node_menu <<< "$index"$'\n10\n1' > "$work/out" 2>&1 || { cat "$work/out"; fail 'node menu'; }
grep -qF "端口 $(jq .port <<< "$(node "$id")")（跳跃 22000–22999）" "$work/out" && grep -q '^10.端口跳跃（运营商限制 UDP 时用）' "$work/out" || { cat "$work/out"; fail 'node menu lines'; }
node "$id" | jq -e 'has("hop")|not' >/dev/null && grep -q '端口跳跃已关闭' "$work/out" || fail 'menu off'
node_menu <<< "$index"$'\n10\n2' > "$work/out" 2>&1 || fail 'node menu on'
node "$id" | jq -e '.hop == {start:22000,end:22999}' >/dev/null && grep -q '云服务器安全组也要放行入站 UDP 22000-22999' "$work/out" && grep -q 'mport=22000-22999' "$work/out" || { cat "$work/out"; fail 'menu on'; }
node_menu <<< "$(jq '[.nodes[].type]|index("tuic") + 1' "$STATE")"$'\n10' > "$work/out" 2>&1 || true
grep -q '^10\.' "$work/out" && fail 'a TUIC node shows item 10'
# On: the default range is the current one, so only off and a typed range are offered.
node_menu <<< "$index"$'\n10\n0' > "$work/out" 2>&1 || true
grep -qx '  3. 改为自己填的端口范围' "$work/out" && ! grep -Eq '^  2\. (开启|改为)' "$work/out" || { cat "$work/out"; fail 'menu of a node with hopping'; }
node_menu <<< "$index"$'\n10\n3\n22000-22999' > "$work/out" 2>&1 || true
grep -q '已经是这个范围，无需修改。' "$work/out" || fail 'same range applied again'
# Off: docs/menu-preview.txt shows this screen.
plain=$(jq '[.nodes[].id]|index("1000000000000003") + 1' "$STATE")
node_menu <<< "$plain"$'\n10\n0' > "$work/out" 2>&1 || true
while IFS= read -r line; do
    grep -qxF -- "$line" docs/menu-preview.txt || fail "docs/menu-preview.txt is out of date: $line"
done < <(grep -E '^10\.|^端口跳跃：|^  [0-3]\. (关闭|开启|返回)' "$work/out" | sed -E 's/[0-9]{5}–[0-9]{5}/20000–20999/')
grep -q '^  2\. 开启，范围' "$work/out" || fail 'off menu offers the default range'
[[ ! -e $work/network-calls ]] || { cat "$work/network-calls"; fail 'network access'; }
echo 'PASS node management lists the range and turns hopping off and on from item 10, showing the new client configuration'
