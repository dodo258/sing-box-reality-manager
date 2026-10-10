#!/usr/bin/env bash
# Run only on the explicitly authorized coexistence test server, after backup.
set -euo pipefail
source "$(dirname -- "$0")/support/guard.sh"
need_workspace
source "$TEST_WORKSPACE/srm"
umask 077
work=$TEST_WORKSPACE/integration
mkdir -p "$work"
for p in 18101 18102 18103 18104 18105 18106 40529; do port_free "$p" || { err "测试端口 $p 不空闲。"; exit 1; }; done
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$work/key.pem" -out "$work/fullchain.pem" -days 2 -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com > "$work/openssl.log" 2>&1
activate_cert test.example.com "$work"
pair=$("$CORE" generate reality-keypair)
private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
uuid=$("$CORE" generate uuid)
password=$(random_hex 24)
jq -n --arg host "${TEST_SERVER_HOST:-127.0.0.1}" --arg dir "$DATA/certs/test.example.com/active" --arg private "$private" --arg public "$public" --arg uuid "$uuid" --arg password "$password" '{schema:2,nodes:[
 {id:"1111111111111111",name:"test-reality",type:"vless",enabled:true,host:$host,port:18101,sni:"www.microsoft.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"},
 {id:"2222222222222222",name:"test-anytls",type:"anytls",enabled:true,host:$host,port:40529,sni:"test.example.com",password:$password,cert_dir:$dir},
 {id:"3333333333333333",name:"test-hysteria2",type:"hysteria2",enabled:true,host:$host,port:18103,sni:"test.example.com",password:$password,cert_dir:$dir}
],policies:[],unlock_dns:null,egress:null}' > "$work/state.json"
with_lock apply_state "$work/state.json"
echo 'PASS isolated systemd service with three inbounds'
openssl s_server -accept 18104 -cert "$work/fullchain.pem" -key "$work/key.pem" -www > "$work/target.log" 2>&1 & target_pid=$!
client_pid=''
trap '[[ -z $client_pid ]] || kill "$client_pid" 2>/dev/null || true; kill "$target_pid" 2>/dev/null || true' EXIT
for id in 1111111111111111 2222222222222222 3333333333333333; do
 node_json "$STATE" "$id" | jq '.host="127.0.0.1"' | client_outbound | jq --arg ca "$work/fullchain.pem" '. + (if .type!="vless" then {tls:(.tls+{certificate_path:$ca})} else {} end) | {log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:18105}],outbounds:[.],route:{final:.tag}}' > "$work/client.json"
 "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!
 sleep 1
 if ! curl --noproxy '' --silent --show-error --fail --max-time 20 --socks5-hostname 127.0.0.1:18105 -k https://127.0.0.1:18104/ > "$work/page"; then cat "$work/client.log"; exit 1; fi
 grep -q s_server "$work/page"
 kill "$client_pid"; wait "$client_pid" 2>/dev/null || true; client_pid=''
 echo "PASS real client traffic: $id"
done
old=$(readlink "$DATA/current")
jq '.nodes[0].port=80' "$STATE" > "$work/bad.json"
if with_lock apply_state "$work/bad.json"; then echo 'FAIL invalid port accepted'; exit 1; fi
[[ $(readlink "$DATA/current") == "$old" ]] || exit 1
echo 'PASS invalid input leaves active state unchanged'
# Bind failure after syntax validation must roll back automatically.
jq '.nodes[0].port=18104' "$STATE" > "$work/conflict.json"
if with_lock apply_state "$work/conflict.json"; then echo 'FAIL bind conflict accepted'; exit 1; fi
[[ $(readlink "$DATA/current") == "$old" ]] || exit 1
systemctl is-active --quiet "$SERVICE"
echo 'PASS runtime failure rollback'
with_lock node_change 3333333333333333 toggle
jq -e '.nodes[]|select(.id=="3333333333333333")|.enabled==false' "$STATE" >/dev/null
with_lock node_change 3333333333333333 toggle
echo 'PASS disable/enable node'
with_lock node_change 3333333333333333 name '测试中文 & name'
node_json "$STATE" 3333333333333333 | share_uri | grep -q '%E6%B5%8B%E8%AF%95'
echo 'PASS rename and encoded raw URL'
# Original services must remain exactly as they were.
sha256sum -c $TEST_WORKSPACE/config-hashes.before > "$work/hash-check.log"
read -ra services <<< "${TEST_SERVICES:?set TEST_SERVICES to the existing services that must stay untouched}"
systemctl show "${services[@]}" -p Id -p MainPID -p ActiveEnterTimestamp > "$work/services.after"
cmp $TEST_WORKSPACE/services.before "$work/services.after"
echo 'PASS original configuration hashes and service PIDs unchanged'
