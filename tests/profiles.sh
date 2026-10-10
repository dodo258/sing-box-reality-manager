#!/usr/bin/env bash
# Whole client configurations (mihomo, sing-box, Surge) and the temporary import link:
# what each configuration contains, the one-tap import link of each app, and that the
# download service closes after one download, after its time or when interrupted, with
# the firewall opening removed every time. Needs python3 (the download service).
# TEST_CORE / TEST_MIHOMO (CI) also run the configurations through `sing-box check` and
# `mihomo -t`; tests/firewall-live.sh repeats the link against real iptables.
# Assertions use `|| fail` because `! cmd` never trips set -e, and bash 3.2
# (macOS) also ignores a failing [[ ]].
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
work=$(mktemp -d)
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/current/state.json
mkdir -p "$SRM_ROOT" "$DATA/current"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
require_root() { return 0; }
require_linux() { return 0; }
with_lock() { "$@"; }
port_free() { valid_port "$1"; }
resolve_domain() { printf '%s\n' "${dns_answer:-198.51.100.7}"; }
# Records what the firewall was asked: the temporary port, then "sync" when it is closed.
firewall_sync() { printf '%s\n' "${2:-sync}" >> "$work/firewall"; }
http() { curl --noproxy '*' --silent --show-error --fail --max-time 5 "$@"; }

uuid=0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a5b
pin=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
key=0123456789abcdef0123456789abcdef
jq -n --arg uuid "$uuid" --arg pin "$pin" --arg key "$key" --arg certs "$DATA/certs" '
  def node($id; $name; $type; $port): {id:$id,name:$name,type:$type,enabled:true,host:"192.0.2.1",port:$port};
  def cert: {sni:"test.example.com",cert_dir:"\($certs)/test.example.com/active"};
  def self: {sni:"www.bing.com",cert_dir:"/var/lib/srm/selfsigned/x",cert_sha256:$pin,pubkey_sha256:"lSYy2gx+EMQODMJuSwKlopSiRbeTovhZ4IsSxF1Dnp4="};
  {schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
   node("1000000000000001"; "ss 节点"; "shadowsocks"; 20001) + {method:"2022-blake3-aes-128-gcm",password:"YctPZ6U7xPPcU+gp3u+0tw=="},
   node("1000000000000002"; "tuic"; "tuic"; 20002) + cert + {uuid:$uuid,password:"pw/1"},
   node("1000000000000003"; "tuic-self"; "tuic"; 20003) + self + {uuid:$uuid,password:"pw"},
   node("1000000000000004"; "v-tcp"; "vlesstls"; 20004) + cert + {uuid:$uuid,transport:"tcp"},
   node("1000000000000005"; "v-ws"; "vlesstls"; 20005) + cert + {uuid:$uuid,transport:"ws",path:"/a1b2"},
   node("1000000000000006"; "v-grpc"; "vlesstls"; 20006) + cert + {uuid:$uuid,transport:"grpc",service_name:"c3d4"},
   node("1000000000000007"; "v-hu"; "vlesstls"; 20007) + cert + {uuid:$uuid,transport:"httpupgrade",path:"/e5f6"},
   node("1000000000000008"; "trojan"; "trojan"; 20008) + cert + {password:"pw"},
   node("1000000000000009"; "vmess"; "vmess"; 20009) + cert + {uuid:$uuid,path:"/a7b8"},
   node("100000000000000a"; "naive"; "naive"; 20010) + cert + {username:"0123456789ab",password:"pw"},
   node("100000000000000b"; "hy1"; "hysteria"; 20011) + cert + {password:"pw"},
   node("100000000000000c"; "hy1-self"; "hysteria"; 20012) + self + {password:"pw"},
   node("100000000000000d"; "hy2-self"; "hysteria2"; 20013) + self + {password:"pw"},
   node("100000000000000e"; "anytls"; "anytls"; 20014) + cert + {password:"pw"},
   node("100000000000000f"; "reality"; "vless"; 20015) + {sni:"www.python.org",uuid:$uuid,private_key:"priv",public_key:"Z1Pq0-lHkWkM9wGFDw7tkVcxl7Gx5bCKJVnJ2Pq8Wy0",short_id:"0123456789abcdef"},
   node("1000000000000010"; "hy2"; "hysteria2"; 20016) + cert + {password:"pw/1"},
   node("1000000000000011"; "snell6"; "snell"; 20017) + {sni:"www.python.org",snell_version:6,snell_mode:"default",psk:$key,shadowtls_password:$key,local_port:21017},
   node("1000000000000012"; "snell5"; "snell"; 20018) + {sni:"www.python.org",snell_version:5,psk:$key,shadowtls_password:$key,local_port:21018},
   node("1000000000000013"; "off"; "hysteria2"; 20019) + cert + {password:"pw", enabled:false},
   node("1000000000000014"; "hy2"; "hysteria2"; 20020) + cert + {password:"pw2"},
   node("1000000000000015"; "节点选择"; "trojan"; 20021) + cert + {password:"pw"}
  ]}' > "$STATE"
validate_state "$STATE" || fail 'fixture state rejected'

# mihomo: every enabled node mihomo supports, the group, DNS and the basic routing.
profile_render clash "$STATE" > "$work/clash.yaml" 2> "$work/err" || { cat "$work/err"; fail 'mihomo profile'; }
grep -qxF 'Clash Verge / Clash Meta for Android（mihomo） 不支持这些节点的协议，没有放进配置：naive、snell6' "$work/err" || { cat "$work/err"; fail 'skipped nodes not listed'; }
sed -n '/^proxies:$/,/^proxy-groups:$/p' "$work/clash.yaml" | sed -n 's/^  - //p' | jq -s . > "$work/proxies.json"
names='["ss 节点","tuic","tuic-self","v-tcp","v-ws","v-grpc","v-hu","trojan","vmess","hy1","hy1-self","hy2-self","anytls","reality","hy2","snell5","hy2 (2)","节点选择 (2)"]'
jq -e --argjson names "$names" '[.[].name] == $names' "$work/proxies.json" >/dev/null || { jq -c '[.[].name]' "$work/proxies.json"; fail 'mihomo proxies'; }
# Each entry is the node's own Clash Meta snippet.
[[ $(jq -c '.[0]' "$work/proxies.json") == "$(node_json "$STATE" 1000000000000001 | clash_proxy | sed 's/^- //' | jq -c .)" ]] || fail 'proxy entry differs from the snippet'
group=$(sed -n '/^proxy-groups:$/{n;s/^  - //p;}' "$work/clash.yaml")
jq -e --argjson names "$names" '. == {name:"节点选择",type:"select",proxies:($names + ["DIRECT"])}' <<< "$group" >/dev/null || fail "mihomo group: $group"
for line in 'mode: rule' '  enhanced-mode: fake-ip' '  nameserver: ["https://dns.alidns.com/dns-query", "https://doh.pub/dns-query"]' \
            '  - "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve"' '  - "GEOSITE,cn,DIRECT"' '  - "GEOIP,CN,DIRECT"'; do
    grep -qxF -- "$line" "$work/clash.yaml" || fail "mihomo profile lacks: $line"
done
[[ $(tail -n 1 "$work/clash.yaml") == '  - "MATCH,节点选择"' ]] || fail 'mihomo final rule'
if grep -q '"off"\|20019' "$work/clash.yaml"; then fail 'disabled node exported'; fi
echo 'PASS mihomo profile: every enabled node mihomo supports (others listed), unique names, one select group, fake-ip DNS, private and mainland China direct'

# sing-box: tun inbound, the group over every node, helper outbounds after their node.
profile_render sing-box "$STATE" > "$work/sing-box.json" 2> "$work/err" || { cat "$work/err"; fail 'sing-box profile'; }
[[ ! -s $work/err ]] || { cat "$work/err"; fail 'sing-box skipped a node'; }
jq -e --argjson names "$names" '
  (.outbounds[0] == {type:"selector",tag:"节点选择",outbounds:($names[0:9] + ["naive"] + $names[9:15] + ["snell6"] + $names[15:])}) and
  ([.outbounds[].tag]|length == (unique|length)) and
  ([.outbounds[].tag] as $tags|all(.outbounds[]|.detour // empty; . as $d|any($tags[]; . == $d))) and
  (.outbounds[-1] == {type:"direct",tag:"direct"}) and
  (.inbounds == [{type:"tun",tag:"tun-in",address:["172.19.0.1/30","fdfe:dcba:9876::1/126"],auto_route:true,strict_route:true}]) and
  (.route.final == "节点选择" and .route.default_domain_resolver == "local" and
   .route.rules[2] == {ip_is_private:true,outbound:"direct"} and .route.rules[3] == {rule_set:["geosite-cn","geoip-cn"],outbound:"direct"} and
   [.route.rule_set[].url] == ["https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs","https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"] and
   all(.route.rule_set[]; .download_detour == "节点选择")) and
  (.dns.final == "remote" and .dns.rules == [{rule_set:"geosite-cn",action:"route",server:"local"}]) and
  (all(.outbounds[]; .server_port != 20019))' "$work/sing-box.json" >/dev/null || { jq -c '.outbounds[0], [.outbounds[].tag]' "$work/sing-box.json"; fail 'sing-box profile'; }
[[ $(jq -c '.outbounds[1]' "$work/sing-box.json") == "$(node_json "$STATE" 1000000000000001 | client_outbound | jq -c .)" ]] || fail 'outbound differs from the snippet'
echo 'PASS sing-box profile: tun inbound, a selector over every enabled node (helper outbounds resolved), DNS and rule sets for mainland China direct'

# Surge: proxy lines as in the snippets, the group lists the names as the lines write them.
profile_render surge "$STATE" > "$work/surge.conf" 2> "$work/err" || { cat "$work/err"; fail 'Surge profile'; }
grep -qxF 'Surge 不支持这些节点的协议，没有放进配置：v-tcp、v-ws、v-grpc、v-hu、naive、hy1、hy1-self、reality' "$work/err" || { cat "$work/err"; fail 'Surge skipped nodes'; }
sed -n '/^\[Proxy\]$/,/^$/p' "$work/surge.conf" | sed '1d;$d' > "$work/surge-proxies"
[[ $(wc -l < "$work/surge-proxies") -eq 12 && $(head -n 1 "$work/surge-proxies") == "$(node_json "$STATE" 1000000000000001 | surge_proxy)" ]] || { cat "$work/surge-proxies"; fail 'Surge proxies'; }
[[ $(sed -n '/^\[Proxy Group\]$/,$p' "$work/surge.conf") == '[Proxy Group]
节点选择 = select, ss 节点, tuic, tuic-self, trojan, vmess, hy2-self, anytls, hy2, snell6, snell5, hy2 (2), 节点选择 (2), DIRECT

[Rule]
RULE-SET,LAN,DIRECT
DOMAIN-SUFFIX,cn,DIRECT
GEOIP,CN,DIRECT
FINAL,节点选择,dns-failed' ]] || { cat "$work/surge.conf"; fail 'Surge group and rules'; }
grep -qxF '[General]' "$work/surge.conf" && grep -qxF 'dns-server = 223.5.5.5, 119.29.29.29' "$work/surge.conf" || fail 'Surge [General]'
echo 'PASS Surge profile: the Surge lines of supported nodes, one select group with the same names, LAN and mainland China direct, FINAL with dns-failed'

# One node; a disabled, unknown or unsupported one fails without output.
profile_render sing-box "$STATE" 1000000000000011 | jq -e '[.outbounds[].tag] == ["节点选择","snell6","snell6-shadowtls","direct"] and .outbounds[0].outbounds == ["snell6"]' >/dev/null || fail 'single node'
profile_render clash "$STATE" 100000000000000f | grep -q '"name":"reality"' || fail 'single mihomo node'
for args in 'clash 1000000000000013' 'clash 2000000000000000' 'surge 100000000000000a' 'clash 1000000000000011' 'v2rayn'; do
    # shellcheck disable=SC2086 # client and node ID
    if profile_render ${args%% *} "$STATE" $( [[ $args == *' '* ]] && printf '%s' "${args#* }" ) > "$work/out" 2> "$work/err"; then fail "accepted: $args"; fi
    [[ ! -s $work/out && -s $work/err ]] || fail "output or no message for: $args"
done
grep -q '客户端只能是：clash sing-box surge' "$work/err" || fail 'unknown client message'
profile_render surge "$STATE" 100000000000000a > /dev/null 2> "$work/err" || true
grep -q 'Surge 都不支持' "$work/err" || fail 'unsupported node message'
# A node named like another node's helper outbound: the helper is renamed, its node follows.
jq '.nodes += [{id:"1000000000000016",name:"snell6-shadowtls",type:"trojan",enabled:true,host:"192.0.2.1",port:20022,
  sni:"test.example.com",cert_dir:"/c",password:"pw"},{id:"1000000000000017",name:"Direct",type:"trojan",enabled:true,host:"192.0.2.1",port:20023,
  sni:"test.example.com",cert_dir:"/c",password:"pw"}]' "$STATE" > "$work/helper.json"
profile_render sing-box "$work/helper.json" > "$work/helper-profile.json" || fail 'helper name clash'
jq -e '([.outbounds[].tag]|length == (unique|length)) and any(.outbounds[]; .tag == "snell6" and .detour == "snell6-shadowtls (2)")
  and any(.outbounds[]; .tag == "snell6-shadowtls (2)" and .type == "shadowtls") and any(.outbounds[]; .tag == "snell6-shadowtls" and .type == "trojan")
  and any(.outbounds[]; .tag == "Direct (2)")' "$work/helper-profile.json" >/dev/null || { jq -c '[.outbounds[]|[.tag,.detour]]' "$work/helper-profile.json"; fail 'helper renamed'; }
echo 'PASS a single node can be exported; a disabled, unknown or unsupported node, or an unknown app, fails without output'

# One-tap import links, each in the form its app documents or implements:
#   sing-box  sing-box.sagernet.org/clients/general/ "Profile import": sing-box://import-remote-profile?url=urlEncodedURL#urlEncodedName
#   Clash     Clash Verge Rev src-tauri/src/utils/resolve/scheme.rs (scheme clash, query "url=" to the end) and
#             Clash Meta for Android AndroidManifest.xml (clash / clashmeta, host install-config) + ExternalControlActivity.kt (url, name)
#   Surge     manual.nssurge.com/tools/url-scheme.html: surge:///install-config?url=x, x percent-encoded
url='http://192.0.2.1:23456/0123456789abcdef0123456789abcdef/srm.yaml'
encoded='http%3A%2F%2F192.0.2.1%3A23456%2F0123456789abcdef0123456789abcdef%2Fsrm.yaml'
[[ $(profile_import_link sing-box "$url" 'srm-香港 1') == "sing-box://import-remote-profile?url=$encoded#srm-%E9%A6%99%E6%B8%AF%201" ]] || fail 'sing-box import link'
link=$(profile_import_link clash "$url" 'srm-香港 1')
[[ $link == "clash://install-config?name=srm-%E9%A6%99%E6%B8%AF%201&url=$encoded" ]] || fail "Clash import link: $link"
# Clash Verge Rev takes everything after the first "url=" and decodes it: exactly the URL.
[[ $(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "${link#*url=}") == "$url" ]] || fail 'Clash Verge Rev would read another URL'
[[ $(profile_import_link surge "$url" x) == "surge:///install-config?url=$encoded" ]] || fail 'Surge import link'
https='https://vpn.example.com:8443/abc/srm.json?a=1&b=2'
[[ $(profile_import_link sing-box "$https" n) == 'sing-box://import-remote-profile?url=https%3A%2F%2Fvpn.example.com%3A8443%2Fabc%2Fsrm.json%3Fa%3D1%26b%3D2#n' ]] || fail 'reserved characters in the URL'
echo 'PASS one-tap import links: sing-box import-remote-profile, clash install-config (name before url), surge install-config; URL and name percent-encoded'

# The temporary link. Waits until the run prints its download URL.
link_url() {
    local i
    for ((i=0; i<100; i++)); do
        grep -m 1 -E '^https?://' "$1" 2>/dev/null && return 0
        sleep 0.1
    done
    cat "$1"; return 1
}
free_port() { printf '%s\n' $((30000 + RANDOM % 9000)); }
# Downloaded once: the content is the profile, other paths are 404 and do not count,
# a second download finds the port closed, and the firewall opening is removed.
rm -f "$work/firewall"
port=$(free_port)
profile_link sing-box '' "$port" 30 > "$work/link.out" 2>&1 & pid=$!; pids+=("$pid")
url=$(link_url "$work/link.out") || fail 'no link printed'
[[ $url =~ ^http://192\.0\.2\.1:$port/[0-9a-f]{32}/srm\.json$ ]] || fail "download URL: $url"
local_url=http://127.0.0.1:$port/${url#*:"$port"/}
[[ $(cat "$work/firewall") == "$port" ]] || fail 'temporary port not opened before serving'
if http "http://127.0.0.1:$port/srm.json" > /dev/null 2>&1; then fail 'served outside the random path'; fi
if http "http://127.0.0.1:$port/${url##*/}" > /dev/null 2>&1; then fail 'served without the token'; fi
http -I "$local_url" > /dev/null || fail 'HEAD refused'
http "$local_url" > "$work/downloaded" || fail 'download failed'
cmp -s "$work/downloaded" <(profile_render sing-box "$STATE" 2>/dev/null) || fail 'downloaded file differs from the profile'
wait "$pid" || { cat "$work/link.out"; fail 'link exit code after the download'; }
[[ $(cat "$work/firewall") == "$port"$'\n'sync ]] || fail "firewall opening not removed after the download: $(cat "$work/firewall")"
if http "$local_url" > /dev/null 2>&1; then fail 'second download served'; fi
grep -qxF '已下载一次，临时链接已关闭。' "$work/link.out" || fail 'closing message'
grep -qxF '注意：没有域名证书，只能用 HTTP 传输：链接里带节点密码，用完即关。' "$work/link.out" || fail 'HTTP warning'
grep -qxF "$(profile_import_link sing-box "$url" srm-192.0.2.1)" "$work/link.out" || fail 'import link of the download URL not shown'
echo 'PASS the temporary link serves the profile once at its random path (404 elsewhere), then closes and removes the firewall opening; over HTTP it warns that the link carries node passwords'

# Nobody downloads: closed after its time, firewall opening removed.
rm -f "$work/firewall"
port=$(free_port)
profile_link clash 100000000000000f "$port" 2 > "$work/link.out" 2>&1 & pid=$!; pids+=("$pid")
url=$(link_url "$work/link.out") || fail 'no link printed'
sleep 3
wait "$pid" || { cat "$work/link.out"; fail 'link exit code after the timeout'; }
[[ $(cat "$work/firewall") == "$port"$'\n'sync ]] || fail 'firewall opening not removed after the timeout'
if http "http://127.0.0.1:$port/${url#*:"$port"/}" > /dev/null 2>&1; then fail 'served after the timeout'; fi
grep -qxF '1 分钟内没有下载，临时链接已关闭。' "$work/link.out" || { cat "$work/link.out"; fail 'timeout message'; }
grep -qF 'clash://install-config?name=srm-reality&url=' "$work/link.out" || fail 'single-node profile name'
echo 'PASS without a download the link closes after its time and the firewall opening is removed'

# A dropped SSH session (SIGHUP to the whole process group, like Ctrl+C sends SIGINT):
# the service stops and the opening goes too. Job control gives the run its own group.
rm -f "$work/firewall"
port=$(free_port)
set -m
profile_link surge '' "$port" 60 > "$work/link.out" 2>&1 & pid=$!; pids+=("$pid")
set +m
url=$(link_url "$work/link.out") || fail 'no link printed'
kill -HUP -- "-$pid"
wait "$pid" 2>/dev/null || true
[[ $(cat "$work/firewall") == "$port"$'\n'sync ]] || fail 'firewall opening not removed after an interrupt'
sleep 0.3
if http "http://127.0.0.1:$port/${url#*:"$port"/}" > /dev/null 2>&1; then fail 'served after an interrupt'; fi
echo 'PASS an interrupted link stops serving and removes the firewall opening'

# A valid CA-style certificate of a node whose domain points here: HTTPS on the domain.
mkdir -p "$DATA/certs/test.example.com/active"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj /CN=test.example.com \
    -addext subjectAltName=DNS:test.example.com -keyout "$DATA/certs/test.example.com/active/key.pem" \
    -out "$DATA/certs/test.example.com/active/fullchain.pem" > /dev/null 2>&1 || fail 'test certificate'
dns_answer=192.0.2.1
rm -f "$work/firewall"
port=$(free_port)
profile_link clash '' "$port" 30 > "$work/link.out" 2>&1 & pid=$!; pids+=("$pid")
url=$(link_url "$work/link.out") || fail 'no link printed'
[[ $url =~ ^https://test\.example\.com:$port/[0-9a-f]{32}/srm\.yaml$ ]] || fail "HTTPS URL: $url"
http --resolve "test.example.com:$port:127.0.0.1" --cacert "$DATA/certs/test.example.com/active/fullchain.pem" "$url" > "$work/downloaded" || fail 'HTTPS download'
cmp -s "$work/downloaded" "$work/clash.yaml" || fail 'HTTPS content'
wait "$pid" || fail 'HTTPS link exit code'
if grep -q '只能用 HTTP' "$work/link.out"; then fail 'HTTP warning over HTTPS'; fi
[[ $(cat "$work/firewall") == "$port"$'\n'sync ]] || fail 'HTTPS firewall opening'
dns_answer=198.51.100.7
echo 'PASS with a certificate whose domain points here the link uses HTTPS on that domain, without the HTTP warning'

# Menus: node management lists both after the nodes; Enter = all nodes, then the app.
count=$(jq '.nodes|length' "$STATE")
node_menu <<< "$((count+1))"$'\n\n3' > "$work/out" 2>&1 || { cat "$work/out"; fail 'export menu'; }
for line in "  $((count+1)). 导出完整配置 · 可直接导入 Clash Verge / sing-box App / Surge" "  $((count+2)). 临时导入链接 · 扫码一键导入，用完自动关闭" \
            '  1. 全部启用的节点（20 个）' '  1. Clash Verge / Clash Meta for Android（mihomo）' '  2. sing-box 官方 App（iOS / Android / macOS）' '  3. Surge' \
            'FINAL,节点选择,dns-failed' '把上面的内容保存为 srm.conf，在 App 里从文件导入。更省事的是在「2. 节点管理」里选「临时导入链接」，扫码一键导入。'; do
    grep -qxF -- "$line" "$work/out" || { cat "$work/out"; fail "menu lacks: $line"; }
done
rm -f "$work/firewall"
port=$(free_port)
node_menu <<< "$((count+2))"$'\n2\n2\n'"$port" > "$work/link.out" 2>&1 & pid=$!; pids+=("$pid")
url=$(link_url "$work/link.out") || fail 'menu link'
http "http://127.0.0.1:$port/${url#*:"$port"/}" > "$work/downloaded" || fail 'menu link download'
wait "$pid" || fail 'menu link exit code'
jq -e '.outbounds[0].outbounds == ["ss 节点"]' "$work/downloaded" >/dev/null || fail 'menu link: node 2 of the list = the first node'
[[ $(cat "$work/firewall") == "$port"$'\n'sync ]] || fail 'menu link firewall'
for line in "临时端口（回车随机选一个空闲端口） [随机]：" '  2. ss 节点'; do
    grep -qF -- "$line" "$work/link.out" || fail "link menu lacks: $line"
done
# docs/menu-preview.txt shows these screens (its example has other node numbers).
for line in '导出完整配置 · 可直接导入 Clash Verge / sing-box App / Surge' '临时导入链接 · 扫码一键导入，用完自动关闭' '  1. 全部启用的节点（' \
            '  1. Clash Verge / Clash Meta for Android（mihomo）' '  2. 节点管理 · 链接 / 二维码 / 完整配置' '临时端口（回车随机选一个空闲端口） [随机]：' \
            '注意：没有域名证书，只能用 HTTP 传输：链接里带节点密码，用完即关。' '已下载一次，临时链接已关闭。'; do
    grep -qF -- "$line" docs/menu-preview.txt || fail "docs/menu-preview.txt lacks: $line"
done
grep -qF -- '  2. 节点管理 · 链接 / 二维码 / 完整配置' lib/main.sh || fail 'main menu line'
echo 'PASS node management offers 「导出完整配置」 and 「临时导入链接」 after the nodes (Enter = all nodes, then the app); docs/menu-preview.txt shows them'

# Command line: profile on stdout, profile-link options checked before anything opens.
main profile surge > "$work/out" 2>/dev/null || fail 'srm profile'
cmp -s "$work/out" "$work/surge.conf" || fail 'srm profile output'
rm -f "$work/firewall"
for args in 'profile-link clash --minutes 0' 'profile-link clash --port' 'profile-link clash --bogus' 'profile-link v2rayn' 'profile'; do
    # shellcheck disable=SC2086 # words of the command line
    if main $args > /dev/null 2>&1; then fail "accepted: srm $args"; fi
done
[[ ! -e $work/firewall ]] || fail 'a rejected command touched the firewall'
echo 'PASS srm profile prints the profile; srm profile-link rejects bad options and apps before opening anything'

# The configurations against the real programs (CI).
[[ -n ${TEST_CORE:-} && -n ${TEST_MIHOMO:-} ]] || skip_or_fail "${0##*/}：sing-box check / mihomo -t 需要 TEST_CORE 和 TEST_MIHOMO（CI 会下载）"
"$TEST_CORE" check -c "$work/sing-box.json" || fail 'sing-box check rejected the profile'
profile_render sing-box "$STATE" 1000000000000011 > "$work/one.json" && "$TEST_CORE" check -c "$work/one.json" || fail 'sing-box check rejected the single-node profile'
"$TEST_CORE" check -c "$work/helper-profile.json" || fail 'sing-box check rejected the profile with a renamed helper'
echo 'PASS sing-box check accepts the whole sing-box profile (every protocol) and a single-node one'
mkdir -p "$work/mihomo"
# mihomo loads the geo data GEOSITE / GEOIP need (downloads it on first use, as the apps ship it).
"$TEST_MIHOMO" -t -d "$work/mihomo" -f "$work/clash.yaml" > "$work/mihomo.log" 2>&1 || { cat "$work/mihomo.log"; fail 'mihomo -t rejected the profile'; }
grep -q 'test is successful' "$work/mihomo.log" || { cat "$work/mihomo.log"; fail 'mihomo -t result'; }
echo 'PASS mihomo -t accepts the whole mihomo profile (every protocol mihomo supports)'
