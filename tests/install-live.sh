#!/usr/bin/env bash
# Real install, transaction and uninstall; only for disposable systemd-based Linux CI,
# never an existing customer installation.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source tests/support/guard.sh
need_ci_root
[[ ! -e /opt/srm && ! -e /var/lib/srm ]] || exit 1
bash dist/srm install
cleanup() { printf 'y\n' | bash /opt/srm/manager.sh uninstall; }
trap cleanup EXIT
systemd-analyze verify /etc/systemd/system/srm.service
[[ $(readlink /usr/local/sbin/srm) == /opt/srm/manager.sh && $(readlink /usr/local/sbin/vasma) == /opt/srm/manager.sh ]] || exit 1
srm version | grep -q '^srm ' || exit 1
echo 'PASS install links srm and vasma to the manager'
# A v3 installation owns /usr/bin/vasma; srm must leave it alone.
(
    source ./srm.sh
    rm /usr/local/sbin/vasma
    mkdir -p "$DATA/fake-v3"
    printf '#!/bin/sh\necho v3\n' > "$DATA/fake-v3/install.sh"
    ln -s "$DATA/fake-v3/install.sh" /usr/bin/vasma
    link_vasma | grep -q '旧版脚本' || exit 1
    [[ ! -e /usr/local/sbin/vasma && $(readlink /usr/bin/vasma) == "$DATA/fake-v3/install.sh" ]] || exit 1
    rm /usr/bin/vasma
    link_vasma
    [[ $(readlink /usr/local/sbin/vasma) == /opt/srm/manager.sh ]] || exit 1
)
echo 'PASS vasma is not taken over from an existing v3 installation'
# Exercise certificate activation with real Linux ownership and symlink switching.
source ./srm.sh
mkdir -m 700 "$DATA/cert-test"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$DATA/cert-test/key.pem" -out "$DATA/cert-test/fullchain.pem" -days 2 \
    -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com >/dev/null 2>&1
activate_cert test.example.com "$DATA/cert-test" acme
[[ $(certificate_source test.example.com) == acme ]] || exit 1
old_cert=$(readlink "$DATA/certs/test.example.com/active")
activate_cert test.example.com "$DATA/cert-test" acme
[[ $(readlink "$DATA/certs/test.example.com/active") == "$old_cert" ]] || exit 1
activate_cert test.example.com "$DATA/cert-test" import
[[ $(certificate_source test.example.com) == import ]] || exit 1
[[ $(readlink "$DATA/certs/test.example.com/active") != "$old_cert" ]] || exit 1
[[ $(stat -c '%a' "$DATA/certs/test.example.com/active/renewal-source") == 600 ]] || exit 1
echo 'PASS atomic certificate origin switching and repeated activation'
# Exercise the real configuration transaction with a stopped Reality node.
# The external target was separately tested; this gate focuses on local rollback.
(
    pair=$("$CORE" generate reality-keypair)
    private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
    public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
    uuid=$("$CORE" generate uuid)
    jq -n --arg private "$private" --arg public "$public" --arg uuid "$uuid" \
      '{schema:1,policies:[],unlock_dns:null,egress:null,nodes:[{id:"1111111111111111",name:"test",type:"vless",enabled:false,host:"127.0.0.1",port:18101,sni:"www.ctrip.com",uuid:$uuid,private_key:$private,public_key:$public,short_id:"0123456789abcdef"}]}' > "$DATA/cert-test/state.json"
    # Written as schema 1 on purpose: the real transaction must migrate it.
    apply_state "$DATA/cert-test/state.json"
    jq -e '.schema==2 and .nodes[0].id=="1111111111111111"' "$STATE" >/dev/null || exit 1
    original=$(readlink "$DATA/current")
    reality_target_check() { return 0; }
    firewall_sync() { [[ $(jq -r '.nodes[0].sni' "$1") != www.ixigua.com ]]; }
    ! node_change 1111111111111111 retarget www.ixigua.com || exit 1
    [[ $(readlink "$DATA/current") == "$original" ]] || exit 1
    [[ ! -e $DATA/pending.json ]] || exit 1
    firewall_sync() { return 0; }
    node_change 1111111111111111 retarget www.ixigua.com
    jq -e '.nodes[0].sni=="www.ixigua.com" and .nodes[0].enabled==false' "$STATE" >/dev/null
    ! systemctl is-active --quiet "$SERVICE" || exit 1
)
echo 'PASS real Reality configuration transaction rolls back on failure and preserves stopped state'
# Ports below 1024 work: the service user may bind them and nothing else is granted.
(
    source ./srm.sh
    reality_target_check() { return 0; }
    [[ -z $(ss -H -ltn 'sport = :853') ]] || { echo 'FAIL port 853 already in use on the runner'; exit 1; }
    node_change 1111111111111111 port 853
    node_change 1111111111111111 toggle
    systemctl is-active --quiet "$SERVICE" || exit 1
    [[ -n $(ss -H -ltn 'sport = :853') ]] || exit 1
    [[ $(systemctl show -p AmbientCapabilities --value "$SERVICE") == cap_net_bind_service ]] || exit 1
    [[ $(systemctl show -p User --value "$SERVICE") == srm ]] || exit 1
    node_change 1111111111111111 toggle
    ! systemctl is-active --quiet "$SERVICE" || exit 1
)
echo 'PASS a node on port 853 starts under the unprivileged service user'
# A self-signed TUIC node and a TCP+UDP Shadowsocks node deploy through the real
# transaction: the service user reads the self-signed key and both transports listen.
(
    source ./srm.sh
    node_add "$PWD/dist/srm" tuic --name tuic-self --host 127.0.0.1 --yes
    node_add "$PWD/dist/srm" shadowsocks --name ss --host 127.0.0.1 --yes
    systemctl is-active --quiet "$SERVICE" || exit 1
    dir=$(jq -r '.nodes[]|select(.name=="tuic-self")|.cert_dir' "$STATE")
    [[ $dir == "$DATA/selfsigned/"* && $(stat -c '%U:%G %a' "$dir/key.pem") == 'root:srm 640' ]] || exit 1
    runuser -u srm -- test -r "$dir/key.pem" || exit 1
    port=$(jq -r '.nodes[]|select(.name=="tuic-self")|.port' "$STATE")
    [[ -n $(ss -H -lun "sport = :$port") ]] || exit 1
    port=$(jq -r '.nodes[]|select(.name=="ss")|.port' "$STATE")
    [[ -n $(ss -H -ltn "sport = :$port") && -n $(ss -H -lun "sport = :$port") ]] || exit 1
    for id in $(jq -r '.nodes[]|select(.name=="tuic-self" or .name=="ss")|.id' "$STATE"); do node_change "$id" delete; done
    ! systemctl is-active --quiet "$SERVICE" || exit 1
)
echo 'PASS self-signed TUIC and TCP+UDP Shadowsocks run under the service user'
# Snell v6 and v5 behind ShadowTLS through the real transaction and systemd: the
# pinned official binaries download, snell-server runs as the service user on
# loopback from the current generation, and toggling and deleting stop its unit.
(
    source ./srm.sh
    reality_target_check() { return 0; }
    logs() { journalctl -u srm.service -u 'srm-snell@*' -n 60 --no-pager; ss -ltnp; exit 1; }
    node_add "$PWD/dist/srm" snell --name snell6 --host 127.0.0.1 --yes || logs
    node_add "$PWD/dist/srm" snell --name snell5 --host 127.0.0.1 --proto-version 5 --yes || logs
    systemctl is-active --quiet "$SERVICE" || exit 1
    [[ -x /opt/srm/snell/v6/snell-server && -x /opt/srm/snell/v5/snell-server ]] || exit 1
    for name in snell6 snell5; do
        n=$(jq -c --arg n "$name" '.nodes[]|select(.name==$n)' "$STATE")
        id=$(jq -r .id <<< "$n"); unit=srm-snell@$id.service
        systemd-analyze verify "/etc/systemd/system/$unit"
        systemctl is-active --quiet "$unit" && systemctl is-enabled --quiet "$unit" || { journalctl -u "$unit" --no-pager | tail -20; exit 1; }
        [[ $(systemctl show -p User --value "$unit") == srm ]] || exit 1
        ss -H -ltn "sport = :$(jq -r .local_port <<< "$n")" | grep -q "127.0.0.1:$(jq -r .local_port <<< "$n") " || exit 1
        [[ -n $(ss -H -ltn "sport = :$(jq -r .port <<< "$n")") ]] || exit 1
        [[ $(readlink "$DATA/current/sidecar/$id/snell-server") == "/opt/srm/snell/v$(jq -r .snell_version <<< "$n")/snell-server" ]] || exit 1
    done
    show_logs | grep -q 'snell-server v6\.' && show_logs | grep -q 'snell-server v5\.' || { show_logs; exit 1; }
    show_status | grep -q "srm-snell@$id.service" || exit 1
    node_change "$id" toggle
    ! systemctl is-active --quiet "$unit" && ! systemctl is-enabled --quiet "$unit" || exit 1
    node_change "$id" toggle
    systemctl is-active --quiet "$unit" || exit 1
    # The v6 node goes; the v5 node keeps running for the uninstall below.
    id=$(jq -r '.nodes[]|select(.name=="snell6")|.id' "$STATE")
    node_change "$id" delete
    ! systemctl is-active --quiet "srm-snell@$id.service" && ! systemctl is-enabled --quiet "srm-snell@$id.service" || exit 1
    systemctl is-active --quiet "$SERVICE" && systemctl is-active --quiet "$unit" || exit 1
)
echo 'PASS Snell v6 and v5 run as srm-snell@<node> on loopback behind sing-box; toggle and delete stop the unit'
# Updates are manual only: installation must not schedule any update job.
if compgen -G '/etc/systemd/system/srm-update*' > /dev/null; then echo 'FAIL update unit installed'; exit 1; fi
if crontab -l 2>/dev/null | grep -q srm; then echo 'FAIL update cron job installed'; exit 1; fi
echo 'PASS no automatic update job is installed'
# Uninstall with sing-box and a snell-server still running stops and removes both.
systemctl is-active --quiet srm.service || exit 1
cleanup
trap - EXIT
[[ ! -e /opt/srm && ! -e /var/lib/srm && ! -e /etc/systemd/system/srm.service && ! -e /etc/systemd/system/srm-snell@.service ]] || exit 1
! systemctl is-active --quiet srm.service || exit 1
if systemctl list-units --all --plain --no-legend 'srm-snell@*' | grep -qw active; then echo 'FAIL snell-server still running'; exit 1; fi
if compgen -G '/etc/systemd/system/multi-user.target.wants/srm*' > /dev/null; then echo 'FAIL unit still enabled'; exit 1; fi
[[ ! -e /usr/local/sbin/srm && ! -L /usr/local/sbin/vasma ]] || exit 1
echo 'PASS uninstall stops sing-box and snell-server and removes manager, units and both commands'
