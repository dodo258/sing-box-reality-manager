#!/usr/bin/env bash
# Changing settings never invalidates what clients already imported: one node of every
# protocol goes through port, name, disable / enable, port hopping, handshake target
# and a core replacement, and keeps uuid, password, keys, short_id, PSK and certificate
# pins, in the state, the generated configuration, the Snell configuration and the
# certificate files. Only rotate gives new credentials. Nodes moved from v3 are
# covered in tests/migrate.sh. The configuration transaction is srm's own
# (apply_state with sing-box check); systemctl, the firewall and the health check
# only record or pass, so this runs without root.
# Assertions use `|| fail` because `! cmd` never trips set -e, and bash 3.2
# (macOS) also ignores a failing [[ ]].
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
need_core
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/current/state.json
CORE=$SRM_ROOT/core/sing-box
mkdir -p "$SRM_ROOT/core" "$SRM_ROOT/snell/v6" "$SRM_ROOT/snell/v5" "$DATA/generations" "$work/tls"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
cp "$TEST_CORE" "$CORE"
printf '#!/bin/sh\n' > "$SRM_ROOT/snell/v6/snell-server"
cp "$SRM_ROOT/snell/v6/snell-server" "$SRM_ROOT/snell/v5/snell-server"
chmod 755 "$SRM_ROOT/snell/v6/snell-server" "$SRM_ROOT/snell/v5/snell-server"
systemctl() { printf '%s\n' "$*" >> "$work/systemctl"; }
ss() { return 0; }
chgrp() { :; }
service_unit_write() { return 0; }
service_healthy() { return 0; }
firewall_sync() { return 0; }
hop_tools_ready() { return 0; }
snell_install() { return 0; }
# A fixed loopback port for Snell, clear of the node ports below; it sits in the first
# block port hopping would take, so the default range moves on to the next one.
snell_local_port() { printf '20500\n'; }
reality_target_check() { REPLY=30; }
# The generation switch uses GNU mv -T; macOS mv does the same with -h.
if ! command mv --version >/dev/null 2>&1; then
    mv() { if [[ $1 == -Tf ]]; then command mv -hf "$2" "$3"; else command mv "$@"; fi; }
fi
# Domain certificates as srm keeps them; issuing them is tested elsewhere.
activate_cert() { mkdir -p "$DATA/certs/$1/active"; cp "$2/fullchain.pem" "$2/key.pem" "$DATA/certs/$1/active/"; }

# One node of each protocol through its own create hook, as deploying makes it:
# domain certificates for the protocols that need one, self-signed ones (pinned by
# clients) for the others that can use them.
nodes='[]'
port=31000
for type in $PROTOCOLS; do
    port=$((port+10))
    id=$(printf '%016x' "$port")
    sni='' mode=none cert='' key='' stream='' proto_version='' proto_mode='' hop_range='' email='' webroot=''
    case $(proto_call "$type" domain) in
      required) sni=$type.example.com mode=import
        cert=$work/tls/$sni.crt key=$work/tls/$sni.key
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -subj "/CN=$sni" -addext "subjectAltName=DNS:$sni" \
            -keyout "$key" -out "$cert" >/dev/null 2>&1;;
      optional) sni=$SELF_SIGNED_SNI mode=selfsigned;;
      none) [[ $type == shadowsocks ]] || sni=www.python.org;;
    esac
    case $type in vlesstls) stream=ws;; snell) proto_version=6 proto_mode=default;; esac
    REPLY=''
    proto_call "$type" create > /dev/null || fail "create $type"
    nodes=$(jq -c --arg id "$id" --arg type "$type" --argjson port "$port" --arg sni "$sni" --argjson fields "$REPLY" \
        '. + [{id:$id,name:$type,type:$type,enabled:true,host:"192.0.2.10",port:$port} + (if $sni == "" then {} else {sni:$sni} end) + $fields]' <<< "$nodes")
done
jq -n --argjson nodes "$nodes" '{schema:2,nodes:$nodes,policies:[],unlock_dns:null,egress:null}' > "$work/initial.json"
apply_state "$work/initial.json" > /dev/null || fail 'first apply'
ids=$(jq -r '.nodes[].id' "$STATE")
[[ $(wc -l <<< "$ids") -eq $(wc -w <<< "$PROTOCOLS") ]] || fail 'one node per protocol'
jq -e 'any(.nodes[]; .cert_sha256) and any(.nodes[]; .cert_dir and (.cert_sha256|not)) and any(.nodes[]; .private_key) and any(.nodes[]; .psk)' "$STATE" >/dev/null || fail 'node kinds'

# What clients depend on, besides the address, port and name. Each node's credential
# fields in the state and the hashes of its certificate files; each inbound's users,
# password, method and Reality key of the running configuration; each Snell
# configuration. CREDENTIALS lists the fields; other fields count as well (below).
CREDENTIALS='uuid password username private_key public_key short_id psk shadowtls_password method cert_sha256 pubkey_sha256 path service_name early_data snell_version snell_mode local_port cert_dir'
credentials() {
    local id dir files='{}' conf='{}'
    for id in $(jq -r '.nodes[].id' "$STATE"); do
        dir=$(jq -r --arg id "$id" '.nodes[]|select(.id == $id)|.cert_dir // empty' "$STATE")
        [[ -z $dir ]] || files=$(jq -c --arg id "$id" --arg c "$(sha256 "$dir/fullchain.pem")" --arg k "$(sha256 "$dir/key.pem")" '. + {($id):[$c,$k]}' <<< "$files")
    done
    for dir in "$DATA"/current/sidecar/*; do
        [[ -d $dir ]] || continue
        conf=$(jq -c --arg id "${dir##*/}" --arg c "$(grep -v '^listen' "$dir/snell.conf")" '. + {($id):$c}' <<< "$conf")
    done
    jq -c --arg fields "$CREDENTIALS" --argjson files "$files" --argjson conf "$conf" --slurpfile config "$DATA/current/config.json" '
      ($fields|split(" ")) as $f |
      {state:[.nodes[]|{id} + with_entries(select(.key as $k|any($f[]; . == $k)))],
       files:$files, snell:$conf,
       config:[$config[0].inbounds[]|{tag,users,password,method,reality:.tls.reality.private_key,short_id:.tls.reality.short_id,certificate:.tls.certificate_path}]}' "$STATE"
}
# What a client imported for node ID, without its port and name: the sing-box outbound.
client_view() {
    node_json "$STATE" "$1" | client_outbound | jq -c 'walk(if type == "object" then del(.tag, .detour, .server_port, .server_ports) else . end)'
}
# STATE equals the file BEFORE except the fields FIELD… of node ID.
same_except() {
    jq -e -n --slurpfile a "$1" --slurpfile b "$STATE" --arg id "$2" '$ARGS.positional as $f |
      def strip: .nodes |= map(if .id == $id then delpaths([$f[]|[.]]) else . end);
      ($a[0]|strip) == ($b[0]|strip)' --args "${@:3}" >/dev/null
}
# Remembers the state, credentials and client view of node ID before an operation.
before() { cp "$STATE" "$work/before.json"; credentials > "$work/before.creds"; client_view "$1" > "$work/before.view"; }
# After an operation on ID that changed only FIELD…: everything else is as before.
kept() {
    local id=$1 what=$2
    shift 2
    same_except "$work/before.json" "$id" "$@" || { diff <(jq -S . "$work/before.json") <(jq -S . "$STATE") || true; fail "$what changed other fields of $(jq -r --arg id "$id" '.nodes[]|select(.id == $id)|.type' "$STATE")"; }
    [[ $(credentials) == "$(cat "$work/before.creds")" ]] || { diff <(jq -S . "$work/before.creds") <(credentials | jq -S .) || true; fail "$what changed credentials"; }
    [[ $(client_view "$id") == "$(cat "$work/before.view")" ]] || fail "$what changed the client configuration of $id"
}
# The comparison sees every kind of credential: each node's own, the certificate files,
# the inbounds of the running configuration with Reality key and short_id, Snell's PSK.
credentials | jq -e --argjson n "$(wc -l <<< "$ids")" '(.state|length) == $n and all(.state[]; length > 2) and (.files|length) == ([.state[]|select(.cert_dir)]|length) and
  (.config|length) == $n + 1 and any(.config[]; .reality and .short_id) and (.snell[]|test("psk = [a-f0-9]{32}"))' >/dev/null ||
    { credentials | jq .; fail 'credentials snapshot incomplete'; }
for id in $ids; do
    type=$(node_json "$STATE" "$id" | jq -r .type)
    port=$(node_json "$STATE" "$id" | jq -r .port)
    before "$id"
    node_change "$id" port "$((port+1))" > /dev/null || fail "port of $type"
    node_json "$STATE" "$id" | jq -e --argjson p "$((port+1))" '.port == $p' >/dev/null || fail "port of $type not set"
    kept "$id" 'changing the port' port

    before "$id"
    node_change "$id" name "改名 $type" > /dev/null || fail "name of $type"
    node_json "$STATE" "$id" | jq -e --arg n "改名 $type" '.name == $n' >/dev/null || fail "name of $type not set"
    kept "$id" 'renaming' name

    before "$id"
    link=$(node_json "$STATE" "$id" | share_uri)
    node_change "$id" toggle > /dev/null || fail "disable $type"
    node_json "$STATE" "$id" | jq -e '.enabled == false' >/dev/null || fail "$type not disabled"
    same_except "$work/before.json" "$id" enabled || fail "disabling changed fields of $type"
    jq -e --arg id "$id" 'all(.inbounds[]; .tag != $id)' "$DATA/current/config.json" >/dev/null || fail "$type still served while disabled"
    node_change "$id" toggle > /dev/null || fail "enable $type"
    kept "$id" 'disabling and enabling' enabled
    cmp -s "$work/before.json" "$STATE" || fail "disabling and enabling $type did not give the same node back"
    [[ $(node_json "$STATE" "$id" | share_uri) == "$link" ]] || fail "share link of $type changed by disabling and enabling"
done
echo "PASS port, name, disable and enable keep credentials, certificate pins and client configurations of every protocol ($(wc -w <<< "$PROTOCOLS" | tr -d ' ') nodes)"

for id in $ids; do
    type=$(node_json "$STATE" "$id" | jq -r .type)
    if proto_has "$type" port_hopping; then
        before "$id"
        # The first free block from 20000 that holds no port of another node.
        range=$(hop_default "$id" "$(node_json "$STATE" "$id" | jq -r .port)")
        node_change "$id" hop auto > /dev/null || fail "hopping on for $type"
        node_json "$STATE" "$id" | jq -e --argjson s "${range% *}" --argjson e "${range#* }" '.hop == {start:$s,end:$e}' >/dev/null || fail "hopping of $type not set"
        same_except "$work/before.json" "$id" hop || fail "hopping on changed fields of $type"
        node_change "$id" hop 40000-40999 > /dev/null || fail "hopping range of $type"
        node_json "$STATE" "$id" | jq -e '.hop == {start:40000,end:40999}' >/dev/null || fail "hopping range of $type not set"
        same_except "$work/before.json" "$id" hop || fail "a new hopping range changed fields of $type"
        node_change "$id" hop off > /dev/null || fail "hopping off for $type"
        kept "$id" 'port hopping on and off'
        cmp -s "$work/before.json" "$STATE" || fail "hopping on and off did not give the same $type node back"
        hopped=1
    else
        cp "$STATE" "$work/before.json"
        if node_change "$id" hop auto > /dev/null 2>&1; then fail "$type took port hopping"; fi
        cmp -s "$work/before.json" "$STATE" || fail "refused hopping changed $type"
    fi
    if proto_has "$type" retarget; then
        before "$id"
        node_change "$id" retarget www.mozilla.org > /dev/null || fail "retarget $type"
        node_json "$STATE" "$id" | jq -e '.sni == "www.mozilla.org"' >/dev/null || fail "target of $type not set"
        same_except "$work/before.json" "$id" sni || fail "a new handshake target changed fields of $type"
        [[ $(credentials) == "$(cat "$work/before.creds")" ]] || fail "a new handshake target changed credentials of $type"
        retargeted=$((${retargeted:-0}+1))
    fi
done
[[ ${hopped:-0} == 1 && ${retargeted:-0} == 2 ]] || fail 'port hopping (Hysteria2) and handshake targets (Reality, ShadowTLS) were not all tried'
echo 'PASS port hopping on, to another range and off, and a new handshake target keep every credential; protocols without hopping refuse it unchanged'

# Another core binary (an update to a newer 1.14 build, here the same core reporting
# another version) leaves state and configuration alone; changes after it keep
# credentials as well.
arch=$(core_arch)
mkdir -p "$work/rel/sing-box-1.14.99-linux-$arch"
printf '#!/bin/sh\n[ "$1" = version ] && { echo "sing-box version 1.14.99"; exit 0; }\nexec %q "$@"\n' "$TEST_CORE" > "$work/rel/sing-box-1.14.99-linux-$arch/sing-box"
chmod 755 "$work/rel/sing-box-1.14.99-linux-$arch/sing-box"
tar -czf "$work/core.tar.gz" -C "$work/rel" "sing-box-1.14.99-linux-$arch"
fetch() { [[ $1 == "https://github.com/SagerNet/sing-box/releases/download/v1.14.99/sing-box-1.14.99-linux-$arch.tar.gz" ]] && cp "$work/core.tar.gz" "$2"; }
update_cache_mark() { :; }
cp "$STATE" "$work/before.json"; credentials > "$work/before.creds"
cp "$DATA/current/config.json" "$work/before-config.json"
core_replace "$(core_installed)" 1.14.99 "$(sha256 "$work/core.tar.gz")" > /dev/null || fail 'core replacement'
[[ $(core_installed) == 1.14.99 ]] || fail 'core not replaced'
cmp -s "$work/before.json" "$STATE" && cmp -s "$work/before-config.json" "$DATA/current/config.json" || fail 'the core replacement changed state or configuration'
[[ $(credentials) == "$(cat "$work/before.creds")" ]] || fail 'the core replacement changed credentials'
for id in $ids; do
    before "$id"
    node_change "$id" port "$(( $(node_json "$STATE" "$id" | jq -r .port) + 1 ))" > /dev/null || fail "port after the core replacement"
    kept "$id" 'changing the port with the new core' port
done
echo 'PASS replacing the core binary changes neither state nor configuration; later changes keep every credential'

# Rotate is the one operation that gives new credentials: the node's port, name,
# target and certificate stay, and no other node changes.
for id in $ids; do
    type=$(node_json "$STATE" "$id" | jq -r .type)
    cp "$STATE" "$work/before.json"; credentials > "$work/before.creds"
    proto_call "$type" rotate; fields=$(jq -r 'keys[]' <<< "$REPLY")
    node_change "$id" rotate > /dev/null || fail "rotate $type"
    # shellcheck disable=SC2086 # one field per word
    same_except "$work/before.json" "$id" $fields || fail "rotate changed more than the credentials of $type"
    for field in $fields; do
        jq -e -n --slurpfile a "$work/before.json" --slurpfile b "$STATE" --arg id "$id" --arg f "$field" \
            '[$a[0], $b[0]|.nodes[]|select(.id == $id)|.[$f]] as [$x, $y]|$x != $y and $y != null' >/dev/null || fail "rotate kept $field of $type"
    done
    jq -e -n --slurpfile a "$work/before.creds" --argjson b "$(credentials)" --arg id "$id" \
        '[$a[0].state[]|select(.id != $id)] == [$b.state[]|select(.id != $id)]' >/dev/null || fail "rotating $type changed another node"
done
echo 'PASS rotate gives the node new credentials and changes nothing else'
