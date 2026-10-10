#!/usr/bin/env bash
# Snell v6 / v5 behind ShadowTLS v3: client lines (Surge, Clash Meta, sing-box),
# the sing-box front end, snell-server configuration in the generation, deployment,
# and the helper service lifecycle with systemctl replaced by a recorder.
# No core or root needed; tests/snell-traffic.sh runs real servers and clients and
# tests/install-live.sh the real systemd units.
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
mkdir -p "$SRM_ROOT" "$DATA/current" "$DATA/generations"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"

psk=0123456789abcdef0123456789abcdef
pw=fedcba9876543210fedcba9876543210
jq -n --arg psk "$psk" --arg pw "$pw" '
  def node($id; $name; $port; $lp): {id:$id,name:$name,type:"snell",enabled:true,host:"192.0.2.1",port:$port,sni:"www.jetbrains.com",
    psk:$psk,shadowtls_password:$pw,local_port:$lp};
  {schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
   node("5000000000000001"; "snell v6"; 20001; 30001) + {snell_version:6,snell_mode:"default"},
   node("5000000000000002"; "snell-u"; 20002; 30002) + {snell_version:6,snell_mode:"unshaped"},
   node("5000000000000003"; "snell-5"; 20003; 30003) + {snell_version:5}
  ]}' > "$work/state.json"
validate_state "$work/state.json" || fail 'fixture state rejected'
node() { node_json "$work/state.json" "$1"; }

# Surge lines: manual.nssurge.com/policies/snell.html (version explicit, mode only
# for v6) and tls.html#shadow-tls (shadow-tls-version defaults to 2).
[[ $(node 5000000000000001 | surge_proxy) == "snell v6 = snell, 192.0.2.1, 20001, psk=$psk, version=6, mode=default, reuse=true, shadow-tls-password=$pw, shadow-tls-sni=www.jetbrains.com, shadow-tls-version=3" ]] ||
    fail "surge v6: $(node 5000000000000001 | surge_proxy)"
[[ $(node 5000000000000002 | surge_proxy) == "snell-u = snell, 192.0.2.1, 20002, psk=$psk, version=6, mode=unshaped, reuse=true, shadow-tls-password=$pw, shadow-tls-sni=www.jetbrains.com, shadow-tls-version=3" ]] ||
    fail "surge v6 unshaped: $(node 5000000000000002 | surge_proxy)"
[[ $(node 5000000000000003 | surge_proxy) == "snell-5 = snell, 192.0.2.1, 20003, psk=$psk, version=5, reuse=true, shadow-tls-password=$pw, shadow-tls-sni=www.jetbrains.com, shadow-tls-version=3" ]] ||
    fail "surge v5: $(node 5000000000000003 | surge_proxy)"
# Setting mode below v6 is a Surge profile error.
node 5000000000000003 | surge_proxy | grep -q 'mode=' && fail 'v5 line carries mode'
# Without a share link format, the "link" is the Surge line.
[[ $(node 5000000000000001 | share_uri) == "$(node 5000000000000001 | surge_proxy)" ]] || fail 'share link is not the Surge line'
# Surge for iOS takes no pasted line: its new-proxy form is filled field by field.
[[ $(node 5000000000000001 | surge_proxy | surge_form) == "  名称：snell v6
  类型：snell
  服务器：192.0.2.1
  端口：20001
  PSK：$psk
  版本（version）：6
  模式（mode）：default
  连接复用（reuse）：开
  Shadow TLS 密码（shadow-tls-password）：$pw
  Shadow TLS SNI（shadow-tls-sni）：www.jetbrains.com
  Shadow TLS 版本（shadow-tls-version）：3" ]] || fail "surge v6 fields: $(node 5000000000000001 | surge_proxy | surge_form)"
if node 5000000000000003 | surge_proxy | surge_form | grep -q '模式'; then fail 'v5 fields carry mode'; fi
echo 'PASS Surge lines for Snell v6 (default / unshaped) and v5 with ShadowTLS v3, and the same as form fields for Surge for iOS'

# mihomo: v5 with ShadowTLS in obfs-opts; no Snell v6 client.
[[ $(node 5000000000000003 | clash_proxy) == "- {\"name\":\"snell-5\",\"server\":\"192.0.2.1\",\"port\":20003,\"type\":\"snell\",\"psk\":\"$psk\",\"version\":5,\"udp\":true,\"obfs-opts\":{\"mode\":\"shadow-tls\",\"host\":\"www.jetbrains.com\",\"password\":\"$pw\",\"version\":3}}" ]] ||
    fail "clash v5: $(node 5000000000000003 | clash_proxy)"
[[ -z $(node 5000000000000001 | clash_proxy) ]] || fail 'clash snippet for v6'
echo 'PASS Clash Meta snippet only for v5, with ShadowTLS v3 in obfs-opts'

# sing-box client: snell (v6, or v4 against a v5 server) dialing through shadowtls.
node 5000000000000001 | client_outbound | jq -e --arg psk "$psk" --arg pw "$pw" '. == [
  {tag:"snell v6",server:"192.0.2.1",server_port:20001,type:"snell",version:6,psk:$psk,reuse:true,detour:"snell v6-shadowtls",mode:"default"},
  {type:"shadowtls",tag:"snell v6-shadowtls",server:"192.0.2.1",server_port:20001,version:3,password:$pw,tls:{enabled:true,server_name:"www.jetbrains.com"}}]' >/dev/null ||
    fail "sing-box v6: $(node 5000000000000001 | client_outbound)"
node 5000000000000003 | client_outbound | jq -e '.[0].version == 4 and (.[0]|has("mode")|not) and .[1].type == "shadowtls"' >/dev/null || fail 'sing-box v5 client'
echo 'PASS sing-box client outbounds: snell v6 / v4 through a shadowtls outbound'

# Server: shadowtls on the node port, detour to a loopback direct inbound whose
# destination override points at snell-server.
render_config "$work/state.json" > "$work/config.json"
jq -e --arg pw "$pw" '
  .inbounds[0] == {tag:"5000000000000001",listen:"::",listen_port:20001,type:"shadowtls",version:3,
    users:[{name:"5000000000000001",password:$pw}],handshake:{server:"www.jetbrains.com",server_port:443},strict_mode:true,detour:"5000000000000001-snell"} and
  .inbounds[1] == {type:"direct",tag:"5000000000000001-snell",listen:"127.0.0.1",network:"tcp",override_address:"127.0.0.1",override_port:30001} and
  (.inbounds|length) == 6' "$work/config.json" >/dev/null || fail 'rendered front end'
# Firewall and health checks see only the TCP node port.
[[ $(jq -r ".nodes[]|.port as \$p|($(proto_jq_transports))[]|\"\(\$p)/\(.)\"" "$work/state.json" | tr '\n' ' ') == '20001/tcp 20002/tcp 20003/tcp ' ]] || fail 'transports'
echo 'PASS sing-box shadowtls inbound forwards through a loopback direct inbound to snell-server'

# Validation: versions, modes, keys, local ports.
for bad in '.nodes[0].snell_version=4' '.nodes[0].snell_mode="unsafe-raw"' '.nodes[0]|=del(.snell_mode)' '.nodes[2].snell_mode="default"' \
  '.nodes[0].psk="short"' '.nodes[0].shadowtls_password="x"' '.nodes[0]|=del(.sni)' '.nodes[0].local_port=0' '.nodes[0].local_port="30001"' \
  '.nodes[0].local_port=20002' '.nodes[1].local_port=30001'; do
    jq "$bad" "$work/state.json" > "$work/bad.json"
    if validate_state "$work/bad.json" 2>/dev/null; then fail "accepted $bad"; fi
done
# A loopback port counts as taken for new node ports.
cp "$work/state.json" "$STATE"
ss() { return 0; }
if port_free 30002; then fail 'port_free ignored a loopback port'; fi
port_free 30009 || fail 'free port rejected'
echo 'PASS validation rejects bad versions, modes, keys and overlapping loopback ports'

# snell-server configuration in the generation: the format of `snell-server --wizard`
# of each version, listening on loopback only, plus a link to that version's binary.
mkdir -p "$SRM_ROOT/snell/v6" "$SRM_ROOT/snell/v5"
printf '#!/bin/sh\n' > "$SRM_ROOT/snell/v6/snell-server"; printf '#!/bin/sh\n' > "$SRM_ROOT/snell/v5/snell-server"
chmod 755 "$SRM_ROOT/snell/v6/snell-server" "$SRM_ROOT/snell/v5/snell-server"
chgrp() { :; }
mkdir "$work/gen"
sidecar_render "$work/state.json" "$work/gen" || fail 'sidecar render'
[[ $(cat "$work/gen/sidecar/5000000000000001/snell.conf") == "[snell-server]
listen = 127.0.0.1:30001
psk = $psk
mode = default
dns-ip-preference = default" ]] || fail "v6 config: $(cat "$work/gen/sidecar/5000000000000001/snell.conf")"
grep -qx 'mode = unshaped' "$work/gen/sidecar/5000000000000002/snell.conf" || fail 'unshaped config'
[[ $(cat "$work/gen/sidecar/5000000000000003/snell.conf") == "[snell-server]
listen = 127.0.0.1:30003
psk = $psk
ipv6 = false" ]] || fail "v5 config: $(cat "$work/gen/sidecar/5000000000000003/snell.conf")"
[[ $(readlink "$work/gen/sidecar/5000000000000001/snell-server") == "$SRM_ROOT/snell/v6/snell-server" &&
   $(readlink "$work/gen/sidecar/5000000000000003/snell-server") == "$SRM_ROOT/snell/v5/snell-server" ]] || fail 'binary links'
perm=$(stat -c '%a' "$work/gen/sidecar/5000000000000001/snell.conf" 2>/dev/null || stat -f '%Lp' "$work/gen/sidecar/5000000000000001/snell.conf")
[[ $perm == 640 ]] || fail "config mode $perm"
# Disabled nodes get no files; a missing binary fails before anything switches.
jq '.nodes[1].enabled=false' "$work/state.json" > "$work/off.json"
mkdir "$work/gen2"; sidecar_render "$work/off.json" "$work/gen2" || fail 'render with a disabled node'
[[ ! -e $work/gen2/sidecar/5000000000000002 ]] || fail 'files for a disabled node'
rm "$SRM_ROOT/snell/v5/snell-server"; mkdir "$work/gen3"
if sidecar_render "$work/state.json" "$work/gen3" 2> "$work/err"; then fail 'render without the v5 binary'; fi
grep -q '缺少 Snell v5' "$work/err" || fail 'missing binary message'
printf '#!/bin/sh\n' > "$SRM_ROOT/snell/v5/snell-server"; chmod 755 "$SRM_ROOT/snell/v5/snell-server"
echo 'PASS snell-server configuration per version in the generation, loopback only, 640, enabled nodes only'

# A download whose SHA-256 differs from the pinned one installs nothing, even a
# well-formed zip whose snell-server would pass the version check.
printf '#!/bin/sh\necho "snell-server v6.0.0 (test)"\n' > "$work/fake-snell"
python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").write(sys.argv[2], "snell-server")' "$work/fake.zip" "$work/fake-snell"
(
    fetch() { cp "$work/fake.zip" "$2"; }
    if snell_download 6 "$work/snell-bad" 2> "$work/err"; then fail 'unverified download accepted'; fi
    grep -q 'Snell 6.0.0rc2 下载、SHA256 校验或试运行失败' "$work/err" && [[ ! -e $work/snell-bad ]] || fail 'failed download left a binary'
    if snell_download 4 "$work/snell-bad" 2>/dev/null; then fail 'Snell v4 download accepted'; fi
) || exit 1
echo 'PASS snell-server downloads must match the pinned SHA-256'

# Helper services: one unit per enabled node; status, logs and sync cover them.
[[ $(sidecar_units "$work/off.json" | tr '\n' ' ') == 'srm-snell@5000000000000001.service srm-snell@5000000000000003.service ' ]] || fail 'enabled units'
[[ $(sidecar_units "$work/off.json" true | wc -l | tr -d ' ') == 3 ]] || fail 'all units'
known=''
systemctl() {
    printf '%s\n' "$*" >> "$work/systemctl"
    case $1 in list-units) printf '  %s loaded active running srm Snell\n' $known;; is-active) [[ ${2:-} != --quiet ]] || return 0;; esac
}
known='srm-snell@5000000000000002.service srm-snell@aaaaaaaaaaaaaaaa.service'
: > "$work/systemctl"
sidecars_sync "$work/off.json" || fail 'sync'
grep -qx 'disable --now srm-snell@5000000000000002.service' "$work/systemctl" &&
    grep -qx 'disable --now srm-snell@aaaaaaaaaaaaaaaa.service' "$work/systemctl" &&
    grep -qx 'restart srm-snell@5000000000000001.service' "$work/systemctl" &&
    grep -qx 'enable srm-snell@5000000000000003.service' "$work/systemctl" || { cat "$work/systemctl"; fail 'sync actions'; }
if grep -q 'restart srm-snell@5000000000000002' "$work/systemctl"; then fail 'disabled node restarted'; fi
: > "$work/systemctl"
sidecars_sync || fail 'sync without a state'
[[ $(grep -c '^disable --now' "$work/systemctl") == 2 ]] && ! grep -q '^restart' "$work/systemctl" || { cat "$work/systemctl"; fail 'stop all'; }
journalctl() { printf '%s\n' "$*" > "$work/journal"; }
cp "$work/off.json" "$STATE"
show_logs
[[ $(cat "$work/journal") == "-u srm.service -u srm-snell@5000000000000001.service -u srm-snell@5000000000000002.service -u srm-snell@5000000000000003.service -n 50 --no-pager" ]] || fail "logs: $(cat "$work/journal")"
: > "$work/systemctl"
show_status > /dev/null
grep -q '^--no-pager --full status srm.service srm-snell@5000000000000001.service srm-snell@5000000000000002.service srm-snell@5000000000000003.service$' "$work/systemctl" || { cat "$work/systemctl"; fail 'status'; }
echo 'PASS helper units follow the enabled nodes; logs and status include every Snell node'

# Health: sing-box ports and each helper's loopback port must listen.
listening='20001 20003 30001 30003'
ss() { local filter="$*"; [[ " $listening " != *" ${filter##*:} "* ]] || printf 'LISTEN\n'; }
sleep() { :; }
service_healthy "$work/off.json" || fail 'healthy'
listening='20001 20003 30001'
if service_healthy "$work/off.json"; then fail 'healthy without the v5 snell-server port'; fi
listening='20001 20003 30001 30003'
systemctl() { case $1 in is-active) [[ $3 != srm-snell@5000000000000003.service ]];; esac; }
if service_healthy "$work/off.json"; then fail 'healthy with a stopped snell unit'; fi
unset -f sleep
echo 'PASS health check covers each snell-server unit and its loopback port'

# Deployment: defaults (v6, default mode, first handshake target), options and menu.
printf '#!/bin/sh\nexit 0\n' > "$work/core"; chmod 755 "$work/core"
CORE=$work/core
ensure_dependencies() { return 0; }
sysctl() { return 1; }
ss() { return 0; }
# Every domain passes except example.com; ties keep the list order (the first one).
reality_target_check() { printf '%s\n' "$1" >> "$work/checked"; [[ $1 != example.com ]]; }
snell_install() { printf '%s\n' "$1" >> "$work/installed"; }
apply_state() { validate_state "$1" && cp "$1" "$STATE"; }
last() { jq -c '.nodes[-1]' "$STATE"; }
jq '.nodes=[]' "$work/state.json" > "$STATE"
node_add self snell --host 192.0.2.1 --port 20010 --yes > "$work/out" 2>&1 || { cat "$work/out"; fail 'deploy defaults'; }
last | jq -e '.snell_version==6 and .snell_mode=="default" and .sni=="www.jetbrains.com" and .port==20010 and
  (.psk|test("^[a-f0-9]{32}$")) and (.shadowtls_password|test("^[a-f0-9]{32}$")) and .psk != .shadowtls_password and
  .local_port >= 10000 and .local_port < 32768 and .local_port != 20010' >/dev/null || { last; fail 'default fields'; }
grep -q '= snell, 192.0.2.1, 20010, psk=' "$work/out" && grep -q 'Clash Meta (mihomo) 不支持 Snell v6' "$work/out" &&
    grep -q '端口：20010/TCP ' "$work/out" && grep -q '── Surge：手机版新建代理后按下面逐项填写' "$work/out" &&
    grep -q '^  Shadow TLS SNI（shadow-tls-sni）：www.jetbrains.com$' "$work/out" || { cat "$work/out"; fail 'deploy output'; }
if grep -q '只走 UDP' "$work/out"; then fail 'UDP note for Snell'; fi
# Shadowrocket and v2rayN cannot import the Surge line: no link, QR code or their sections.
if grep -qE '── (分享链接|Shadowrocket|v2rayN)' "$work/out"; then cat "$work/out"; fail 'link clients for Snell'; fi
[[ $(cat "$work/installed") == 6 && $(wc -l < "$work/checked" | tr -d ' ') == $(wc -w <<< "$REALITY_TARGETS" | tr -d ' ') ]] || fail 'install / target check'
node_add self snell --host 192.0.2.1 --proto-mode unshaped --sni www.example.org --yes > /dev/null 2>&1 || fail 'deploy unshaped'
last | jq -e '.snell_version==6 and .snell_mode=="unshaped" and .sni=="www.example.org"' >/dev/null || fail 'unshaped fields'
node_add self snell --host 192.0.2.1 --proto-version 5 --yes > /dev/null 2>&1 || fail 'deploy v5'
last | jq -e '.snell_version==5 and (has("snell_mode")|not)' >/dev/null || fail 'v5 fields'
[[ $(tail -n 1 "$work/installed") == 5 ]] || fail 'v5 binary installed'
# Quick deploy (3): one question for version and mode, then the port; that makes two,
# so the name takes its default. The handshake target is picked automatically.
detect_public_ip() { PUBLIC_IP=192.0.2.1; }
node_add self <<< $'3\n3\n\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu deploy'; }
last | jq -e '.snell_version==5 and .sni=="www.jetbrains.com" and .host=="192.0.2.1"' >/dev/null || fail 'menu v5 fields'
grep -q '1. v6 · default 模式（推荐' "$work/out" && grep -q 'Snell 版本 \[1\]' "$work/out" || { cat "$work/out"; fail 'menu text'; }
if grep -q '节点名称' "$work/out"; then fail 'a third question'; fi
node_add self <<< $'3\n2\n\n\n' > /dev/null 2>&1 || fail 'menu deploy unshaped'
last | jq -e '.snell_version==6 and .snell_mode=="unshaped" and .sni=="www.jetbrains.com"' >/dev/null || fail 'menu v6 unshaped fields'
before=$(sha256 "$STATE")
for bad in 'snell --proto-version 4' 'snell --proto-mode unsafe-raw' 'snell --proto-version 5 --proto-mode default' \
  'snell --sni example.com' 'vless --proto-version 6' 'anytls --sni a.example.com --proto-mode default'; do
    # shellcheck disable=SC2086 # split the argument list
    if node_add self $bad --host 192.0.2.1 --yes > "$work/out" 2>&1; then fail "deploy accepted $bad"; fi
done
grep -q -- '--proto-version、--proto-mode 不适用于 AnyTLS' "$work/out" || { cat "$work/out"; fail 'option message'; }
[[ $(sha256 "$STATE") == "$before" ]] || fail 'rejected deploys changed state'
echo 'PASS Snell deploys v6 default by default, v6 unshaped or v5 by option or menu; bad options change nothing'

# Credentials rotate; the target switches through the shared handshake list.
old=$(last); id=$(jq -r .id <<< "$old")
node_change "$id" rotate > /dev/null || fail rotate
jq -e -n --argjson a "$old" --argjson b "$(last)" '($a|del(.psk,.shadowtls_password)) == ($b|del(.psk,.shadowtls_password)) and
  $a.psk != $b.psk and $a.shadowtls_password != $b.shadowtls_password' >/dev/null || fail 'rotate fields'
node_change "$id" retarget custom.example.org > /dev/null || fail 'retarget to a domain outside the list that passes'
last | jq -e '.sni=="custom.example.org"' >/dev/null || fail 'retarget field'
if node_change "$id" retarget example.com 2>/dev/null; then fail 'retarget to a domain that fails the check'; fi
last | jq -e '.sni=="custom.example.org"' >/dev/null || fail 'failed retarget changed the node'
# Re-enabling refuses a loopback port another program took meanwhile.
node_change "$id" toggle > /dev/null || fail 'disable'
lp=$(last | jq -r .local_port)
ss() { local filter="$*"; [[ ${filter##*:} != "$lp" ]] || printf 'LISTEN\n'; }
before=$(sha256 "$STATE")
if node_change "$id" toggle 2> "$work/err"; then fail 'enabled with its loopback port taken'; fi
grep -q "本机端口 $lp 已被其他程序占用" "$work/err" && [[ $(sha256 "$STATE") == "$before" ]] || fail 'taken loopback port message'
ss() { return 0; }
node_change "$id" toggle > /dev/null || fail 're-enable'
# The command line takes 6 or 5, not menu numbers.
if node_add self snell --host 192.0.2.1 --proto-version 2 --yes > /dev/null 2>&1; then fail '--proto-version 2 accepted'; fi
if node_add self snell --host 192.0.2.1 --proto-mode 2 --yes > /dev/null 2>&1; then fail '--proto-mode 2 accepted'; fi
echo 'PASS rotation renews PSK and ShadowTLS password; target switches within the vetted list; re-enabling checks the loopback port'

# Pages: the client page explains the link, Clash Meta support and routing.
export_node "$id" clients > "$work/clients" || fail 'clients page'
grep -q '"type": "shadowtls"' "$work/clients" && grep -q '= snell, ' "$work/clients" &&
    grep -q '说明：Snell 没有通用的分享链接' "$work/clients" || { cat "$work/clients"; fail 'clients page content'; }
if grep -q '── Clash Meta' "$work/clients"; then fail 'Clash Meta section for Snell v6'; fi
export_node "$(jq -r '.nodes[]|select(.snell_version==5)|.id' "$STATE" | head -n 1)" clients > "$work/clients" || fail 'v5 clients page'
grep -q '"obfs-opts"' "$work/clients" && grep -q 'QUIC 流量会回落到 TCP' "$work/clients" || { cat "$work/clients"; fail 'v5 clients page'; }
export_node "$id" details > "$work/details" || fail details
if grep -qE '"(psk|shadowtls_password)"' "$work/details"; then fail 'details show secrets'; fi
routing_show > "$work/routing" || fail 'routing show'
grep -q '流量由独立服务直接发出，不经过分流规则' "$work/routing" || fail 'routing note'
echo 'PASS client page, hidden secrets and the routing note for Snell nodes'

# The real configuration transaction: helper files land in the new generation, the
# snell-server units restart before sing-box, and a failed health check switches
# back and restores the old generation's helpers.
unset -f apply_state
source lib/system.sh
# BSD mv has no -T; the real atomic switch is covered by tests/install-live.sh.
switch_generation() { rm -f "$DATA/current" && ln -s "$1" "$DATA/current"; }
firewall_sync() { return 0; }
# The unit lives in /etc/systemd/system; tests/install-live.sh writes the real one.
service_unit_write() { return 0; }
# The two-node configuration never becomes healthy.
service_healthy() { [[ $(jq '[.nodes[]|select(.enabled)]|length' "$1") != 2 ]]; }
# Units that were started stay known to systemd until disabled.
systemctl() {
    printf '%s\n' "$*" >> "$work/systemctl"
    case $1 in
      is-active) return 0;;
      restart) [[ $2 == srm.service ]] || printf '%s\n' "$2" >> "$work/known";;
      disable) grep -vFx "$3" "$work/known" > "$work/known.new" || true; mv "$work/known.new" "$work/known";;
      list-units) sort -u "$work/known" | sed 's/^/  /; s/$/ loaded active running x/';;
    esac
}
: > "$work/known"
rm -rf "$DATA/current" "$DATA/previous"; rm -f "$STATE"
jq '.nodes=[.nodes[0]]' "$work/state.json" > "$work/one.json"
: > "$work/systemctl"
apply_state "$work/one.json" > /dev/null || fail 'apply a Snell node'
[[ -f $DATA/current/sidecar/5000000000000001/snell.conf && -L $DATA/current/sidecar/5000000000000001/snell-server ]] || fail 'helper files in the generation'
[[ $(grep -e '^restart srm-snell@5000000000000001.service$' -e '^restart srm.service$' "$work/systemctl" | tr '\n' ' ') == \
   'restart srm-snell@5000000000000001.service restart srm.service ' ]] || { cat "$work/systemctl"; fail 'restart order'; }
first=$(readlink "$DATA/current")
# Adding the v5 node fails the health check: back to the first generation, the v5
# snell-server is stopped again and the first one restarted.
jq '.nodes=[.nodes[0],.nodes[2]]' "$work/state.json" > "$work/two.json"
: > "$work/systemctl"
if apply_state "$work/two.json" > /dev/null 2>&1; then fail 'unhealthy apply succeeded'; fi
[[ $(readlink "$DATA/current") == "$first" && ! -e $DATA/pending.json ]] || fail 'not rolled back'
grep -qx 'restart srm-snell@5000000000000003.service' "$work/systemctl" && grep -qx 'disable --now srm-snell@5000000000000003.service' "$work/systemctl" &&
    [[ $(grep -c '^restart srm-snell@5000000000000001.service$' "$work/systemctl") == 2 ]] || { cat "$work/systemctl"; fail 'old helpers not restored'; }
[[ $(sort -u "$work/known") == srm-snell@5000000000000001.service ]] || { cat "$work/known"; fail "v5 helper left running"; }
# Disabling every node stops sing-box and every snell-server.
jq '.nodes[0].enabled=false' "$work/one.json" > "$work/none.json"
: > "$work/systemctl"
apply_state "$work/none.json" > /dev/null || fail 'apply with every node disabled'
grep -qx 'stop srm.service' "$work/systemctl" && grep -qx 'disable --now srm-snell@5000000000000001.service' "$work/systemctl" || { cat "$work/systemctl"; fail 'stop all'; }
[[ ! -e $DATA/current/sidecar && ! -s $work/known ]] || fail 'helpers for a disabled node'
echo 'PASS the configuration transaction renders, restarts and rolls back snell-server together with sing-box'
