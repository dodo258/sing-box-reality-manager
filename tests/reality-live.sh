#!/usr/bin/env bash
# Optional Linux test: contacts the two public targets, binds only loopback,
# and never changes services, system configuration or firewall rules.
set -euo pipefail
[[ ${TEST_REALITY_LIVE:-} == 1 && -n ${TEST_CORE:-} ]] || { echo 'SKIP reality-live.sh：联网测试，设置 TEST_REALITY_LIVE=1 和 TEST_CORE 后运行'; exit 0; }
source "${TEST_BUNDLE:-$(dirname -- "$0")/../dist/srm}"
CORE=${TEST_CORE:?set TEST_CORE to a verified sing-box binary}
umask 077
work=$(mktemp -d)
STATE=$work/state.json
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
server_port=$(choose_port)
client_port=$(choose_port)
while [[ $client_port == "$server_port" ]]; do client_port=$(choose_port); done
pair=$("$CORE" generate reality-keypair)
private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
uuid=$("$CORE" generate uuid)
for domain in www.ctrip.com www.ixigua.com; do
    reality_target_check "$domain"
    jq -n --arg sni "$domain" --arg private "$private" --arg public "$public" --arg uuid "$uuid" \
      --argjson port "$server_port" '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
      {id:"1111111111111111",name:"Reality test",type:"vless",enabled:true,host:"127.0.0.1",port:$port,sni:$sni,uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"}]}' > "$STATE"
    render_config "$STATE" | jq '.inbounds[].listen="127.0.0.1"' > "$work/server.json"
    node_json "$STATE" 1111111111111111 | client_outbound | jq --argjson port "$client_port" \
      '{log:{level:"warn"},inbounds:[{type:"mixed",listen:"127.0.0.1",listen_port:$port}],outbounds:[.],route:{final:.tag}}' > "$work/client.json"
    "$CORE" check -c "$work/server.json"
    "$CORE" check -c "$work/client.json"
    "$CORE" run -c "$work/server.json" > "$work/server.log" 2>&1 & server_pid=$!; pids+=("$server_pid")
    "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!; pids+=("$client_pid")
    sleep 1
    curl --noproxy '' --fail --silent --show-error --max-time 30 \
      --socks5-hostname "127.0.0.1:$client_port" https://example.com/ > "$work/page"
    grep -qi 'Example Domain' "$work/page"
    kill "$client_pid" "$server_pid"
    wait "$client_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    pids=()
    printf 'PASS %s: real Reality client → loopback server → verified HTTPS request\n' "$domain"
done
