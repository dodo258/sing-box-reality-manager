#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "$0")/support/guard.sh"
need_workspace
source "$TEST_WORKSPACE/srm"
umask 077
work=$TEST_WORKSPACE/routing
mkdir -p "$work"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
for p in 18104 18110 18111; do port_free "$p" || exit 1; done
[[ -z $(ss -H -lun 'sport = :53' | awk '$4 == "127.0.0.2:53"') ]] || exit 1
cat > "$work/dns.json" <<'JSON'
{"log":{"level":"info"},"inbounds":[{"type":"direct","listen":"127.0.0.2","listen_port":53,"network":"udp"}],"dns":{"servers":[{"type":"local","tag":"local"}],"rules":[{"query_type":"A","action":"predefined","answer":["media.fixture.test. IN A 127.0.0.1"]},{"action":"predefined","rcode":"NOERROR"}]},"route":{"rules":[{"action":"hijack-dns"}]}}
JSON
"$CORE" check -c "$work/dns.json"
"$CORE" run -c "$work/dns.json" > "$work/dns.log" 2>&1 & pids+=("$!")
openssl s_server -accept 18104 -cert "$DATA/certs/test.example.com/active/fullchain.pem" -key "$DATA/certs/test.example.com/active/key.pem" -www > "$work/target.log" 2>&1 & pids+=("$!")
jq '.unlock_dns="127.0.0.2"|.policies=[{name:"fixture",mode:"dns",domains:["media.fixture.test"]}]' "$STATE" > "$work/state.json"
render_config "$work/state.json" | jq '.log.level="info"|.inbounds=[{type:"mixed",listen:"127.0.0.1",listen_port:18110}]' > "$work/router.json"
"$CORE" run -c "$work/router.json" > "$work/router.log" 2>&1 & router_pid=$!; pids+=("$router_pid")
sleep 1
curl --noproxy '' -fsSk --max-time 10 --socks5-hostname 127.0.0.1:18110 https://media.fixture.test:18104/ > "$work/dns-page"
grep -q s_server "$work/dns-page"
echo 'PASS selected domain resolved by unlock DNS and connected to returned address'
curl --noproxy '' -fsSk --max-time 10 --socks5-hostname 127.0.0.1:18110 https://localhost:18104/ > "$work/local-page"
grep -q s_server "$work/local-page"
! grep -q 'localhost' "$work/dns.log" || exit 1
echo 'PASS unselected domain uses normal local resolver'
# sing-box 1.14 resolve acts only on a domain destination, not an IP plus SNI.
# Verify and document the boundary instead of pretending DNS unlock covers it.
if curl --noproxy '' -fsSk --max-time 3 --socks5 127.0.0.1:18110 --resolve media.fixture.test:18104:203.0.113.11 https://media.fixture.test:18104/ > "$work/sniff-page" 2>/dev/null; then
 echo 'FAIL unexpectedly replaced IP destination'; exit 1
fi
grep -q 'outbound connection to 203.0.113.11:18104' "$work/router.log"
echo 'PASS documented boundary: DNS-only requires domain destination or client DNS through this server'
kill "$router_pid"; wait "$router_pid" 2>/dev/null || true
# An authenticated proxy records whether only selected requests arrive.
cat > "$work/egress.json" <<'JSON'
{"log":{"level":"info"},"inbounds":[{"type":"socks","listen":"127.0.0.1","listen_port":18111,"users":[{"username":"test","password":"test-password"}]}],"dns":{"servers":[{"type":"hosts","tag":"hosts","predefined":{"proxy.fixture.test":"127.0.0.1"}},{"type":"local","tag":"local"}]},"outbounds":[{"type":"direct","tag":"direct"}],"route":{"default_domain_resolver":"hosts","final":"direct"}}
JSON
"$CORE" run -c "$work/egress.json" > "$work/egress.log" 2>&1 & egress_pid=$!; pids+=("$egress_pid")
jq '.egress={type:"socks",version:"5",server:"127.0.0.1",server_port:18111,username:"test",password:"test-password"}|.policies=[{name:"fixture",mode:"proxy",domains:["proxy.fixture.test"]}]' "$STATE" > "$work/state.json"
render_config "$work/state.json" | jq '.log.level="info"|.inbounds=[{type:"mixed",listen:"127.0.0.1",listen_port:18110}]' > "$work/router.json"
"$CORE" run -c "$work/router.json" > "$work/router2.log" 2>&1 & router_pid=$!; pids+=("$router_pid")
sleep 1
curl --noproxy '' -fsSk --max-time 10 --socks5-hostname 127.0.0.1:18110 https://proxy.fixture.test:18104/ > "$work/proxy-page"
grep -q s_server "$work/proxy-page"
grep -q 'proxy.fixture.test:18104' "$work/egress.log"
curl --noproxy '' -fsSk --max-time 10 --socks5-hostname 127.0.0.1:18110 https://localhost:18104/ > "$work/direct-page"
grep -q s_server "$work/direct-page"
! grep -q 'localhost' "$work/egress.log" || exit 1
echo 'PASS selected platform uses proxy; ordinary traffic stays direct'
kill "$egress_pid"; wait "$egress_pid" 2>/dev/null || true
if curl --noproxy '' -fsSk --max-time 4 --socks5-hostname 127.0.0.1:18110 https://proxy.fixture.test:18104/ >/dev/null 2>&1; then echo 'FAIL proxy silently fell back'; exit 1; fi
curl --noproxy '' -fsSk --max-time 4 --socks5-hostname 127.0.0.1:18110 https://localhost:18104/ > /dev/null
echo 'PASS failed proxy does not fall back and does not break ordinary traffic'
