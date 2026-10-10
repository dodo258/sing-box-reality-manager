#!/usr/bin/env bash
# Moving v3 installations: sanitized v3 trees in tests/fixtures/v3/<case>/ (the
# etc-v2ray-agent directory stands for /etc/v2ray-agent, plus its systemd units and
# crontab) must give the nodes in expected.json; the menu alone completes a migration;
# a failed takeover brings the old services back; /etc/v2ray-agent never changes.
# systemctl and crontab are replaced by recorders keeping unit state in files.
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
mkdir -p "$SRM_ROOT" "$work/bin"
touch "$SRM_ROOT/.srm-owned"
# The real curl for the local traffic test; srm itself must not reach the network.
real_curl=$(command -v curl)
for tool in curl wget; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/network-calls"\nexit 1\n' "$tool" "$work" > "$work/bin/$tool"
done
printf '#!/usr/bin/env bash\ncase $1 in check) exit "$(cat %s/core-check 2>/dev/null || echo 0)";; esac\n' "$work" > "$work/core"
chmod 755 "$work/bin/"* "$work/core"
export PATH="$work/bin:$PATH"
CORE=$work/core
require_linux() { return 0; }
require_root() { return 0; }
with_lock() { "$@"; }
ensure_dependencies() { return 0; }
ss() { return 0; }
sysctl() { return 1; }
chgrp() { :; }
detect_public_ip() { PUBLIC_IP=192.0.2.10; PUBLIC_LOC=JP; }
snell_install() { printf '%s\n' "$1" >> "$work/snell-installed"; }
install_renew_timer() { touch "$work/renew-timer"; }
apply_state() { validate_state "$1" && mkdir -p "$DATA/current" && cp "$1" "$STATE"; }
# Certificates land where srm keeps them; the real activation runs in tests/install-live.sh.
activate_cert() { printf '%s %s\n' "$1" "$3" >> "$work/activated"; mkdir -p "$DATA/certs/$1/active"; cp "$2/fullchain.pem" "$2/key.pem" "$DATA/certs/$1/active/"; }
# Units live as files: $work/units/<unit>.active and .enabled.
systemctl() {
    printf '%s\n' "$*" >> "$work/systemctl.log"
    local verb=$1 now=0
    shift
    [[ ${1:-} != --quiet ]] || shift
    [[ ${1:-} != --now ]] || { now=1; shift; }
    case $verb in
      is-active) [[ -f $work/units/$1.active ]];;
      is-enabled) [[ -f $work/units/$1.enabled ]];;
      start) [[ ! -f $work/units/broken-$1 ]] && touch "$work/units/$1.active";;
      stop) rm -f "$work/units/$1.active";;
      enable) touch "$work/units/$1.enabled"; [[ $now == 0 ]] || touch "$work/units/$1.active";;
      disable) rm -f "$work/units/$1.enabled"; [[ $now == 0 ]] || rm -f "$work/units/$1.active";;
      *) return 0;;
    esac
}
crontab() {
    case $1 in
      -l) [[ -f $work/crontab ]] && cat "$work/crontab";;
      -) cat > "$work/crontab";;
    esac
}
# A test CA for domain certificates (subject differs from issuer) and self-signed ones.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj '/CN=srm test CA' \
    -keyout "$work/ca.key" -out "$work/ca.pem" >/dev/null 2>&1
make_cert() {
    local domain=$1 kind=$2 dir=$work/v3/tls
    mkdir -p "$dir"
    if [[ $kind == self ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain" \
            -keyout "$dir/$domain.key" -out "$dir/$domain.crt" >/dev/null 2>&1
    else
        openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=$domain" -keyout "$dir/$domain.key" -out "$work/req.csr" >/dev/null 2>&1
        printf 'subjectAltName=DNS:%s\n' "$domain" > "$work/ext"
        openssl x509 -req -in "$work/req.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" -CAcreateserial -days 60 -extfile "$work/ext" -out "$dir/$domain.crt" >/dev/null 2>&1
        cat "$work/ca.pem" >> "$dir/$domain.crt"
    fi
}
# A server with this fixture installed by v3 and nothing of srm yet: its units running
# and enabled, its crontab; /etc/v2ray-agent paths point at the copy.
load_fixture() {
    local fixture=tests/fixtures/v3/$1 file d kind
    rm -rf "$work/v3" "$work/units" "$work/systemd" "$DATA" "$work/systemctl.log" "$work/activated" "$work/renew-timer" "$work/snell-installed" "$work/core-check"
    mkdir -p "$work/units" "$work/systemd" "$DATA"
    touch "$DATA/.srm-owned"
    cp -R "$fixture/etc-v2ray-agent" "$work/v3"
    find "$work/v3" -name '*.json' -exec perl -pi -e "s#/etc/v2ray-agent#$work/v3#g" {} +
    if [[ -f $fixture/certs ]]; then while read -r d kind; do make_cert "$d" "$kind"; done < "$fixture/certs"; fi
    for file in "$fixture"/systemd/*.service; do
        [[ -f $file ]] || continue
        cp "$file" "$work/systemd/"; touch "$work/units/${file##*/}.active" "$work/units/${file##*/}.enabled"
    done
    perl -pe "s#/etc/v2ray-agent#$work/v3#g" "$fixture/crontab" > "$work/crontab"
    V3_ROOT=$work/v3
    V3_UNIT_DIR=$work/systemd
}
# Contents and names of every file under the v3 copy.
tree_hash() { (cd "$work/v3" && find . -type f -exec shasum -a 256 {} + | sort; find . | sort) | shasum -a 256; }
# Plan in the form of expected.json: ids, loopback ports and certificate hashes vary.
normalized() {
    jq '{nodes:[.nodes[].node|del(.id,.local_port,.cert_sha256,.pubkey_sha256)
          |if .cert_dir then .cert_dir |= (if test("/selfsigned/") then "selfsigned" else sub("^.*/certs/";"certs/") end) else . end],
         notes:([.nodes[]|select(.note)|{(.node.name):.note}]|add // {}),
         skipped:[.skipped[].label],units}' "$1"
}

# Every fixture gives exactly the expected nodes, skipped items and services.
for case in reality trio multi snell tls; do
    load_fixture "$case"
    migrate_scan "$work/plan" || fail "$case scan"
    jq --slurpfile want "tests/fixtures/v3/$case/expected.json" -e '. == ($want[0] + {notes:($want[0].notes // {})})' <(normalized "$work/plan") >/dev/null ||
        { normalized "$work/plan"; fail "$case: plan differs from expected.json"; }
done
echo 'PASS the 5 v3 samples (single Reality; Reality + AnyTLS + Hysteria2; multi-instance 30_–33_; Snell + ShadowTLS; TLS protocols) give the expected nodes'

# Details the expected files cannot show: local ports, self-signed pins, reasons.
load_fixture snell
migrate_scan "$work/plan"
jq -e '[.nodes[].node.local_port]|all(. >= 10000 and . < 32768)' "$work/plan" >/dev/null || fail 'snell loopback ports'
load_fixture trio
migrate_scan "$work/plan"
pin=$(openssl x509 -in "$work/v3/tls/hy2.dodo258.local.crt" -outform der | openssl dgst -sha256 | awk '{print $NF}')
jq -e --arg pin "$pin" '.nodes[0].node.cert_sha256 == $pin and (.nodes[0].node.pubkey_sha256|test("^[A-Za-z0-9+/]{43}=$"))' "$work/plan" >/dev/null || fail 'self-signed pins'
load_fixture multi
migrate_scan "$work/plan"
jq -e '.skipped[0].reason|test("只支持 TCP Vision")' "$work/plan" >/dev/null && jq -e '.skipped[1].reason|test("nginx")' "$work/plan" >/dev/null &&
    jq -e '.skipped[5].reason|test("旧 Xray 服务继续运行")' "$work/plan" >/dev/null || { jq .skipped "$work/plan"; fail 'skip reasons'; }
echo 'PASS Snell loopback ports stay below 32768, self-signed certificates keep their pins, and every skipped item says why'

# Ports already used by srm nodes are not taken twice; expired certificates do not move.
load_fixture trio
mkdir -p "$DATA/current"
jq -n '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[{id:"1111111111111111",name:"mine",type:"shadowsocks",enabled:true,host:"192.0.2.10",port:30443,method:"2022-blake3-aes-128-gcm",password:"AAAAAAAAAAAAAAAAAAAAAA=="}]}' > "$STATE"
migrate_scan "$work/plan"
jq -e '(.nodes|length) == 2 and any(.skipped[]; .reason|test("端口 30443 已被 srm 的节点「mine」使用"))' "$work/plan" >/dev/null || { jq . "$work/plan"; fail 'port taken'; }
rm -f "$STATE"
openssl x509 -req -in "$work/req.csr" -CA "$work/ca.pem" -CAkey "$work/ca.key" -days 0 -out "$work/v3/tls/vpn.example.com.crt" >/dev/null 2>&1
migrate_scan "$work/plan"
jq -e '(.nodes|length) == 2 and any(.skipped[]; .reason|test("已到期"))' "$work/plan" >/dev/null || { jq . "$work/plan"; fail 'expired certificate moved'; }
echo 'PASS nodes on ports srm already uses and nodes with an expired certificate are listed as not movable'

# srm migrate previews only: both lists, no change anywhere.
load_fixture multi
before=$(tree_hash)
main migrate > "$work/out" 2>&1 || { cat "$work/out"; fail 'preview exit code'; }
for want in '能迁移的节点' '1. VLESS Reality（端口 31443，07_VLESS_vision_reality_inbounds.json） · www.example.com' '说明：这个端口还有 1 个用户' \
            '不能迁移：' 'Xray vless（端口 31448）' '网站：' '订阅链接：' '停止并停用旧服务：dodo258-sing-box.service' '没有改动'; do
    grep -qF -- "$want" "$work/out" || { cat "$work/out"; fail "preview lacks: $want"; }
done
[[ ! -e $STATE && ! -e $work/systemctl.log && $(tree_hash) == "$before" && ! -e $DATA/certs ]] || fail 'preview changed something'
[[ ! -e $work/network-calls ]] || fail 'preview reached the network'
(V3_ROOT=$work/none; if main migrate > "$work/out" 2>&1; then fail 'preview without v3 exited 0'; fi) || exit 1
grep -q '没有找到旧版安装' "$work/out" || fail 'no v3 message'
echo 'PASS srm migrate lists what moves and what does not (Xray nodes, website, subscriptions) and changes nothing; without v3 it fails'

# The menu alone: a fresh srm on a v3 server offers the migration first; Enter shows
# the lists, 1 confirms; the nodes then run in srm and the menu stops offering it.
load_fixture trio
rm -f "$SRM_ROOT/.srm-owned"
setup() { touch "$SRM_ROOT/.srm-owned" "$work/setup-called"; }
before=$(tree_hash)
main <<< $'\n1\n0' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu migration exit code'; }
grep -q '发现旧版节点' "$work/out" && grep -q '1. 确认迁移' "$work/out" && grep -q '迁移完成' "$work/out" || { cat "$work/out"; fail 'menu migration text'; }
[[ -e $work/setup-called ]] || fail 'srm not installed before moving'
jq -e '(.nodes|length) == 3 and all(.nodes[]; .host == "192.0.2.10" and .enabled) and ([.nodes[].port]|sort) == [30443,30444,30445]' "$STATE" >/dev/null ||
    { cat "$work/out"; fail 'migrated state'; }
[[ ! -e $work/units/dodo258-sing-box.service.active && ! -e $work/units/dodo258-sing-box.service.enabled ]] || fail 'old service still running or enabled'
grep -q "^# srm 迁移后停用：30 1 \* \* \* /bin/bash $work/v3/install.sh RenewTLS" "$work/crontab" &&
    grep -q "^# srm 迁移后停用：35 1 .* UpdateGeo" "$work/crontab" && grep -q '^0 3 \* \* \* /usr/local/bin/backup.sh$' "$work/crontab" || { cat "$work/crontab"; fail 'crontab'; }
[[ $(cat "$work/activated") == 'vpn.example.com v3' && -e $work/renew-timer ]] || fail 'certificate handed to srm renewal'
dir=$(jq -r '.nodes[]|select(.type=="hysteria2")|.cert_dir' "$STATE")
cmp -s "$dir/fullchain.pem" "$work/v3/tls/hy2.dodo258.local.crt" && cmp -s "$dir/key.pem" "$work/v3/tls/hy2.dodo258.local.key" || fail 'self-signed certificate copied'
[[ $(tree_hash) == "$before" ]] || fail '/etc/v2ray-agent changed'
[[ -f $DATA/migrated-v3.json ]] || fail 'migration not recorded'
main <<< $'0' > "$work/out" 2>&1
if grep -q '发现旧版节点\|9. 迁移旧版节点' "$work/out"; then fail 'migration offered again'; fi
echo 'PASS the menu alone (Enter, 1) migrates: old service stopped and disabled, cron jobs commented out, certificates copied, /etc/v2ray-agent unchanged'

# Enter at 「确认 / 返回」 goes back; 0 at the offer as well. Item 9 stays in the menu.
load_fixture reality
main <<< $'\n\n0\n0' > "$work/out" 2>&1 || fail 'menu back'
main <<< $'0\n0\n0' >> "$work/out" 2>&1 || fail 'menu no'
[[ ! -e $STATE ]] && ! grep -qE '^(disable|stop)' "$work/systemctl.log" || fail 'going back changed something'
# docs/menu-preview.txt shows these screens.
for line in '  1. 是，先看看能迁移哪些' '  0. 否（以后在菜单「9. 迁移旧版节点」里也能迁移）' '  1. 确认迁移（服务会重启，连接断开几秒）' '  9. 迁移旧版节点 · 发现 v3 安装'; do
    grep -qxF -- "$line" "$work/out" || fail "menu lacks: $line"
    grep -qxF -- "$line" docs/menu-preview.txt || fail "docs/menu-preview.txt is out of date: $line"
done
main <<< $'0\n0\n9\n1\n0' > "$work/out" 2>&1 || fail 'menu item 9 run'
jq -e '.nodes[0].type == "vless" and .nodes[0].port == 30443' "$STATE" >/dev/null || { cat "$work/out"; fail 'item 9 did not migrate'; }
echo 'PASS Enter at 确认 / 返回 changes nothing; menu item 9 migrates later; docs/menu-preview.txt shows these screens'

# A failed takeover (health check, sing-box check) brings v3 back as it was.
load_fixture snell
before=$(tree_hash)
cp "$work/crontab" "$work/crontab.before"
apply_state() { return 1; }
if main migrate --apply --yes > "$work/out" 2>&1; then fail 'failed apply exited 0'; fi
grep -q '迁移失败，已恢复旧服务' "$work/out" || { cat "$work/out"; fail 'failure message'; }
for unit in dodo258-snell-20260101120000-32443 dodo258-shadowtls-20260101120000-32443 dodo258-snell-20260102120000-32444 dodo258-shadowtls-20260102120000-32444; do
    [[ -e $work/units/$unit.service.active && -e $work/units/$unit.service.enabled ]] || fail "$unit not restored"
    grep -q "^disable --now $unit.service$" "$work/systemctl.log" && grep -q "^start $unit.service$" "$work/systemctl.log" || fail "$unit not stopped and started"
done
cmp -s "$work/crontab" "$work/crontab.before" && [[ ! -e $STATE && ! -e $DATA/migrated-v3.json && $(tree_hash) == "$before" ]] || fail 'failed apply left changes'
# A unit that cannot start again is reported.
touch "$work/units/broken-dodo258-snell-20260101120000-32443.service"
if main migrate --apply --yes > "$work/out" 2>&1; then fail 'failed apply exited 0'; fi
grep -q '旧服务没能全部恢复' "$work/out" || { cat "$work/out"; fail 'restore failure not reported'; }
apply_state() { validate_state "$1" && mkdir -p "$DATA/current" && cp "$1" "$STATE"; }
load_fixture reality
echo 1 > "$work/core-check"
if main migrate --apply --yes > "$work/out" 2>&1; then fail 'apply despite sing-box check failure'; fi
grep -q '没有通过 sing-box 校验，旧服务没有停止' "$work/out" && [[ ! -e $STATE && -e $work/units/dodo258-sing-box.service.active ]] || { cat "$work/out"; fail 'check failure'; }
if grep -qs 'disable' "$work/systemctl.log"; then fail 'units touched before the check passed'; fi
echo 'PASS --apply that fails restores the old services (running and enabled), crontab and state; a failed sing-box check stops nothing'

# --apply without --yes asks; at the end of input nothing happens. With --yes Snell nodes
# get their server program and the v4 services of the old nodes stop.
load_fixture snell
if main migrate --apply < /dev/null > "$work/out" 2>&1; then fail '--apply without an answer exited 0'; fi
[[ ! -e $STATE ]] || fail '--apply without confirmation changed state'
main migrate --apply --yes > "$work/out" 2>&1 || { cat "$work/out"; fail 'snell apply'; }
[[ $(cat "$work/snell-installed") == $'5\n5' ]] || fail 'snell-server v5 installed'
jq -e '[.nodes[]|.type == "snell" and .snell_version == 5]|all and length == 2' "$STATE" >/dev/null || fail 'snell nodes'
[[ -e $work/units/dodo258-snell-20260103120000-32445.service.active ]] || fail 'the node that did not move must keep running'
echo 'PASS --apply asks unless --yes; Snell nodes move to snell-server v5; nodes that do not move keep their services'

# A certificate moved from v3 is renewed by a new Let's Encrypt request within 30 days of expiry.
issue_certificate() { printf '%s\n' "$*" >> "$work/issued"; }
owned_root() { return 0; }
mkdir -p "$DATA/certs/old.example.com/active" "$DATA/certs/new.example.com/active"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 10 -subj /CN=old.example.com -keyout /dev/null -out "$DATA/certs/old.example.com/active/fullchain.pem" >/dev/null 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 80 -subj /CN=new.example.com -keyout /dev/null -out "$DATA/certs/new.example.com/active/fullchain.pem" >/dev/null 2>&1
printf 'v3\n' | tee "$DATA/certs/old.example.com/active/renewal-source" > "$DATA/certs/new.example.com/active/renewal-source"
jq -n '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
  {id:"1111111111111111",name:"a",type:"trojan",enabled:true,host:"192.0.2.10",port:1001,sni:"old.example.com",password:"p",cert_dir:"/x"},
  {id:"2222222222222222",name:"b",type:"trojan",enabled:true,host:"192.0.2.10",port:1002,sni:"new.example.com",password:"p",cert_dir:"/x"}]}' > "$STATE"
renew_certificates > "$work/out" 2>&1 || { cat "$work/out"; fail 'renew'; }
[[ $(cat "$work/issued") == 'old.example.com auto   force' ]] || { cat "$work/issued"; fail 'v3 certificate renewal'; }
[[ $(certificate_source old.example.com) == v3 ]] || fail 'v3 origin'
echo 'PASS certificates moved from v3 get a new Let'"'"'s Encrypt certificate within 30 days of expiry, not before'

# With a real core: every sample's migrated configuration passes `sing-box check`, and
# the Reality public key derived here matches the core's own key pair.
if [[ -n ${TEST_CORE:-} ]]; then
    CORE=$TEST_CORE
    pair=$("$CORE" generate reality-keypair)
    [[ $(reality_public_key "$(awk '/PrivateKey:/{print $2}' <<< "$pair")") == "$(awk '/PublicKey:/{print $2}' <<< "$pair")" ]] || fail 'public key derivation'
    for case in reality trio multi snell tls; do
        load_fixture "$case"
        main migrate --apply --yes > "$work/out" 2>&1 || { cat "$work/out"; fail "$case with the real core"; }
        render_config "$STATE" > "$work/config.json" && "$CORE" check -c "$work/config.json" || fail "$case config"
    done
    echo 'PASS migrated configurations of all samples pass the real sing-box check; derived Reality public keys match the core'
    # v3's sing-box clients send ws early data; migrated ws nodes accept it, and clients
    # without it (srm's own snippets) as well. The control server without early data
    # shows the field is needed.
    wait_port() { local i; for ((i=0; i<50; i++)); do (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0; sleep 0.2; done; return 1; }
    pids=()
    trap 'for pid in ${pids[@]+"${pids[@]}"}; do kill "$pid" 2>/dev/null || true; done; rm -rf "$work"' EXIT
    mkdir -p "$work/www"; printf 'srm-migrate-ok\n' > "$work/www/index.html"
    python3 -m http.server 18399 --bind 127.0.0.1 --directory "$work/www" > /dev/null 2>&1 & pids+=("$!"); disown "$!"
    load_fixture tls
    main migrate --apply --yes > "$work/out" 2>&1 || { cat "$work/out"; fail 'tls sample'; }
    serve() {
        render_config "$1" > "$work/server.json"
        "$CORE" run -c "$work/server.json" > "$work/server.log" 2>&1 & server=$!; pids+=("$server")
        wait_port 18399 && wait_port 33444 || { cat "$work/server.log"; fail 'server did not start'; }
    }
    through() {
        local early=$2 page rc=0
        node_json "$STATE" "$1" | jq '.host = "127.0.0.1"' | client_outbound | jq --arg ca "$work/ca.pem" --argjson early "$early" '.tls.certificate_path = $ca
            | if $early then .transport += {max_early_data:2048,early_data_header_name:"Sec-WebSocket-Protocol"} else . end
            | {log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:18398}],outbounds:[.],route:{final:.tag}}' > "$work/client.json"
        "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client=$!; pids+=("$client")
        wait_port 18398 || return 2
        page=$("$real_curl" --noproxy '' --silent --fail --max-time 8 --socks5-hostname 127.0.0.1:18398 http://127.0.0.1:18399/) || rc=1
        kill "$client"; wait "$client" 2>/dev/null || true
        [[ $rc == 0 && $page == srm-migrate-ok ]]
    }
    serve "$STATE"
    for name in vlesstls-33444 vmess-33446; do
        id=$(jq -r --arg n "$name" '.nodes[]|select(.name == $n)|.id' "$STATE")
        through "$id" true || { cat "$work/client.log" "$work/server.log"; fail "v3 early-data client through $name"; }
        through "$id" false || { cat "$work/client.log" "$work/server.log"; fail "client without early data through $name"; }
    done
    kill "$server"; wait "$server" 2>/dev/null || true
    jq '.nodes |= map(del(.early_data))' "$STATE" > "$work/no-early.json"
    serve "$work/no-early.json"
    if through "$id" true; then fail 'early data worked without the server setting; the early_data field would be unneeded'; fi
    kill "$server"; wait "$server" 2>/dev/null || true
    echo 'PASS clients of v3 with ws early data, and clients without it, fetch a page through the migrated VLESS ws and VMess ws nodes'
else
    printf 'SKIP real core check of migrated configurations: TEST_CORE not set\n'
fi
