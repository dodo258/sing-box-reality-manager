#!/usr/bin/env bash
# Quick deploy: the menu deploys with Enter only, asks at most two questions with
# defaults (plus the domain for certificate protocols), checks the domain before any
# certificate request, and prints one screen per client; `srm add --json` prints the
# same as JSON. System commands are replaced by fixtures; curl and wget record calls.
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
mkdir -p "$SRM_ROOT" "$DATA/current" "$work/bin"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
for tool in curl wget; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/network-calls"\nexit 1\n' "$tool" "$work" > "$work/bin/$tool"
done
printf '#!/usr/bin/env bash\ncat > /dev/null\necho "[QR $*]"\n' > "$work/bin/qrencode"
printf '#!/usr/bin/env bash\ncase $2 in reality-keypair) printf "PrivateKey: priv%%s\\nPublicKey: pub%%s\\n" $RANDOM $RANDOM;; uuid) printf "%%s\\n" 0f2a6c1e-3b4d-4e5f-8a9b-$(openssl rand -hex 6);; esac\n' > "$work/core"
chmod 755 "$work/bin/"* "$work/core"
export PATH="$work/bin:$PATH"
CORE=$work/core
require_linux() { return 0; }
with_lock() { "$@"; }
systemctl() { case $1 in is-active|is-enabled) return 3;; esac; }
ensure_dependencies() { return 0; }
ss() { return 0; }
sysctl() { return 1; }
chgrp() { :; }
apply_state() { validate_state "$1" && mkdir -p "$DATA/current" && cp "$1" "$STATE"; }
# This server: 192.0.2.10 in Japan. Only www.mozilla.org passes the target check,
# so the automatic pick has to skip the first built-in target.
detect_public_ip() { PUBLIC_IP=192.0.2.10; PUBLIC_LOC=JP; }
reality_target_check() { printf '%s\n' "$1" >> "$work/checked"; [[ $1 == www.mozilla.org ]] && REPLY=35; }
issue_certificate() { printf 'ISSUE %s %s\n' "$1" "$2"; printf '%s\n' "$1" >> "$work/issued"; }
cert_auto_mode() { printf 'http\n'; }
snell_install() { :; }
resolve_domain() { printf '%s\n' "${dns_answer:-192.0.2.10}"; }
last() { jq -c '.nodes[-1]' "$STATE"; }
# Questions with a default, as printed by ask: "prompt [default]：".
# Prompts carry no newline, so several can share a line of the captured output.
questions() { perl -CSD -Mutf8 -ne 'while (/([^：\n]*? \[[^\]]*\]：)/g) { print "$1\n" }' "$1" | grep -vE '^请选择 ' || true; }

# A fresh server: the menu opens on quick deploy and Enter, Enter, Enter deploys
# VLESS Reality; Enter once more returns to the menu, 0 leaves it.
rm -f "$STATE"
main <<< $'\n\n\n\n0' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu exit code'; }
[[ $(jq '.nodes|length' "$STATE") == 1 ]] || { cat "$work/out"; fail 'no node deployed'; }
last | jq -e '.type=="vless" and .name=="vless-JP" and .host=="192.0.2.10" and .sni=="www.mozilla.org" and .port >= 10000 and .port <= 50000' >/dev/null ||
    { last; fail 'Reality node fields'; }
[[ $(questions "$work/out" | tr '\n' '|') == '端口（1–65535，回车随机选一个空闲端口） [随机]：|节点名称 [vless-JP]：|' ]] || { questions "$work/out" | od -c | head; fail "questions asked"; }
[[ $(sort "$work/checked" | tr '\n' ' ') == "$(tr ' ' '\n' <<< "$REALITY_TARGETS" | sort | tr '\n' ' ')" ]] || fail 'not every built-in target checked'
grep -qxF '伪装目标：自动选用 www.mozilla.org（握手 35 ms；以后可以在「2. 节点管理」里更换）' "$work/out" || fail 'picked target not shown'
[[ ! -e $work/network-calls ]] || { cat "$work/network-calls"; fail 'network access outside the stubs'; }
echo 'PASS a fresh server deploys VLESS Reality from the menu with Enter only; the target is picked and checked automatically'

# The one screen after deploying.
for want in '━━ 部署完成：vless-JP（VLESS Reality）' '服务器：192.0.2.10' '放行入站 TCP ' '── 分享链接 ──' '^vless://' '\[QR -t UTF8\]' \
            '── Clash Meta (mihomo)' '── sing-box：' '"type": "vless"' '── Shadowrocket：' '── v2rayN：' '1. 添加节点 · 快速部署'; do
    grep -q -- "$want" "$work/out" || { cat "$work/out"; fail "summary lacks: $want"; }
done
if grep -q '── Surge' "$work/out"; then fail 'Surge section for VLESS (Surge has no VLESS)'; fi
if grep -q '已有节点的连接会断开几秒' "$work/out"; then fail 'restart notice without running nodes'; fi
# Summary first, menu after it: the deploy output is not scrolled into the menu loop.
[[ $(grep -n '部署完成' "$work/out" | cut -d: -f1) -lt $(grep -n '1. 添加节点 · 快速部署' "$work/out" | head -n 1 | cut -d: -f1) ]] || fail 'summary order'
echo 'PASS the summary shows address, cloud firewall ports, link, local QR code and Clash Meta / sing-box / Shadowrocket / v2rayN, without Surge'

# Node management item 10: the checked targets, Enter takes the fastest; the node
# switches and its link, QR code and client configurations come again.
reality_target_check() { case $1 in www.mozilla.org) REPLY=35;; www.python.org) REPLY=20;; *) return 1;; esac; }
id=$(last | jq -r .id)
main <<< $'2\n1\n10\n\n0' > "$work/out" 2>&1 || { cat "$work/out"; fail 'retarget from the menu'; }
last | jq -e --arg id "$id" '.id==$id and .sni=="www.python.org"' >/dev/null || { cat "$work/out"; fail 'target not switched'; }
for want in '10.更换伪装目标（Reality 借用握手的网站）' '  当前：www.mozilla.org' '  1. www.python.org         握手 20 ms（最快）' \
            '  2. www.mozilla.org        握手 35 ms' '  3. 自己填一个网站域名（同样要通过检测）' '新的客户端配置：' 'sni=www.python.org' '[QR -t UTF8]' '── Shadowrocket：'; do
    grep -qF -- "$want" "$work/out" || { cat "$work/out"; fail "retarget screen lacks: $want"; }
done
# Picking the current target changes nothing and shows no new configuration.
before=$(sha256 "$STATE")
main <<< $'2\n1\n10\n\n0' > "$work/out2" 2>&1 || fail 'retarget to the current target'
[[ $(sha256 "$STATE") == "$before" ]] && grep -q '当前已经使用此目标，无需修改。' "$work/out2" || { cat "$work/out2"; fail 'current target'; }
if grep -q '新的客户端配置' "$work/out2"; then fail 'configuration shown again without a change'; fi
line=$(grep -F -m 1 '10.更换伪装目标' "$work/out")
grep -qxF -- "$line" docs/menu-preview.txt || fail "docs/menu-preview.txt is out of date: $line"
echo 'PASS node management switches the target with Enter (fastest checked one) and shows the new link, QR code and configurations'

# With nodes the menu no longer jumps into quick deploy; item 1 opens it.
main <<< $'0' > "$work/out" 2>&1 || fail 'menu with nodes'
if grep -q '快速部署（' "$work/out"; then fail 'quick deploy opened although nodes exist'; fi
main <<< $'1\n0\n0' > "$work/out" 2>&1 || fail 'menu item 1'
grep -q '快速部署（' "$work/out" && grep -q '2. Hysteria2' "$work/out" && grep -q '3. Snell + ShadowTLS' "$work/out" &&
    grep -qE '4. AnyTLS +需要域名' "$work/out" && grep -q '5. 更多协议…' "$work/out" || { cat "$work/out"; fail 'quick list'; }
echo 'PASS menu item 1 opens the quick-deploy list: Reality, Hysteria2, Snell + ShadowTLS, AnyTLS, more'

# Every protocol: at most two questions with defaults; certificate protocols also ask
# the domain (typed), nothing else is typed.
for type in $PROTOCOLS; do
    input=$'\n\n\n\n'
    [[ $(proto_call "$type" domain) != required ]] || input=$'vpn.example.com\n'"$input"
    node_add self "$type" <<< "$input" > "$work/out" 2>&1 || { cat "$work/out"; fail "interactive $type"; }
    last | jq -e --arg t "$type" '.type == $t and .host == "192.0.2.10"' >/dev/null || { cat "$work/out"; fail "$type not deployed"; }
    count=$(questions "$work/out" | wc -l | tr -d ' ')
    (( count <= 2 )) || { questions "$work/out"; fail "$type asks $count questions"; }
    if [[ $(proto_call "$type" domain) == required ]]; then
        grep -q '域名（没有域名直接回车，换一个协议）：' "$work/out" || fail "$type domain question"
    elif grep -q '域名（' "$work/out"; then fail "$type asks for a domain"; fi
done
echo "PASS each of the $(wc -w <<< "$PROTOCOLS" | tr -d ' ') protocols asks at most two questions with defaults; only certificate protocols ask the domain"

# More protocols: those without a domain first.
# Leaving the list without deploying: fine inside the menu, a failure for `srm add`.
if node_add self <<< $'5\n0\n0' > "$work/out" 2>&1; then fail 'srm add without a node exited 0'; fi
grep -q '没有部署节点' "$work/out" || fail 'no-node message'
grep -q '1. Shadowsocks 2022' "$work/out" && grep -q '2. TUIC v5' "$work/out" && grep -qE '3. Hysteria v1 +兼容老客户端' "$work/out" &&
    grep -qE '4. VLESS TLS +需要域名' "$work/out" || { cat "$work/out"; fail 'more list order'; }
echo 'PASS 更多协议 lists the protocols without a domain first'

# `srm add TYPE` interactively: no input, 0 or no domain deploys nothing and fails;
# 「没有域名，换一个协议」 opens the list. Missing paths for --cert are asked.
before=$(sha256 "$STATE")
if node_add self vless < /dev/null > "$work/out" 2>&1; then fail 'srm add vless at EOF exited 0'; fi
if main add vless --json < /dev/null > "$work/json" 2> "$work/err"; then fail 'srm add --json without --yes at EOF exited 0'; fi
[[ ! -s $work/json ]] || fail 'JSON printed without a node'
if node_add self anytls <<< $'0' > "$work/out" 2>&1; then fail 'srm add anytls, 0 at the domain, exited 0'; fi
[[ $(sha256 "$STATE") == "$before" ]] || fail 'cancelled deploys changed state'
node_add self anytls <<< $'\n1\n\n\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'no domain, then the list'; }
grep -q '快速部署（' "$work/out" && last | jq -e '.type=="vless"' >/dev/null || fail 'no domain did not open the list'
# The protocol's own options stay behind: --domain of AnyTLS does not block Reality.
dns_answer=198.51.100.7
node_add self anytls --domain bad.example.com <<< $'\n\n3\n1\n\n\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'another protocol after --domain'; }
last | jq -e '.type=="vless"' >/dev/null || fail 'switched to Reality after --domain'
dns_answer=192.0.2.10
node_add self hysteria2 --cert auto <<< $'hy2.example.com\n\n\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'hysteria2 --cert auto asks the domain'; }
last | jq -e '.type=="hysteria2" and .sni=="hy2.example.com" and (has("cert_sha256")|not)' >/dev/null || fail 'hysteria2 domain certificate'
node_add self vlesstls --domain www2.example.com --cert webroot <<< $'\n\n/srv/www\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'webroot path asked'; }
grep -q '^ISSUE www2.example.com webroot$' "$work/out" && grep -q '现有网站根目录绝对路径' "$work/out" || { cat "$work/out"; fail 'webroot path'; }
if grep -q '非交互模式' "$work/out"; then fail 'interactive run says non-interactive'; fi
echo 'PASS srm add TYPE fails without a node (no JSON), opens the list when there is no domain and asks the paths --cert needs'

# A domain that does not point here is reported before any certificate request:
# AnyTLS → domain → wrong record → 3 (no domain, another protocol) → Reality.
rm -f "$work/issued"
dns_answer=198.51.100.7
node_add self <<< $'4\nvpn.example.com\n3\n1\n\n\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'switch protocol'; }
grep -q '域名 vpn.example.com 解析到 198.51.100.7，不是本机 192.0.2.10' "$work/out" || { cat "$work/out"; fail 'wrong record message'; }
[[ ! -e $work/issued ]] || fail 'certificate requested for a domain that points elsewhere'
last | jq -e '.type=="vless"' >/dev/null || fail 'switched to Reality'
# Enter at the domain question = no domain: back to the list.
node_add self <<< $'4\n\n2\n\n\n\n' > "$work/out" 2>&1 || fail 'no domain'
last | jq -e '.type=="hysteria2" and .cert_sha256' >/dev/null || { cat "$work/out"; fail 'no domain → Hysteria2 self-signed'; }
# The summary of a UDP-only node explains the latency test and UDP-blocking networks,
# and Surge comes field by field before the whole line (docs/menu-preview.txt shows both).
for line in "$(grep -m 1 '^只走 UDP：' "$work/out")" '── Surge：手机版新建代理后按下面逐项填写 ──' 'Mac 版或在配置文本里编辑：把下面整行放进配置的 [Proxy] 段'; do
    [[ -n ${line#只走 UDP：} ]] && grep -qxF -- "$line" "$work/out" && grep -qxF -- "$line" docs/menu-preview.txt || { cat "$work/out"; fail "summary or docs/menu-preview.txt lacks: $line"; }
done
grep -q '^hysteria2://[^?]*:[0-9]*/?sni=' "$work/out" || { cat "$work/out"; fail 'Hysteria2 link in the summary'; }
[[ ! -e $work/issued ]] || fail 'certificate requested without a domain'
# Fixing the record and checking again: the certificate is requested after the check.
printf '0\n' > "$work/dns-tries"
resolve_domain() {
    local n; n=$(cat "$work/dns-tries"); printf '%s\n' $((n+1)) > "$work/dns-tries"
    if (( n == 0 )); then printf '198.51.100.7\n'; else printf '192.0.2.10\n'; fi
}
node_add self <<< $'4\nVPN.example.com\n1\n\n\n\n' > "$work/out" 2>&1 || { cat "$work/out"; fail 'check again'; }
[[ $(cat "$work/issued") == vpn.example.com ]] || { cat "$work/out"; fail 'certificate after the fixed record'; }
[[ $(grep -n '不是本机' "$work/out" | cut -d: -f1) -lt $(grep -n '^ISSUE ' "$work/out" | cut -d: -f1) ]] || fail 'check before the certificate'
last | jq -e '.type=="anytls" and .sni=="vpn.example.com" and .host=="192.0.2.10"' >/dev/null || fail 'AnyTLS node'
grep -q '── Surge：' "$work/out" && grep -q '── Clash Meta' "$work/out" && grep -q '^anytls://' "$work/out" || { cat "$work/out"; fail 'AnyTLS clients'; }
# Adding a node next to running ones restarts the service: one line says so (no extra question).
grep -q '应用新配置会重启服务，已有节点的连接会断开几秒。' "$work/out" || fail 'restart notice'
resolve_domain() { printf '%s\n' "${dns_answer:-192.0.2.10}"; }
echo 'PASS a domain that does not resolve here is reported before the certificate request; no domain or another protocol is one choice away'

# The command line: same content as JSON on stdout, progress on stderr.
rm -f "$work/issued"
dns_answer=192.0.2.10
main add vless --yes --json > "$work/json" 2> "$work/err" || { cat "$work/err"; fail 'add --json'; }
jq -e '.type=="vless" and .protocol=="VLESS Reality" and .host=="192.0.2.10" and .firewall==[{port:.port,protocol:"tcp"}] and
  (.share_link|startswith("vless://")) and .clients.shadowrocket==.share_link and .clients.v2rayn==.share_link and
  .clients.clash_meta.type=="vless" and .clients.sing_box.type=="vless" and (.clients|has("surge")|not)' "$work/json" >/dev/null || { cat "$work/json"; fail 'Reality JSON'; }
grep -q '配置已应用\|部署：' "$work/err" || fail 'progress not on stderr'
main add shadowsocks --port 20444 --name ss-x --yes --json > "$work/json" 2> "$work/err" || { cat "$work/err"; fail 'ss --json'; }
jq -e '.name=="ss-x" and .port==20444 and .firewall==[{port:20444,protocol:"tcp"},{port:20444,protocol:"udp"}] and (.clients.surge|startswith("ss-x = ss"))' "$work/json" >/dev/null || { cat "$work/json"; fail 'SS JSON'; }
main add snell --yes --json > "$work/json" 2> "$work/err" || { cat "$work/err"; fail 'snell --json'; }
jq -e '.share_link==null and (.clients|keys)==["sing_box","surge"] and (.note|length > 0)' "$work/json" >/dev/null || { cat "$work/json"; fail 'Snell JSON'; }
main add hysteria2 --domain hy.example.com --yes --json > "$work/json" 2> "$work/err" || { cat "$work/err"; fail 'hysteria2 --domain'; }
jq -e '.clients.v2rayn and (.share_link|test("sni=hy.example.com"))' "$work/json" >/dev/null && [[ $(cat "$work/issued") == hy.example.com ]] || fail 'hysteria2 domain certificate'
echo 'PASS srm add --json prints one parsable object per deploy, with only the supported clients; progress goes to stderr'

before=$(sha256 "$STATE")
dns_answer=198.51.100.7
if main add anytls --domain vpn2.example.com --yes --json > "$work/json" 2> "$work/err"; then fail 'wrong record accepted'; fi
[[ ! -s $work/json ]] && grep -q '不是本机' "$work/err" && grep -q '没有申请证书' "$work/err" || { cat "$work/json" "$work/err"; fail 'wrong record message on the command line'; }
[[ $(cat "$work/issued") == hy.example.com ]] || fail 'certificate requested on the command line despite the wrong record'
if main add vless --domain vpn.example.com --yes > "$work/out" 2>&1; then fail '--domain accepted for Reality'; fi
grep -q 'VLESS Reality 不需要域名' "$work/out" || fail '--domain message'
if main add anytls --yes > "$work/out" 2>&1; then fail 'anytls without a domain'; fi
grep -q '非交互模式缺少参数：证书域名（--domain）' "$work/out" || fail 'missing domain message'
[[ $(sha256 "$STATE") == "$before" ]] || fail 'rejected command-line deploys changed state'
echo 'PASS the command line refuses a domain that does not point here (before the certificate), --domain for Reality and a missing domain'

# docs/menu-preview.txt shows the current menus.
dns_answer=192.0.2.10
main <<< $'1\n5\n0\n0\n0' > "$work/out" 2>&1 || fail 'preview run'
for block in '  1. 添加节点 · 快速部署' '  1. VLESS Reality      推荐 · 不需要域名 · 回车即可' '  5. 更多协议…' '  1. Shadowsocks 2022' '  7. Naive'; do
    line=$(grep -F -m 1 -- "$block" "$work/out") || fail "menu lacks: $block"
    grep -qxF -- "$line" docs/menu-preview.txt || fail "docs/menu-preview.txt is out of date: $line"
done
echo 'PASS docs/menu-preview.txt matches the menus'

# User-facing text never asks to run a command (the --help text is for advanced users).
# Typing srm to open the menu is fine; running it or typing a subcommand is not.
if grep -nE '(运行|执行)[ `「]*(srm|vasma)|输入[ `「]*(srm|vasma) +[a-z-]' lib/*.sh; then fail 'UI text asks the user to run srm'; fi
echo 'PASS no 「运行 srm」 or 「执行 srm」 in lib/'
