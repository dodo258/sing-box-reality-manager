#!/usr/bin/env bash
# Real traffic through every protocol added to the registry: the generated server
# configuration passes `sing-box check`, and a client built only from the node's
# client snippet fetches a local HTTP page through the node. Certificate nodes are
# trusted by CA file; self-signed nodes only by the pin in the snippet.
# TEST_MIHOMO=<mihomo binary> also runs every Clash Meta snippet through mihomo.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
need_core
CORE=${TEST_CORE:?set TEST_CORE to sing-box 1.14.1}
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
chgrp() { :; }
work=$(mktemp -d)
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
DATA=$work/data
mkdir -p "$DATA" "$work/www"
printf 'srm-traffic-ok\n' > "$work/www/index.html"

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$work/key.pem" -out "$work/fullchain.pem" -days 2 \
    -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com > /dev/null 2>&1
ca_sha256=$(openssl x509 -in "$work/fullchain.pem" -outform der | openssl dgst -sha256 | awk '{print $NF}')
# Self-signed certificates exactly as a deployment creates them.
id=5555555555555555 sni=$SELF_SIGNED_SNI; selfsigned_create || fail 'self-signed certificate'; tuic_self=$REPLY
id=6666666666666666 sni=$SELF_SIGNED_SNI; selfsigned_create || fail 'self-signed certificate'; hy_self=$REPLY
id=7777777777777777 sni=$SELF_SIGNED_SNI; selfsigned_create || fail 'self-signed certificate'; hy2_self=$REPLY
uuid() { "$CORE" generate uuid; }
jq -n --arg dir "$work" --arg ss "$(openssl rand -base64 16)" --argjson tuic "$tuic_self" --argjson hy "$hy_self" --argjson hy2 "$hy2_self" \
  --arg u1 "$(uuid)" --arg u2 "$(uuid)" --arg u3 "$(uuid)" --arg u4 "$(uuid)" --arg u5 "$(uuid)" --arg u6 "$(uuid)" --arg u7 "$(uuid)" --arg u8 "$(uuid)" '
  def cert: {sni:"test.example.com",cert_dir:$dir};
  def node($id; $name; $type; $port): {id:$id,name:$name,type:$type,enabled:true,host:"127.0.0.1",port:$port};
  {schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
    node("a000000000000001"; "ss 测试"; "shadowsocks"; 18201) + {method:"2022-blake3-aes-128-gcm",password:$ss},
    node("a000000000000002"; "tuic"; "tuic"; 18202) + cert + {uuid:$u1,password:"tuic-password"},
    node("5555555555555555"; "tuic-self"; "tuic"; 18203) + {sni:"www.bing.com",uuid:$u2,password:"tuic-password-2"} + $tuic,
    node("a000000000000004"; "vless-tcp"; "vlesstls"; 18204) + cert + {uuid:$u3,transport:"tcp"},
    node("a000000000000005"; "vless-ws"; "vlesstls"; 18205) + cert + {uuid:$u4,transport:"ws",path:"/a1b2c3d4"},
    node("a000000000000006"; "vless-grpc"; "vlesstls"; 18206) + cert + {uuid:$u5,transport:"grpc",service_name:"e5f6a7b8"},
    node("a000000000000007"; "vless-httpupgrade"; "vlesstls"; 18207) + cert + {uuid:$u6,transport:"httpupgrade",path:"/c9d0e1f2"},
    node("a000000000000008"; "trojan"; "trojan"; 18208) + cert + {password:"trojan-password"},
    node("a000000000000009"; "vmess"; "vmess"; 18209) + cert + {uuid:$u7,path:"/f3a4b5c6"},
    node("a00000000000000a"; "naive"; "naive"; 18210) + cert + {username:"0123456789ab",password:"naive-password"},
    node("a00000000000000b"; "hysteria"; "hysteria"; 18211) + cert + {password:"hysteria-password"},
    node("6666666666666666"; "hysteria-self"; "hysteria"; 18212) + {sni:"www.bing.com",password:"hysteria-password-2"} + $hy,
    node("7777777777777777"; "hysteria2-self"; "hysteria2"; 18213) + {sni:"www.bing.com",password:"hy2-password"} + $hy2,
    node("a00000000000000e"; "anytls"; "anytls"; 18214) + cert + {password:"anytls-password"}
  ]}' > "$work/state.json"
validate_state "$work/state.json" || fail 'state with every protocol rejected'
render_config "$work/state.json" > "$work/server.json"
"$CORE" check -c "$work/server.json" || fail 'sing-box check rejected the server configuration'
jq -e '[.inbounds[].type]|unique == ["anytls","hysteria","hysteria2","naive","shadowsocks","trojan","tuic","vless","vmess"]' "$work/server.json" >/dev/null || fail 'inbound types'
echo 'PASS every protocol renders a server configuration accepted by sing-box check'

# Waits up to 10 s until something accepts TCP connections on 127.0.0.1:PORT.
wait_port() {
    local i
    for ((i=0; i<50; i++)); do
        if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then return 0; fi
        sleep 0.2
    done
    return 1
}
python3 -m http.server 18299 --bind 127.0.0.1 --directory "$work/www" > "$work/http.log" 2>&1 & pids+=("$!")
"$CORE" run -c "$work/server.json" > "$work/server.log" 2>&1 & server_pid=$!; pids+=("$server_pid")
# The server starts every inbound together; UDP ones cannot be probed, so a TCP one
# stands in for all of them.
wait_port 18299 && wait_port 18214 || { cat "$work/server.log"; fail 'server did not start'; }
sleep 0.5
fetch_via() { curl --noproxy '' --silent --show-error --fail --max-time 10 --socks5-hostname "$1" http://127.0.0.1:18299/ 2>&1; }

# sing-box client: the node's outbound, plus the test CA for certificate nodes.
# Returns 0 when the page arrives, 1 when a valid, running client cannot fetch it,
# 2 when the client configuration fails `sing-box check`, 3 when the client exits.
run_singbox_client() {
    local node=$1 extra=${2:-.}
    printf '%s' "$node" | client_outbound | jq --arg ca "$work/fullchain.pem" "if .tls and (.tls.certificate_public_key_sha256|not) then .tls.certificate_path=\$ca else . end | $extra |
        {log:{level:\"warn\"},inbounds:[{type:\"mixed\",listen:\"127.0.0.1\",listen_port:18298}],outbounds:[.],route:{final:.tag}}" > "$work/client.json"
    "$CORE" check -c "$work/client.json" > "$work/client-check.log" 2>&1 || return 2
    "$CORE" run -c "$work/client.json" > "$work/client.log" 2>&1 & client_pid=$!; pids+=("$client_pid")
    wait_port 18298 || { kill "$client_pid" 2>/dev/null; wait "$client_pid" 2>/dev/null; return 3; }
    local rc=0 page
    page=$(fetch_via 127.0.0.1:18298) || rc=1
    [[ $rc == 0 && $page == srm-traffic-ok ]] || rc=1
    kill -0 "$client_pid" 2>/dev/null || rc=3
    kill "$client_pid" 2>/dev/null; wait "$client_pid" 2>/dev/null || true
    return "$rc"
}
# Fails the test unless the client ran and was refused (exactly 1), so a broken
# configuration or a crashed client never passes as "refused".
expect_refused() {
    local rc=0
    run_singbox_client "$@" || rc=$?
    [[ $rc == 1 ]] || { cat "$work/client-check.log" "$work/client.log"; fail "expected a refused connection, got rc=$rc for $(jq -r .name <<< "$1")"; }
}
for nid in $(jq -r '.nodes[].id' "$work/state.json"); do
    node=$(node_json "$work/state.json" "$nid")
    name=$(jq -r .name <<< "$node")
    rc=0; run_singbox_client "$node" || rc=$?
    # The naive client needs cronet: the Linux release ships libcronet.so next to
    # sing-box (CI extracts it); a build without it cannot dial naive. curl is no
    # substitute because the inbound insists on naive padding.
    if [[ $(jq -r .type <<< "$node") == naive ]] && { { [[ $rc == 3 ]] && grep -q 'cronet: library not found' "$work/client.log"; } ||
         { [[ $rc == 2 ]] && grep -q 'with_naive_outbound' "$work/client-check.log"; }; }; then
        skip_reason=$(cat "$work/client.log" "$work/client-check.log" | tr '\n' ' ')
        if [[ ${GITHUB_ACTIONS:-} == true ]]; then fail "naive client unavailable in CI: $skip_reason"; fi
        printf 'SKIP naive: this sing-box build cannot run the naive client: %s\n' "$skip_reason"
        continue
    fi
    [[ $rc == 0 ]] || { cat "$work/client-check.log" "$work/client.log" "$work/server.log"; fail "sing-box client through $name"; }
    printf 'PASS sing-box client fetches the local HTTP page through %s\n' "$name"
done

# A pin that does not match the server's certificate must not connect.
for nid in 5555555555555555 6666666666666666 7777777777777777; do
    node=$(node_json "$work/state.json" "$nid")
    expect_refused "$node" '.tls.certificate_public_key_sha256=["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="]'
done
# Without the pin, the self-signed certificate is rejected like any untrusted one.
node=$(node_json "$work/state.json" 5555555555555555)
expect_refused "$node" 'del(.tls.certificate_public_key_sha256)'
echo 'PASS self-signed nodes connect only with the pinned public key'

# Credentials are per node: another node's password does not open this one.
node=$(node_json "$work/state.json" a000000000000008 | jq '.password="anytls-password"')
expect_refused "$node"
node=$(node_json "$work/state.json" a000000000000001 | jq --arg k "$(openssl rand -base64 16)" '.password=$k')
expect_refused "$node"
echo 'PASS wrong credentials are refused'

if [[ -n ${TEST_MIHOMO:-} ]]; then
    # mihomo opens its ports before it starts routing and silently closes connections
    # that arrive in between (tunnel status not yet Running). A second inbound sent
    # DIRECT to the page shows when it routes, without going through the node.
    wait_mihomo_routing() {
        local i
        for ((i=0; i<50; i++)); do
            [[ $(fetch_via 127.0.0.1:18296) == srm-traffic-ok ]] && return 0
            sleep 0.2
        done
        return 1
    }
    for nid in $(jq -r '.nodes[].id' "$work/state.json"); do
        node=$(node_json "$work/state.json" "$nid")
        name=$(jq -r .name <<< "$node")
        proxy=$(printf '%s' "$node" | clash_proxy)
        if [[ -z $proxy ]]; then printf 'SKIP Clash Meta has no client for %s\n' "$name"; continue; fi
        # Certificate nodes are trusted by the test certificate's fingerprint.
        if [[ $(jq -r '.cert_sha256 // empty' <<< "$node") == '' && $(jq -r '.cert_dir // empty' <<< "$node") != '' ]]; then
            proxy="- $(jq -c --arg fp "$ca_sha256" '.fingerprint=$fp' <<< "${proxy#- }")"
        fi
        mkdir -p "$work/mihomo"
        printf 'mixed-port: 18297\nbind-address: 127.0.0.1\nmode: rule\nlog-level: warning\nipv6: false\nlisteners:\n  - {name: ready, type: mixed, listen: 127.0.0.1, port: 18296, proxy: DIRECT}\nproxies:\n  %s\nrules:\n  - MATCH,%s\n' \
            "$proxy" "$name" > "$work/mihomo/config.yaml"
        "$TEST_MIHOMO" -t -d "$work/mihomo" > "$work/mihomo-check.log" 2>&1 || { cat "$work/mihomo/config.yaml" "$work/mihomo-check.log"; fail "mihomo rejected the $name snippet"; }
        "$TEST_MIHOMO" -d "$work/mihomo" > "$work/mihomo.log" 2>&1 & mihomo_pid=$!; pids+=("$mihomo_pid")
        wait_port 18297 && wait_mihomo_routing || { cat "$work/mihomo.log"; fail "mihomo did not start for $name"; }
        page=$(fetch_via 127.0.0.1:18297) || true
        kill "$mihomo_pid"; wait "$mihomo_pid" 2>/dev/null || true
        [[ $page == srm-traffic-ok ]] || { cat "$work/mihomo/config.yaml" "$work/mihomo.log"; printf '%s\n' "$page"; fail "mihomo through $name"; }
        printf 'PASS mihomo (Clash Meta snippet) fetches the page through %s\n' "$name"
    done
else
    skip_or_fail 'mihomo client checks need TEST_MIHOMO'
fi
