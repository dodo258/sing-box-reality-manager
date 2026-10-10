#!/usr/bin/env bash
# Only for disposable systemd-based Linux CI, not an existing customer installation.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source tests/support/guard.sh
need_ci_root
[[ ! -e /opt/srm && ! -e /var/lib/srm ]] || exit 1
bash dist/srm install
# A test-only unit condition prevents a scheduled check from downloading an older
# public release before this candidate has itself been released.
mkdir -p /run/systemd/system/srm-update.service.d
printf '[Unit]\nConditionPathExists=/run/srm-ci-allow-update\n' > /run/systemd/system/srm-update.service.d/ci.conf
cleanup() {
    printf 'y\n' | bash /opt/srm/manager.sh uninstall
    rm -f /run/systemd/system/srm-update.service.d/ci.conf
    rmdir /run/systemd/system/srm-update.service.d
    systemctl daemon-reload
}
trap cleanup EXIT
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
    apply_state "$DATA/cert-test/state.json"
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
bash /opt/srm/manager.sh auto-update on
systemctl is-enabled --quiet srm-update.timer
systemctl is-active --quiet srm-update.timer
systemd-analyze verify /etc/systemd/system/srm-update.service /etc/systemd/system/srm-update.timer
bash /opt/srm/manager.sh auto-update status
bash /opt/srm/manager.sh auto-update off
! systemctl is-active --quiet srm-update.timer || exit 1
[[ ! -e /etc/systemd/system/srm-update.service ]] || exit 1
echo 'PASS real systemd timer enable, status and disable'
# Avoid network updates during this test, then check uninstall cleans the timer.
bash /opt/srm/manager.sh auto-update on
cleanup
trap - EXIT
[[ ! -e /opt/srm && ! -e /var/lib/srm ]] || exit 1
[[ ! -e /etc/systemd/system/srm-update.timer ]] || exit 1
echo 'PASS uninstall removes manager and update timer'
