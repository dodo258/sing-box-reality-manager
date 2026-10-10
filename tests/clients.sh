#!/usr/bin/env bash
# Share links and client snippets of every protocol, field validation, and
# non-interactive deployment of the protocols added after the skeleton.
# No core or root needed; tests/traffic.sh runs the same nodes through real clients.
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
mkdir -p "$SRM_ROOT" "$DATA/current"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"

[[ $PROTOCOLS == 'vless anytls hysteria2 shadowsocks tuic vlesstls trojan vmess naive hysteria' ]] || fail "registered: $PROTOCOLS"
echo 'PASS Shadowsocks 2022, TUIC v5, VLESS TLS, Trojan, VMess, Naive and Hysteria v1 are registered'

uuid=0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a5b
pin=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
jq -n --arg uuid "$uuid" --arg pin "$pin" '
  def node($id; $name; $type; $port): {id:$id,name:$name,type:$type,enabled:true,host:"192.0.2.1",port:$port};
  def cert: {sni:"test.example.com",cert_dir:"/var/lib/srm/certs/test.example.com/active"};
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
   node("100000000000000f"; "reality"; "vless"; 20015) + {sni:"www.ctrip.com",uuid:$uuid,private_key:"priv",public_key:"pub",short_id:"0123456789abcdef"}
  ]}' > "$work/state.json"
validate_state "$work/state.json" || fail 'fixture state rejected'
node() { node_json "$work/state.json" "$1"; }
expect() {
    local id=$1 format=$2 want=$3 got
    case $format in uri) got=$(node "$id" | share_uri);; clash) got=$(node "$id" | clash_proxy);; surge) got=$(node "$id" | surge_proxy);; esac
    [[ $got == "$want" ]] || fail "$format of $(node "$id" | jq -r .name)"$'\n'"  want: $want"$'\n'"  got:  $got"
}

# Share links. Shadowsocks follows SIP002: AEAD-2022 userinfo is not base64,
# method and password are percent-encoded.
expect 1000000000000001 uri 'ss://2022-blake3-aes-128-gcm:YctPZ6U7xPPcU%2Bgp3u%2B0tw%3D%3D@192.0.2.1:20001#ss%20%E8%8A%82%E7%82%B9'
expect 1000000000000002 uri "tuic://$uuid:pw%2F1@192.0.2.1:20002?congestion_control=bbr&alpn=h3&sni=test.example.com&udp_relay_mode=native#tuic"
expect 1000000000000003 uri "tuic://$uuid:pw@192.0.2.1:20003?congestion_control=bbr&alpn=h3&sni=www.bing.com&udp_relay_mode=native&allow_insecure=1#tuic-self"
expect 1000000000000004 uri "vless://$uuid@192.0.2.1:20004?encryption=none&security=tls&sni=test.example.com&fp=chrome&type=tcp&flow=xtls-rprx-vision#v-tcp"
expect 1000000000000005 uri "vless://$uuid@192.0.2.1:20005?encryption=none&security=tls&sni=test.example.com&fp=chrome&type=ws&host=test.example.com&path=%2Fa1b2&alpn=http%2F1.1#v-ws"
expect 1000000000000006 uri "vless://$uuid@192.0.2.1:20006?encryption=none&security=tls&sni=test.example.com&fp=chrome&type=grpc&serviceName=c3d4&mode=gun&alpn=h2#v-grpc"
expect 1000000000000007 uri "vless://$uuid@192.0.2.1:20007?encryption=none&security=tls&sni=test.example.com&fp=chrome&type=httpupgrade&host=test.example.com&path=%2Fe5f6&alpn=http%2F1.1#v-hu"
expect 1000000000000008 uri 'trojan://pw@192.0.2.1:20008?security=tls&sni=test.example.com&type=tcp#trojan'
expect 100000000000000a uri 'naive+https://0123456789ab:pw@test.example.com:20010#naive'
expect 100000000000000b uri 'hysteria://192.0.2.1:20011?protocol=udp&auth=pw&peer=test.example.com&upmbps=30&downmbps=100&alpn=hysteria#hy1'
expect 100000000000000c uri 'hysteria://192.0.2.1:20012?protocol=udp&auth=pw&peer=www.bing.com&upmbps=30&downmbps=100&alpn=hysteria&insecure=1#hy1-self'
expect 100000000000000d uri "hysteria2://pw@192.0.2.1:20013?sni=www.bing.com&alpn=h3&insecure=1&pinSHA256=$pin#hy2-self"
expect 100000000000000e uri 'anytls://pw@192.0.2.1:20014?sni=test.example.com#anytls'
# VMess: v2rayN's base64 JSON with string values.
link=$(node 1000000000000009 | share_uri)
[[ $link == vmess://* ]] || fail 'vmess scheme'
printf '%s' "${link#vmess://}" | openssl base64 -d -A | jq -e --arg uuid "$uuid" '. == {v:"2",ps:"vmess",add:"192.0.2.1",port:"20009",id:$uuid,aid:"0",scy:"auto",net:"ws",type:"none",
  host:"test.example.com",path:"/a7b8",tls:"tls",sni:"test.example.com",alpn:"http/1.1",fp:"chrome"}' >/dev/null || fail 'vmess link JSON'
# IPv6 hosts are bracketed; names and passwords are escaped.
node 1000000000000008 | jq '.host="2001:db8::1"|.password="a:@ /?#&"|.name="中文 & x"' | share_uri > "$work/uri"
[[ $(cat "$work/uri") == 'trojan://a%3A%40%20%2F%3F%23%26@[2001:db8::1]:20008?security=tls&sni=test.example.com&type=tcp#%E4%B8%AD%E6%96%87%20%26%20x' ]] || fail "escaping: $(cat "$work/uri")"
echo 'PASS share links: SS2022 (SIP002), TUIC, VLESS TLS ×4, Trojan, VMess, Naive, Hysteria v1/v2 incl. self-signed pins'

# Clash Meta (mihomo) proxies, one flow mapping per line.
expect 1000000000000001 clash '- {"name":"ss 节点","server":"192.0.2.1","port":20001,"type":"ss","cipher":"2022-blake3-aes-128-gcm","password":"YctPZ6U7xPPcU+gp3u+0tw==","udp":true}'
expect 1000000000000003 clash '- {"name":"tuic-self","server":"192.0.2.1","port":20003,"type":"tuic","uuid":"'"$uuid"'","password":"pw","alpn":["h3"],"congestion-controller":"bbr","udp-relay-mode":"native","sni":"www.bing.com","fingerprint":"'"$pin"'"}'
expect 1000000000000005 clash '- {"name":"v-ws","server":"192.0.2.1","port":20005,"type":"vless","uuid":"'"$uuid"'","tls":true,"servername":"test.example.com","client-fingerprint":"chrome","udp":true,"network":"ws","ws-opts":{"path":"/a1b2","headers":{"Host":"test.example.com"}}}'
expect 1000000000000006 clash '- {"name":"v-grpc","server":"192.0.2.1","port":20006,"type":"vless","uuid":"'"$uuid"'","tls":true,"servername":"test.example.com","client-fingerprint":"chrome","udp":true,"network":"grpc","grpc-opts":{"grpc-service-name":"c3d4"}}'
expect 1000000000000007 clash '- {"name":"v-hu","server":"192.0.2.1","port":20007,"type":"vless","uuid":"'"$uuid"'","tls":true,"servername":"test.example.com","client-fingerprint":"chrome","udp":true,"network":"ws","ws-opts":{"path":"/e5f6","headers":{"Host":"test.example.com"},"v2ray-http-upgrade":true}}'
expect 1000000000000009 clash '- {"name":"vmess","server":"192.0.2.1","port":20009,"type":"vmess","uuid":"'"$uuid"'","alterId":0,"cipher":"auto","tls":true,"servername":"test.example.com","udp":true,"network":"ws","ws-opts":{"path":"/a7b8","headers":{"Host":"test.example.com"}}}'
expect 100000000000000c clash '- {"name":"hy1-self","server":"192.0.2.1","port":20012,"type":"hysteria","auth-str":"pw","up":"30 Mbps","down":"100 Mbps","protocol":"udp","sni":"www.bing.com","alpn":["hysteria"],"fingerprint":"'"$pin"'"}'
expect 100000000000000f clash '- {"name":"reality","server":"192.0.2.1","port":20015,"type":"vless","uuid":"'"$uuid"'","network":"tcp","tls":true,"udp":true,"flow":"xtls-rprx-vision","servername":"www.ctrip.com","reality-opts":{"public-key":"pub","short-id":"0123456789abcdef"},"client-fingerprint":"chrome"}'
expect 100000000000000a clash ''
echo 'PASS Clash Meta snippets, with the certificate fingerprint for self-signed nodes; none for Naive'

# Surge proxy lines (manual.nssurge.com/policies); no VLESS, Naive or Hysteria v1.
expect 1000000000000001 surge 'ss 节点 = ss, 192.0.2.1, 20001, encrypt-method=2022-blake3-aes-128-gcm, password="YctPZ6U7xPPcU+gp3u+0tw==", udp-relay=true'
expect 1000000000000003 surge "tuic-self = tuic-v5, 192.0.2.1, 20003, password=\"pw\", uuid=$uuid, alpn=h3, sni=www.bing.com, server-cert-fingerprint-sha256=$pin"
expect 1000000000000008 surge 'trojan = trojan, 192.0.2.1, 20008, password="pw", sni=test.example.com'
expect 1000000000000009 surge "vmess = vmess, 192.0.2.1, 20009, username=$uuid, ws=true, ws-path=/a7b8, ws-headers=Host:test.example.com, tls=true, sni=test.example.com, vmess-aead=true"
expect 100000000000000d surge "hy2-self = hysteria2, 192.0.2.1, 20013, password=\"pw\", sni=www.bing.com, server-cert-fingerprint-sha256=$pin"
expect 100000000000000e surge 'anytls = anytls, 192.0.2.1, 20014, password="pw", sni=test.example.com'
for id in 1000000000000004 100000000000000a 100000000000000b 100000000000000f; do expect "$id" surge ''; done
node 1000000000000008 | jq '.name="a, b = c"' | surge_proxy | grep -q '^a  b   c = trojan, ' || fail 'surge name escaping'
echo 'PASS Surge lines, with server-cert-fingerprint-sha256 for self-signed nodes; none for unsupported protocols'

# sing-box client outbounds: self-signed nodes pin the public key, others use the CA.
node 1000000000000003 | client_outbound | jq -e '.tls.certificate_public_key_sha256==["lSYy2gx+EMQODMJuSwKlopSiRbeTovhZ4IsSxF1Dnp4="] and (.tls.insecure|not)' >/dev/null || fail 'pinned outbound'
node 1000000000000002 | client_outbound | jq -e '.tls|has("certificate_public_key_sha256")|not' >/dev/null || fail 'CA outbound has a pin'
node 1000000000000001 | client_outbound | jq -e 'has("tls")|not' >/dev/null || fail 'shadowsocks outbound has tls'
echo 'PASS sing-box outbounds pin self-signed certificates and never set insecure'

# Server inbounds per protocol and transport.
render_config "$work/state.json" > "$work/config.json"
jq -e '
  def ib($t): .inbounds[]|select(.tag==$t);
  (ib("1000000000000001")|.type=="shadowsocks" and .method=="2022-blake3-aes-128-gcm" and (has("network")|not)) and
  (ib("1000000000000004")|.users[0].flow=="xtls-rprx-vision" and (has("transport")|not) and (.tls|has("alpn")|not)) and
  (ib("1000000000000005")|.transport=={type:"ws",path:"/a1b2"} and .tls.alpn==["http/1.1"] and (.users[0]|has("flow")|not)) and
  (ib("1000000000000006")|.transport=={type:"grpc",service_name:"c3d4"} and .tls.alpn==["h2"]) and
  (ib("1000000000000007")|.transport=={type:"httpupgrade",path:"/e5f6"}) and
  (ib("1000000000000009")|.users[0].alterId==0 and .transport.path=="/a7b8") and
  (ib("100000000000000a")|.network=="tcp" and .users==[{username:"0123456789ab",password:"pw"}]) and
  (ib("1000000000000003")|.tls.certificate_path=="/var/lib/srm/selfsigned/x/fullchain.pem" and .congestion_control=="bbr") and
  (ib("100000000000000b")|.users==[{name:"100000000000000b",auth_str:"pw"}] and .tls.alpn==["hysteria"])' "$work/config.json" >/dev/null || fail 'rendered inbounds'
echo 'PASS server inbounds for every protocol and VLESS transport'

# Transports: Shadowsocks opens TCP and UDP on one port; firewall and health
# checks expand them per port.
[[ $(jq -r ".nodes[]|.port as \$p|($(proto_jq_transports))[]|\"\(\$p)/\(.)\"" "$work/state.json" | tr '\n' ' ') == \
   '20001/tcp 20001/udp 20002/udp 20003/udp 20004/tcp 20005/tcp 20006/tcp 20007/tcp 20008/tcp 20009/tcp 20010/tcp 20011/udp 20012/udp 20013/udp 20014/tcp 20015/tcp ' ]] || fail 'transports'
[[ $(bash srm.sh protocols | cut -f1,3 | tr '\t\n' ': ') == 'vless:tcp anytls:tcp hysteria2:udp shadowsocks:tcp udp tuic:udp vlesstls:tcp trojan:tcp vmess:tcp naive:tcp hysteria:udp ' ]] || fail 'protocol list'
echo 'PASS transports per protocol; Shadowsocks needs both TCP and UDP'

# Validation of the new fields.
for bad in \
  '.nodes[0].sni="example.com"' '.nodes[0].password="c2hvcnQ="' '.nodes[0].method="aes-128-gcm"' \
  '.nodes[1].uuid="not-a-uuid"' '.nodes[1]|=del(.sni)' '.nodes[2].cert_sha256="ABC"' '.nodes[2].pubkey_sha256="x"' \
  '.nodes[3].transport="xhttp"' '.nodes[4]|=del(.path)' '.nodes[4].path="no-slash"' '.nodes[5].service_name="a/b"' \
  '.nodes[8].path="/a b"' '.nodes[9].username="root"' '.nodes[13]|=del(.password)' '.nodes[14]|=del(.sni)'; do
    jq "$bad" "$work/state.json" > "$work/bad.json"
    if validate_state "$work/bad.json" 2>/dev/null; then fail "accepted $bad"; fi
done
echo 'PASS validation rejects malformed keys, UUIDs, transports, paths, pins and missing SNI'

# Node pages: one screen with every client's snippet.
cp "$work/state.json" "$STATE"
export_node 1000000000000003 clients > "$work/clients" || fail 'clients page'
grep -q '"certificate_public_key_sha256"' "$work/clients" && grep -q '^- {"name":"tuic-self"' "$work/clients" &&
    grep -q '^tuic-self = tuic-v5' "$work/clients" && grep -q "能填证书 SHA-256 指纹时填：$pin" "$work/clients" || { cat "$work/clients"; fail 'clients page content'; }
export_node 100000000000000a clients > "$work/clients" || fail 'naive clients page'
grep -q 'Clash Meta 不支持此协议' "$work/clients" && grep -q 'Surge 不支持此协议' "$work/clients" || fail 'unsupported clients'
# Fixture certificates do not exist, so details end with an openssl error.
export_node 100000000000000d details > "$work/details" 2>&1 || true
grep -q "\"cert_sha256\": \"$pin\"" "$work/details" || fail 'pin shown in details'
export_node 1000000000000002 details > "$work/details" 2>&1 || true
if grep -q 'pw/1' "$work/details"; then fail 'details show the TUIC password'; fi
echo 'PASS the client page lists sing-box, Clash Meta and Surge snippets and says which clients are unsupported'

# Non-interactive deployment with stubs for the system parts.
printf '#!/usr/bin/env bash\ncase $2 in uuid) printf "%%s\\n" 0f2a6c1e-3b4d-4e5f-8a9b-$(openssl rand -hex 6);; esac\n' > "$work/core"
chmod 755 "$work/core"
CORE=$work/core
ensure_dependencies() { return 0; }
ss() { return 0; }
sysctl() { return 1; }
chgrp() { :; }
apply_state() { validate_state "$1" && cp "$1" "$STATE"; }
issue_certificate() { printf '%s %s\n' "$1" "$2" >> "$work/issued"; }
jq '.nodes=[]' "$work/state.json" > "$STATE"
last() { jq -c '.nodes[-1]' "$STATE"; }

node_add self shadowsocks --host 192.0.2.1 --yes > "$work/out" 2>&1 || { cat "$work/out"; fail 'deploy shadowsocks'; }
last | jq -e 'has("sni")|not' >/dev/null && last | jq -e '.method=="2022-blake3-aes-128-gcm" and (.password|test("^[A-Za-z0-9+/]{22}==$"))' >/dev/null || fail 'shadowsocks fields'
grep -q '/TCP+UDP；' "$work/out" && grep -q '允许 TCP+UDP ' "$work/out" && grep -q '^ss://2022-blake3-aes-128-gcm:' "$work/out" || { cat "$work/out"; fail 'shadowsocks deploy output'; }

# TUIC and Hysteria without a domain default to a self-signed certificate whose
# pins match the certificate on disk.
for type in tuic hysteria hysteria2; do
    node_add self "$type" --host 192.0.2.1 --yes > "$work/out" 2>&1 || { cat "$work/out"; fail "deploy $type without domain"; }
    n=$(last)
    dir=$(jq -r .cert_dir <<< "$n")
    [[ $(jq -r .sni <<< "$n") == "$SELF_SIGNED_SNI" && $dir == "$DATA/selfsigned/$(jq -r .id <<< "$n")" ]] || { cat "$work/out"; echo "$n"; fail "$type self-signed location"; }
    want=$(openssl x509 -in "$dir/fullchain.pem" -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')
    [[ $(jq -r .cert_sha256 <<< "$n") == "$want" ]] || fail "$type certificate pin"
    want=$(openssl pkey -in "$dir/key.pem" -pubout -outform der | openssl dgst -sha256 -binary | openssl base64 -A)
    [[ $(jq -r .pubkey_sha256 <<< "$n") == "$want" ]] || fail "$type public key pin"
    openssl x509 -in "$dir/fullchain.pem" -noout -checkend $((3600*24*3600)) >/dev/null || fail "$type certificate lifetime"
done
[[ ! -e $work/issued ]] || fail 'self-signed deploy requested a Lets Encrypt certificate'
node_add self tuic --host vpn.example.com --yes > /dev/null 2>&1 || fail 'tuic with domain'
[[ $(cat "$work/issued") == 'vpn.example.com auto' ]] && last | jq -e '.sni=="vpn.example.com" and (has("cert_sha256")|not)' >/dev/null || fail 'tuic with a domain uses Lets Encrypt'
node_add self hysteria --host 192.0.2.1 --cert selfsigned --sni cdn.example.com --yes > /dev/null 2>&1 || fail 'self-signed with --sni'
last | jq -e '.sni=="cdn.example.com" and .cert_sha256' >/dev/null || fail 'self-signed --sni'
echo 'PASS TUIC and Hysteria without a domain get a self-signed certificate whose pins match; with a domain they use Lets Encrypt'

for transport in tcp ws grpc httpupgrade; do
    node_add self vlesstls --host 192.0.2.1 --sni vpn.example.com --transport "$transport" --yes > /dev/null 2>&1 || fail "vlesstls $transport"
    last | jq -e --arg t "$transport" '.transport==$t and
      (if $t=="grpc" then (.service_name|test("^[a-f0-9]{16}$")) and (has("path")|not)
       elif $t=="tcp" then (has("path") or has("service_name"))|not
       else (.path|test("^/[a-f0-9]{16}$")) end)' >/dev/null || fail "vlesstls $transport fields"
done
node_add self vlesstls --host vpn.example.com --yes > /dev/null 2>&1 || fail 'vlesstls default'
last | jq -e '.transport=="tcp"' >/dev/null || fail 'vlesstls default transport is tcp'
node_add self vmess --host vpn.example.com --yes > /dev/null 2>&1 || fail 'vmess'
last | jq -e '(.path|test("^/[a-f0-9]{16}$")) and (.uuid|test("^[a-f0-9-]{36}$"))' >/dev/null || fail 'vmess fields'
node_add self naive --host vpn.example.com --yes > /dev/null 2>&1 || fail 'naive'
last | jq -e '(.username|test("^[a-f0-9]{12}$")) and (.password|length)==48' >/dev/null || fail 'naive fields'
node_add self trojan --host vpn.example.com --yes > /dev/null 2>&1 || fail 'trojan'
before=$(sha256 "$STATE")
for bad in 'anytls --cert selfsigned' 'trojan --cert selfsigned' 'vlesstls --transport xhttp' 'trojan --transport ws' 'naive --cert 4' 'shadowsocks --transport ws'; do
    # shellcheck disable=SC2086 # split the argument list
    if node_add self $bad --host vpn.example.com --yes > "$work/out" 2>&1; then fail "deploy accepted $bad"; fi
done
grep -q -- '--transport 不适用于 Shadowsocks 2022' "$work/out" || fail 'transport message'
if node_add self trojan --host 192.0.2.1 --yes > "$work/out" 2>&1; then fail 'domain certificate without a domain accepted'; fi
grep -q '非交互模式缺少参数：证书域名' "$work/out" || fail 'missing domain message'
[[ $(sha256 "$STATE") == "$before" ]] || fail 'rejected deploys changed state'
validate_state "$STATE" || fail 'deployed state invalid'
echo 'PASS VLESS TLS (4 transports), VMess, Naive and Trojan deploy non-interactively; bad options change nothing'

# The menu: TUIC on a server without a domain proposes the self-signed certificate.
jq '.nodes=[]' "$work/state.json" > "$STATE"
node_add self <<< $'5\n\n192.0.2.1\n\n\ny' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu deploy'; }
grep -q '4.自签证书' "$work/out" && grep -q '证书方式 \[4\]' "$work/out" || { cat "$work/out"; fail 'self-signed not the default without a domain'; }
last | jq -e '.type=="tuic" and .cert_sha256' >/dev/null || fail 'menu deployed tuic self-signed'
echo 'PASS the menu offers a self-signed certificate as the default for TUIC without a domain'

# Rotation changes credentials and keeps the certificate and its pins.
jq '.nodes=[]' "$work/state.json" > "$STATE"
for type in shadowsocks tuic vlesstls trojan vmess naive hysteria; do
    args=(--sni vpn.example.com)
    if [[ $type == tuic || $type == hysteria ]]; then args=(--cert selfsigned); fi
    node_add self "$type" --host 192.0.2.1 "${args[@]}" --yes > /dev/null 2>&1 || fail "deploy $type for rotation"
    old=$(last)
    node_change "$(jq -r .id <<< "$old")" rotate > /dev/null || fail "rotate $type"
    new=$(last)
    jq -e -n --argjson a "$old" --argjson b "$new" '
      ($a|del(.password,.uuid)) == ($b|del(.password,.uuid)) and ($a.password != $b.password or $a.uuid != $b.uuid) and
      (($a.password == null) == ($b.password == null)) and (($a.uuid == null) == ($b.uuid == null))' >/dev/null || fail "rotate $type fields"
done
echo 'PASS credential rotation changes only passwords/UUIDs, never the certificate or pins'

# Certificate management ignores self-signed nodes: nothing to renew or reserve.
jq '.nodes=[]' "$work/state.json" > "$STATE"
node_add self tuic --host 192.0.2.1 --yes > /dev/null 2>&1 || fail 'deploy for certificate page'
systemctl() { return 3; }
certificate_status > "$work/status" 2>&1 || fail 'certificate status'
grep -q '另有 1 个节点使用自签证书' "$work/status" && grep -q '目前没有使用 TLS 证书的节点' "$work/status" || { cat "$work/status"; fail 'self-signed status'; }
firewall_renew() { printf 'called\n' > "$work/renew-called"; }
owned_root() { return 0; }
renew_certificates || fail 'renew with only self-signed nodes'
[[ ! -e $work/renew-called ]] || fail 'self-signed certificate sent to renewal'
echo 'PASS certificate pages and renewal skip self-signed nodes'

# Only the registry may branch on protocol type names.
if grep -nwE "$(tr ' ' '|' <<< "$PROTOCOLS")" lib/*.sh | grep -v '^lib/protocols.sh:'; then fail 'protocol type matched outside lib/protocols.sh'; fi
echo 'PASS no module outside lib/protocols.sh matches any protocol type name'
