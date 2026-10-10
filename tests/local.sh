#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
need_core
CORE=${TEST_CORE:?set TEST_CORE to sing-box 1.14.1}
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
work=$(mktemp -d)
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
pass=0
ok() { pass=$((pass+1)); printf 'PASS %s\n' "$1"; }
for port in 1 80 443 10000 33524 65535; do valid_port "$port"; done
for port in 0 65536 99999 01000 080 '1;id' '' -1 ' 443'; do ! valid_port "$port" || exit 1; done
ok 'port boundaries 1–65535 and invalid input'
for host in example.com test.example.com xn--fiqs8s.cn; do valid_domain "$host"; done
for host in '-x.com' 'a..com' 'abc.com;id' 'a/com' 'a-.com'; do ! valid_domain "$host" || exit 1; done
ok 'domain validation'
"$TEST_OPENSSL" req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$work/key.pem" -out "$work/fullchain.pem" -days 2 -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com > "$work/openssl.log" 2>&1
cert_valid "$work/fullchain.pem" "$work/key.pem" test.example.com
! cert_valid "$work/fullchain.pem" "$work/key.pem" wrong.example.com || exit 1
ok 'certificate validation accepts correct hostname and rejects mismatched hostname'
pair=$("$CORE" generate reality-keypair)
private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
uuid=$("$CORE" generate uuid)
jq -n --arg dir "$work" --arg private "$private" --arg public "$public" --arg uuid "$uuid" '{schema:2,nodes:[
 {id:"1111111111111111",name:"Reality 测试",type:"vless",enabled:true,host:"127.0.0.1",port:18101,sni:"www.microsoft.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"},
 {id:"2222222222222222",name:"AnyTLS 测试",type:"anytls",enabled:true,host:"127.0.0.1",port:18102,sni:"test.example.com",password:"test_password_with_32_characters_1234",cert_dir:$dir},
 {id:"3333333333333333",name:"Hysteria2 测试",type:"hysteria2",enabled:true,host:"127.0.0.1",port:18103,sni:"test.example.com",password:"test_password_with_32_characters_1234",cert_dir:$dir}
],policies:[],unlock_dns:null,egress:null}' > "$work/state.json"
render_config "$work/state.json" > "$work/server.json"
"$CORE" check -c "$work/server.json"
ok 'all three protocol configurations accepted by real core'
for mutation in '.nodes[1].port=.nodes[0].port' '.nodes[1].id=.nodes[0].id' '.nodes[0].port=0' '.nodes[0].port=65536' '.schema=1' '.nodes[0].type="vmess"' '.nodes[0].name="bad\nname"' '.policies=[{name:"x",mode:"dns",domains:["netflix.com"]}]'; do
 jq "$mutation" "$work/state.json" > "$work/invalid.json"
 if validate_state "$work/invalid.json" 2>/dev/null; then echo "FAILED: accepted $mutation"; exit 1; fi
done
ok 'reject duplicate identifiers, ports, unsupported protocol and incomplete routing'
jq '.unlock_dns="1.1.1.1"|.egress={type:"socks",version:"5",server:"127.0.0.1",server_port:18888}|.policies=[{name:"Netflix",mode:"dns",domains:["netflix.com"]},{name:"YouTube",mode:"proxy",domains:["youtube.com"]}]' "$work/state.json" > "$work/routing.json"
render_config "$work/routing.json" > "$work/routing-config.json"
"$CORE" check -c "$work/routing-config.json"
jq -e '.route.final=="direct" and .dns.final=="local" and ([.route.rules[]|select(.outbound=="media-proxy")]|length==1)' "$work/routing-config.json" >/dev/null
ok 'DNS/proxy policies with unchanged default direct route'
node_json "$work/state.json" 2222222222222222 | jq '.password="a:@ /?#&"|.host="2001:db8::1"|.name="中文 & test"' | share_uri > "$work/url"
grep -q 'anytls://a%3A%40%20%2F%3F%23%26@\[2001:db8::1\]:18102' "$work/url"
grep -q '#%E4%B8%AD%E6%96%87%20%26%20test' "$work/url"
ok 'raw URI escaping and IPv6 brackets'
"$CORE" run -c "$work/server.json" > "$work/server.log" 2>&1 & pids+=("$!")
"$TEST_OPENSSL" s_server -accept 18104 -cert "$work/fullchain.pem" -key "$work/key.pem" -www > "$work/target.log" 2>&1 & pids+=("$!")
sleep 1
for id in 2222222222222222 3333333333333333; do
 node_json "$work/state.json" "$id" | client_outbound | jq --arg ca "$work/fullchain.pem" '.tls.certificate_path=$ca | {log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:18105}],outbounds:[.],route:{final:.tag}}' > "$work/client.json"
 "$CORE" check -c "$work/client.json"
 "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!; pids+=("$client_pid")
 sleep 1
 if ! curl --noproxy '' --silent --show-error --fail --max-time 15 --socks5-hostname 127.0.0.1:18105 -k https://127.0.0.1:18104/ > "$work/page"; then cat "$work/server.log" "$work/client.log"; exit 1; fi
 grep -q 's_server' "$work/page"
 kill "$client_pid"; wait "$client_pid" 2>/dev/null || true
 ok "real TLS-verified proxy connection $id"
done
# Several independent nodes of the same protocol: three of each, every one with
# its own port, credentials and inbound tag, accepted by the real core.
nodes='[]'
for i in 1 2 3; do
 pair=$("$CORE" generate reality-keypair)
 nodes=$(jq -c --arg i "$i" --arg private "$(awk '/PrivateKey:/{print $2}' <<< "$pair")" --arg public "$(awk '/PublicKey:/{print $2}' <<< "$pair")" \
  --arg uuid "$("$CORE" generate uuid)" --arg short "$(openssl rand -hex 8)" --arg password "$(openssl rand -hex 24)" --arg dir "$work" '. + [
  {id:("a00000000000000"+$i),name:("vless-"+$i),type:"vless",enabled:true,host:"127.0.0.1",port:(18120+($i|tonumber)),sni:"www.ctrip.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:$short},
  {id:("b00000000000000"+$i),name:("anytls-"+$i),type:"anytls",enabled:true,host:"127.0.0.1",port:(18123+($i|tonumber)),sni:"test.example.com",password:($password+"a"),cert_dir:$dir},
  {id:("c00000000000000"+$i),name:("hysteria2-"+$i),type:"hysteria2",enabled:true,host:"127.0.0.1",port:(18126+($i|tonumber)),sni:"test.example.com",password:($password+"h"),cert_dir:$dir}]' <<< "$nodes")
done
jq --argjson nodes "$nodes" '.nodes=$nodes' "$work/state.json" > "$work/multi.json"
render_config "$work/multi.json" > "$work/multi-server.json"
"$CORE" check -c "$work/multi-server.json"
jq -e '[.inbounds[]|.type]|group_by(.)|map(length)==[3,3,3]' "$work/multi-server.json" >/dev/null || exit 1
jq -e '[.inbounds[]|.tag]|length==9 and (unique|length)==9' "$work/multi-server.json" >/dev/null || exit 1
jq -e '[.inbounds[]|select(.type=="vless")|.users[0].uuid, .tls.reality.private_key, .tls.reality.short_id[0]]|unique|length==9' "$work/multi-server.json" >/dev/null || exit 1
ok 'three nodes of each protocol render to nine independent inbounds accepted by sing-box check'
"$CORE" run -c "$work/multi-server.json" > "$work/multi-server.log" 2>&1 & multi_pid=$!; pids+=("$multi_pid")
sleep 1
for id in b000000000000001 b000000000000002 b000000000000003 c000000000000001 c000000000000002 c000000000000003; do
 node_json "$work/multi.json" "$id" | client_outbound | jq --arg ca "$work/fullchain.pem" '.tls.certificate_path=$ca | {log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:18105}],outbounds:[.],route:{final:.tag}}' > "$work/client.json"
 "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!; pids+=("$client_pid")
 sleep 1
 if ! curl --noproxy '' --silent --show-error --fail --max-time 15 --socks5-hostname 127.0.0.1:18105 -k https://127.0.0.1:18104/ > "$work/page"; then cat "$work/multi-server.log" "$work/client.log"; exit 1; fi
 grep -q 's_server' "$work/page"
 kill "$client_pid"; wait "$client_pid" 2>/dev/null || true
done
# One node's credentials do not open another node of the same protocol.
node_json "$work/multi.json" b000000000000001 | jq '.port=18125' | client_outbound | jq --arg ca "$work/fullchain.pem" '.tls.certificate_path=$ca | {log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:18105}],outbounds:[.],route:{final:.tag}}' > "$work/client.json"
"$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!; pids+=("$client_pid")
sleep 1
if curl --noproxy '' --silent --fail --max-time 5 --socks5-hostname 127.0.0.1:18105 -k https://127.0.0.1:18104/ > /dev/null 2>&1; then echo 'FAIL node 1 password accepted by node 2'; exit 1; fi
kill "$client_pid" "$multi_pid"; wait "$client_pid" "$multi_pid" 2>/dev/null || true
ok 'real traffic through each of three AnyTLS and three Hysteria2 nodes; credentials are not shared'

# A rule limited to one node: traffic entering through that node's inbound goes
# to the proxy egress; the same domain through another node stays direct.
jq '.nodes=.nodes[0:2] | .egress={type:"socks",version:"5",server:"127.0.0.1",server_port:18111,username:"test",password:"test-password"} |
 .policies=[{name:"scoped",mode:"proxy",domains:["proxy.fixture.test"],inbounds:["1111111111111111"]}]' "$work/state.json" > "$work/scoped.json"
render_config "$work/scoped.json" > "$work/scoped-server.json"
"$CORE" check -c "$work/scoped-server.json"
jq -e '[.route.rules[]|select(.domain_suffix)]==[{inbound:["1111111111111111"],domain_suffix:["proxy.fixture.test"],action:"route",outbound:"media-proxy"}]
 and [.dns.rules[]|select(.domain_suffix)|.inbound]==[["1111111111111111"]]' "$work/scoped-server.json" >/dev/null || exit 1
cat > "$work/egress.json" <<'JSON'
{"log":{"level":"info"},"inbounds":[{"type":"socks","listen":"127.0.0.1","listen_port":18111,"users":[{"username":"test","password":"test-password"}]}],"dns":{"servers":[{"type":"hosts","tag":"hosts","predefined":{"proxy.fixture.test":"127.0.0.1"}}]},"outbounds":[{"type":"direct","tag":"direct"}],"route":{"default_domain_resolver":"hosts","final":"direct"}}
JSON
"$CORE" run -c "$work/egress.json" > "$work/egress.log" 2>&1 & egress_pid=$!; pids+=("$egress_pid")
# Same routing and DNS sections; the two node inbounds are swapped for local mixed
# inbounds with the same tags so curl can enter through either node. The local
# resolver gains the fixture name so the direct path can reach it too.
jq '.log.level="info" | .inbounds=[{type:"mixed",tag:"1111111111111111",listen:"127.0.0.1",listen_port:18110},{type:"mixed",tag:"2222222222222222",listen:"127.0.0.1",listen_port:18112}] |
 .dns.servers[0]={type:"hosts",tag:"local",predefined:{"proxy.fixture.test":"127.0.0.1"}}' "$work/scoped-server.json" > "$work/router.json"
"$CORE" run -c "$work/router.json" > "$work/router.log" 2>&1 & router_pid=$!; pids+=("$router_pid")
sleep 1
curl --noproxy '' -fsSk --max-time 10 --socks5-hostname 127.0.0.1:18110 https://proxy.fixture.test:18104/ | grep -q s_server || { cat "$work/router.log"; exit 1; }
[[ $(grep -c 'proxy.fixture.test:18104' "$work/egress.log") -ge 1 ]] || { cat "$work/router.log" "$work/egress.log"; exit 1; }
before=$(grep -c 'proxy.fixture.test:18104' "$work/egress.log")
curl --noproxy '' -fsSk --max-time 10 --socks5-hostname 127.0.0.1:18112 https://proxy.fixture.test:18104/ | grep -q s_server || { cat "$work/router.log"; exit 1; }
sleep 1
[[ $(grep -c 'proxy.fixture.test:18104' "$work/egress.log") == "$before" ]] || { echo 'FAIL rule leaked to another node'; cat "$work/egress.log"; exit 1; }
kill "$router_pid" "$egress_pid"; wait "$router_pid" "$egress_pid" 2>/dev/null || true
ok 'a rule limited to one node routes only that inbound; the same domain via another node stays direct'

for ip in 127.0.0.1 255.255.255.255 ::1 2001:db8::1 ::; do valid_ip "$ip"; done
for ip in 999.1.1.1 1.2.3 1.2.3.4.5 2001:::1 2001::1::2 2001:zzzz::1; do ! valid_ip "$ip" || exit 1; done
ok 'IPv4 and IPv6 address validation'

printf 'Passed %s checks.\n' "$pass"
