#!/usr/bin/env bash
# Real traffic through Snell behind ShadowTLS: the official snell-server (v6 default,
# v6 unshaped, v5) runs from the configuration a generation gets, sing-box serves the
# ShadowTLS front end from the rendered configuration, and clients built only from
# the node's snippets fetch a local HTTP page: the sing-box client for every node,
# mihomo (Clash Meta snippet) for v5. The ShadowTLS handshake goes to a local TLS 1.3
# server standing in for the real site, with a test certificate for its name.
# Needs TEST_CORE, TEST_SNELL_V6 and TEST_SNELL_V5 (CI downloads them with
# snell_download); TEST_MIHOMO adds the mihomo client.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
need_core
[[ -n ${TEST_SNELL_V6:-} && -n ${TEST_SNELL_V5:-} ]] || skip_or_fail "${0##*/}：需要 TEST_SNELL_V6 / TEST_SNELL_V5 指向 snell-server（只有 Linux 版）"
CORE=$TEST_CORE
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
chgrp() { :; }
work=$(mktemp -d)
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
SRM_ROOT=$work/root
DATA=$work/data
mkdir -p "$SRM_ROOT/snell/v6" "$SRM_ROOT/snell/v5" "$DATA" "$work/www" "$work/gen"
install -m 755 "$TEST_SNELL_V6" "$SRM_ROOT/snell/v6/snell-server"
install -m 755 "$TEST_SNELL_V5" "$SRM_ROOT/snell/v5/snell-server"
printf 'srm-snell-ok\n' > "$work/www/index.html"
wait_port() {
    local i
    for ((i=0; i<50; i++)); do
        if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then return 0; fi
        sleep 0.2
    done
    return 1
}

# The handshake site: TLS 1.3 with a test certificate for the node's target name.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 2 \
    -subj /CN=www.ctrip.com -addext subjectAltName=DNS:www.ctrip.com > /dev/null 2>&1
openssl s_server -quiet -accept 18443 -tls1_3 -cert "$work/cert.pem" -key "$work/key.pem" -www > "$work/handshake.log" 2>&1 & pids+=("$!")
python3 -m http.server 18399 --bind 127.0.0.1 --directory "$work/www" > "$work/http.log" 2>&1 & pids+=("$!")

jq -n --arg a "$(random_hex 16)" --arg b "$(random_hex 16)" --arg c "$(random_hex 16)" --arg d "$(random_hex 16)" '
  def node($id; $name; $port; $lp; $psk; $pw): {id:$id,name:$name,type:"snell",enabled:true,host:"127.0.0.1",port:$port,
    sni:"www.ctrip.com",psk:$psk,shadowtls_password:$pw,local_port:$lp};
  {schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
    node("5000000000000001"; "snell-v6"; 18301; 18311; $a; $b) + {snell_version:6,snell_mode:"default"},
    node("5000000000000002"; "snell-v6-unshaped"; 18302; 18312; $c; $b) + {snell_version:6,snell_mode:"unshaped"},
    node("5000000000000003"; "snell-v5"; 18303; 18313; $d; $a) + {snell_version:5}
  ]}' > "$work/state.json"
validate_state "$work/state.json" || fail 'state rejected'
# Exactly what apply_state does: rendered configuration, `sing-box check`, helper files.
render_config "$work/state.json" | jq '.inbounds |= map(if .type == "shadowtls" then .handshake = {server:"127.0.0.1",server_port:18443} else . end)' > "$work/server.json"
"$CORE" check -c "$work/server.json" || fail 'sing-box check rejected the ShadowTLS front end'
sidecar_render "$work/state.json" "$work/gen" || fail 'snell-server configuration'
echo 'PASS the ShadowTLS front end passes sing-box check and every node gets its snell-server configuration'

# snell-server starts exactly as the unit starts it: the generation's link and config.
for id in 5000000000000001 5000000000000002 5000000000000003; do
    "$work/gen/sidecar/$id/snell-server" -c "$work/gen/sidecar/$id/snell.conf" > "$work/snell-$id.log" 2>&1 & pids+=("$!")
done
for port in 18311 18312 18313; do wait_port "$port" || { cat "$work"/snell-*.log; fail "snell-server did not listen on $port"; }; done
grep -q 'snell-server v6\.' "$work/snell-5000000000000001.log" && grep -q 'Encryption mode: unshaped' "$work/snell-5000000000000002.log" &&
    grep -q 'snell-server v5\.' "$work/snell-5000000000000003.log" || { cat "$work"/snell-*.log; fail 'snell-server versions / mode'; }
# Loopback only: nothing answers on another local address.
if ss -H -ltn 'sport = :18311' | grep -vq '127.0.0.1:18311'; then fail 'snell-server listens beyond loopback'; fi
echo 'PASS snell-server v6 (default, unshaped) and v5 start from the generation and listen on loopback only'

"$CORE" run -c "$work/server.json" > "$work/server.log" 2>&1 & pids+=("$!")
for port in 18301 18302 18303 18399 18443; do wait_port "$port" || { cat "$work/server.log"; fail "port $port not listening"; }; done
# Without the ShadowTLS password the port is the handshake site: a plain TLS client
# completes TLS 1.3 and sees the site's certificate.
openssl s_client -connect 127.0.0.1:18301 -servername www.ctrip.com -tls1_3 -verify_return_error -CAfile "$work/cert.pem" < /dev/null > "$work/probe.log" 2>&1 ||
    { cat "$work/probe.log"; fail 'TLS handshake on the ShadowTLS port'; }
grep -qE '^subject= ?CN ?= ?www.ctrip.com' "$work/probe.log" && grep -q 'TLSv1.3' "$work/probe.log" || { cat "$work/probe.log"; fail 'handshake site certificate'; }
echo 'PASS a TLS 1.3 handshake on the ShadowTLS port completes with the handshake site certificate'

fetch_via() { curl --noproxy '' --silent --show-error --fail --max-time 10 --socks5-hostname "$1" http://127.0.0.1:18399/ 2>&1; }
# sing-box client from the node's two outbounds; returns 0 when the page arrives,
# 1 when the running client cannot fetch it, 2 on a rejected configuration.
run_client() {
    local node=$1 extra=${2:-.} rc=0 page
    printf '%s' "$node" | client_outbound | jq --arg ca "$work/cert.pem" "map(if .type == \"shadowtls\" then .tls.certificate_path = \$ca else . end) | $extra |
        {log:{level:\"warn\"},inbounds:[{type:\"mixed\",listen:\"127.0.0.1\",listen_port:18398}],outbounds:.,route:{final:.[0].tag}}" > "$work/client.json"
    "$CORE" check -c "$work/client.json" > "$work/client-check.log" 2>&1 || return 2
    "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!; pids+=("$client_pid")
    wait_port 18398 || { kill "$client_pid" 2>/dev/null; return 2; }
    page=$(fetch_via 127.0.0.1:18398) || rc=1
    [[ $rc == 0 && $page == srm-snell-ok ]] || rc=1
    kill "$client_pid" 2>/dev/null; wait "$client_pid" 2>/dev/null || true
    return "$rc"
}
for id in 5000000000000001 5000000000000002 5000000000000003; do
    node=$(node_json "$work/state.json" "$id")
    rc=0; run_client "$node" || rc=$?
    [[ $rc == 0 ]] || { cat "$work/client-check.log" "$work/client.log" "$work/server.log" "$work/snell-$id.log"; fail "sing-box client through $(jq -r .name <<< "$node")"; }
    printf 'PASS sing-box client (snell %s + shadowtls v3) fetches the page through %s\n' \
        "$(printf '%s' "$node" | client_outbound | jq -r '.[0].version')" "$(jq -r .name <<< "$node")"
done
# Wrong ShadowTLS password, wrong PSK, or a v6 mode the server does not use: refused.
node=$(node_json "$work/state.json" 5000000000000001)
for extra in '.[1].password = "0000000000000000"' '.[0].psk = "00000000000000000000000000000000"' '.[0].mode = "unshaped"'; do
    rc=0; run_client "$node" "$extra" || rc=$?
    [[ $rc == 1 ]] || { cat "$work/client-check.log" "$work/client.log"; fail "expected refusal (rc=$rc) with $extra"; }
done
echo 'PASS a wrong ShadowTLS password, PSK or v6 mode is refused'

if [[ -n ${TEST_MIHOMO:-} ]]; then
    node=$(node_json "$work/state.json" 5000000000000003)
    proxy=$(printf '%s' "$node" | clash_proxy)
    [[ -n $proxy ]] || fail 'no Clash Meta snippet for v5'
    mkdir -p "$work/mihomo"
    printf 'mixed-port: 18397\nbind-address: 127.0.0.1\nmode: rule\nlog-level: warning\nipv6: false\nproxies:\n  %s\nrules:\n  - MATCH,snell-v5\n' "$proxy" > "$work/mihomo/config.yaml"
    "$TEST_MIHOMO" -t -d "$work/mihomo" > "$work/mihomo-check.log" 2>&1 || { cat "$work/mihomo/config.yaml" "$work/mihomo-check.log"; fail 'mihomo rejected the Snell v5 snippet'; }
    # mihomo trusts the stand-in handshake site through the system certificate path.
    SSL_CERT_FILE=$work/cert.pem "$TEST_MIHOMO" -d "$work/mihomo" > "$work/mihomo.log" 2>&1 & mihomo_pid=$!; pids+=("$mihomo_pid")
    wait_port 18397 || { cat "$work/mihomo.log"; fail 'mihomo did not start'; }
    page=$(fetch_via 127.0.0.1:18397) || page=''
    kill "$mihomo_pid"; wait "$mihomo_pid" 2>/dev/null || true
    [[ $page == srm-snell-ok ]] || { cat "$work/mihomo/config.yaml" "$work/mihomo.log" "$work/server.log" "$work/snell-5000000000000003.log"; fail 'mihomo through snell-v5'; }
    echo 'PASS mihomo (Clash Meta snippet: snell v5 + shadow-tls v3) fetches the page through snell-v5'
else
    skip_or_fail 'mihomo client check needs TEST_MIHOMO'
fi
