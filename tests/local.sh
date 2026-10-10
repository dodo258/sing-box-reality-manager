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
for port in 10000 33524 50000; do valid_port "$port"; done
for port in 9999 50001 65535 01000 '1;id' ''; do ! valid_port "$port" || exit 1; done
ok 'port boundaries and invalid input'
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
jq -n --arg dir "$work" --arg private "$private" --arg public "$public" --arg uuid "$uuid" '{schema:1,nodes:[
 {id:"1111111111111111",name:"Reality 测试",type:"vless",enabled:true,host:"127.0.0.1",port:18101,sni:"www.microsoft.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"},
 {id:"2222222222222222",name:"AnyTLS 测试",type:"anytls",enabled:true,host:"127.0.0.1",port:18102,sni:"test.example.com",password:"test_password_with_32_characters_1234",cert_dir:$dir},
 {id:"3333333333333333",name:"Hysteria2 测试",type:"hysteria2",enabled:true,host:"127.0.0.1",port:18103,sni:"test.example.com",password:"test_password_with_32_characters_1234",cert_dir:$dir}
],policies:[],unlock_dns:null,egress:null}' > "$work/state.json"
render_config "$work/state.json" > "$work/server.json"
"$CORE" check -c "$work/server.json"
ok 'all three protocol configurations accepted by real core'
for mutation in '.nodes[1].port=.nodes[0].port' '.nodes[1].id=.nodes[0].id' '.nodes[0].port=50001' '.nodes[0].type="vmess"' '.nodes[0].name="bad\nname"' '.policies=[{name:"x",mode:"dns",domains:["netflix.com"]}]'; do
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
for ip in 127.0.0.1 255.255.255.255 ::1 2001:db8::1 ::; do valid_ip "$ip"; done
for ip in 999.1.1.1 1.2.3 1.2.3.4.5 2001:::1 2001::1::2 2001:zzzz::1; do ! valid_ip "$ip" || exit 1; done
ok 'IPv4 and IPv6 address validation'

printf 'Passed %s checks.\n' "$pass"
