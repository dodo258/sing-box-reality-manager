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
# The daily version check is registered with systemd at install; its service only
# runs the check, sandboxed so it cannot write outside /var/lib/srm.
systemd-analyze verify /etc/systemd/system/srm-version-check.service /etc/systemd/system/srm-version-check.timer
systemctl is-enabled --quiet srm-version-check.timer && systemctl is-active --quiet srm-version-check.timer || exit 1
systemctl list-timers --all --no-pager srm-version-check.timer | grep -q 'srm-version-check.timer' || exit 1
[[ $(systemctl show -p ExecStart --value srm-version-check.service) == *'path=/usr/local/sbin/srm ; argv[]=/usr/local/sbin/srm update-check run ;'* ]] || exit 1
[[ $(systemctl show -p ProtectSystem --value srm-version-check.service) == strict ]] || exit 1
srm update-check off | grep -q '每日检查已关闭' || exit 1
! systemctl is-enabled --quiet srm-version-check.timer && ! systemctl is-active --quiet srm-version-check.timer || exit 1
srm update-check on | grep -q '每日检查已开启' || exit 1
systemctl is-enabled --quiet srm-version-check.timer && systemctl is-active --quiet srm-version-check.timer || exit 1
echo 'PASS the daily version check timer registers with real systemd and turns off and on'
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
# The real menu, lock and transaction: 1 (添加节点), then only Enter deploys a running
# VLESS Reality node and shows its summary. The public-IP lookup and the external
# handshake check are replaced (tests/reality-live.sh covers the latter).
(
    source ./srm.sh
    detect_public_ip() { PUBLIC_IP=127.0.0.1; PUBLIC_LOC=''; }
    reality_target_check() { return 0; }
    before=$(jq '.nodes|length' "$STATE")
    out=$(main <<< $'1\n\n\n\n\n0' 2>&1) || { printf '%s\n' "$out"; exit 1; }
    n=$(jq -c '.nodes[-1]' "$STATE")
    [[ $(jq '.nodes|length' "$STATE") == $((before+1)) ]] && jq -e '.type=="vless" and .enabled and .host=="127.0.0.1"' <<< "$n" >/dev/null || { printf '%s\n' "$out"; exit 1; }
    systemctl is-active --quiet "$SERVICE" && [[ -n $(ss -H -ltn "sport = :$(jq -r .port <<< "$n")") ]] || exit 1
    grep -q '部署完成' <<< "$out" && grep -q '^vless://' <<< "$out" || { printf '%s\n' "$out"; exit 1; }
    node_change "$(jq -r .id <<< "$n")" delete
)
echo 'PASS the real menu deploys a running VLESS Reality node with Enter only'
# Snell v6 and v5 behind ShadowTLS through the real transaction and systemd: the
# pinned official binaries download, snell-server runs as the service user on
# loopback from the current generation, and toggling and deleting stop its unit.
(
    source ./srm.sh
    reality_target_check() { return 0; }
    logs() { systemctl status srm.service --no-pager; journalctl -u srm.service -u 'srm-snell@*' -n 60 --no-pager; ss -ltnp; exit 1; }
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
    # Captured first: grep -q closing the pipe early would fail the pipeline.
    out=$(show_logs)
    grep -q 'snell-server v6\.' <<< "$out" && grep -q 'snell-server v5\.' <<< "$out" || { printf '%s\n' "$out"; exit 1; }
    out=$(show_status)
    grep -q "srm-snell@$id.service" <<< "$out" || exit 1
    node_change "$id" toggle
    ! systemctl is-active --quiet "$unit" && ! systemctl is-enabled --quiet "$unit" || exit 1
    node_change "$id" toggle
    systemctl is-active --quiet "$unit" || exit 1
    # Quick successive changes restart sing-box and every snell-server; seven
    # restarts in a row exceed systemd's default start limit (5 in 10 s).
    for i in 1 2 3 4 5 6 7; do restart_unit "$SERVICE" && restart_unit "$unit" || logs; done
    service_healthy "$STATE" || logs
    # The v6 node goes; the v5 node keeps running for the uninstall below.
    id=$(jq -r '.nodes[]|select(.name=="snell6")|.id' "$STATE")
    node_change "$id" delete
    ! systemctl is-active --quiet "srm-snell@$id.service" && ! systemctl is-enabled --quiet "srm-snell@$id.service" || exit 1
    systemctl is-active --quiet "$SERVICE" && systemctl is-active --quiet "$unit" || exit 1
)
echo 'PASS Snell v6 and v5 run as srm-snell@<node> on loopback behind sing-box; toggle and delete stop the unit'
# The real check service, run by systemd as the timer would: it records versions
# (sing-box from GitHub, Snell v5 from the vendor's release notes) and replaces or
# restarts nothing. A lookup failure is recorded in the cache, not fatal here.
(
    unit=$(systemctl list-units --plain --no-legend 'srm-snell@*' | awk '{print $1}')
    [[ -n $unit ]] || exit 1
    before=$(sha256sum /opt/srm/core/sing-box /opt/srm/snell/v*/snell-server)
    ids="$(systemctl show -p InvocationID --value srm.service) $(systemctl show -p InvocationID --value "$unit")"
    systemctl start srm-version-check.service || journalctl -u srm-version-check.service -n 20 --no-pager
    jq . /var/lib/srm/update-check.json
    jq -e --arg v "$(/opt/srm/core/sing-box version | awk 'NR == 1 {print $3}')" \
        '.items[0].name == "sing-box" and .items[0].current == $v and any(.items[]; .name == "Snell v5")' /var/lib/srm/update-check.json >/dev/null || exit 1
    [[ $(sha256sum /opt/srm/core/sing-box /opt/srm/snell/v*/snell-server) == "$before" ]] || exit 1
    [[ "$(systemctl show -p InvocationID --value srm.service) $(systemctl show -p InvocationID --value "$unit")" == "$ids" ]] || exit 1
)
echo 'PASS the real check service records versions without replacing or restarting anything'
# Updates are manual only: installation must not schedule any update job.
if compgen -G '/etc/systemd/system/srm-update*' > /dev/null; then echo 'FAIL update unit installed'; exit 1; fi
if crontab -l 2>/dev/null | grep -q srm; then echo 'FAIL update cron job installed'; exit 1; fi
echo 'PASS no automatic update job is installed'
# Moving v3 with real systemd: a stand-in for v3's dodo258-sing-box runs the single
# Reality sample on its port. When the takeover fails after srm started on the port,
# the old unit runs and is enabled again; then srm takes the port over, the old unit
# ends stopped and disabled, the v3 cron job is commented out and the v3 files stay
# byte for byte the same.
(
    source ./srm.sh
    logs() { systemctl status srm.service dodo258-sing-box.service --no-pager || true; journalctl -u srm.service -n 40 --no-pager; ss -ltnp; exit 1; }
    v3=$(mktemp -d) run=$(mktemp -d) port=30443
    cp -R tests/fixtures/v3/reality/etc-v2ray-agent/. "$v3/"
    find "$v3" -name '*.json' -exec sed -i "s#/etc/v2ray-agent#$v3#g" {} +
    cp "$v3"/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json "$run/config.json"
    [[ -z $(ss -H -ltn "sport = :$port") ]] || { echo "FAIL port $port already in use on the runner"; exit 1; }
    printf '[Unit]\nDescription=v3 stand-in\n[Service]\nExecStart=%s run -c %s/config.json\n[Install]\nWantedBy=multi-user.target\n' "$CORE" "$run" \
        > /etc/systemd/system/dodo258-sing-box.service
    systemctl daemon-reload && systemctl enable --now dodo258-sing-box.service
    for i in 1 2 3 4 5 6 7 8 9 10; do [[ -z $(ss -H -ltn "sport = :$port") ]] || break; sleep 1; done
    [[ -n $(ss -H -ltn "sport = :$port") ]] || logs
    printf '30 1 * * * /bin/bash %s/install.sh RenewTLS >> /dev/null 2>&1\n' "$v3" | crontab -
    hash() { (cd "$v3" && find . -type f -exec sha256sum {} + | sort; find . | sort) | sha256sum; }
    before=$(hash) state=$(sha256sum < "$STATE")
    V3_ROOT=$v3 opt_host=127.0.0.1 assume_yes=1
    # srm has the port already when this step fails, so the old service must come back after it.
    if (firewall_sync() { ! jq -e --argjson p "$port" 'any(.nodes[]; .port == $p)' "$1" >/dev/null; }; migrate_apply "$PWD/dist/srm") > "$v3.out" 2>&1; then
        cat "$v3.out"; echo 'FAIL takeover reported success although applying failed'; exit 1
    fi
    # The failure came after the old unit stopped and srm took over, not before.
    grep -q '停止旧服务 dodo258-sing-box.service' "$v3.out" && grep -q '恢复旧服务 dodo258-sing-box.service' "$v3.out" &&
        grep -q '迁移失败，已恢复旧服务' "$v3.out" || { cat "$v3.out"; exit 1; }
    [[ ! -e $DATA/pending.json ]] || exit 1
    systemctl is-active --quiet dodo258-sing-box.service && systemctl is-enabled --quiet dodo258-sing-box.service || logs
    # The restarted core needs a moment to bind its port.
    for i in 1 2 3 4 5 6 7 8 9 10; do [[ -z $(ss -H -ltn "sport = :$port") ]] || break; sleep 1; done
    [[ -n $(ss -H -ltn "sport = :$port") && $(sha256sum < "$STATE") == "$state" ]] || logs
    crontab -l | grep -q '^30 1 \* \* \* /bin/bash' || exit 1
    echo 'PASS a failed takeover with real systemd starts and enables the old v3 service again'
    migrate_apply "$PWD/dist/srm" > "$v3.out" 2>&1 || { cat "$v3.out"; logs; }
    ! systemctl is-active --quiet dodo258-sing-box.service && ! systemctl is-enabled --quiet dodo258-sing-box.service || logs
    systemctl is-active --quiet srm.service && [[ -n $(ss -H -ltnp "sport = :$port" | grep sing-box) ]] || logs
    id=$(jq -r --argjson p "$port" '.nodes[]|select(.port == $p)|.id' "$STATE")
    [[ -n $id && $(hash) == "$before" ]] || exit 1
    crontab -l | grep -q '^# srm 迁移后停用：30 1 ' || exit 1
    node_change "$id" delete
    crontab -r; rm -f /etc/systemd/system/dodo258-sing-box.service "$v3.out"; systemctl daemon-reload
    echo 'PASS srm takes over the port of the v3 service with real systemd; the old unit is stopped and disabled, /etc/v2ray-agent unchanged'
)
# Uninstall with sing-box and a snell-server still running stops and removes both.
systemctl is-active --quiet srm.service || exit 1
cleanup
trap - EXIT
[[ ! -e /opt/srm && ! -e /var/lib/srm && ! -e /etc/systemd/system/srm.service && ! -e /etc/systemd/system/srm-snell@.service ]] || exit 1
[[ ! -e /etc/systemd/system/srm-version-check.timer && ! -e /etc/systemd/system/srm-version-check.service ]] || exit 1
! systemctl is-active --quiet srm-version-check.timer || exit 1
! systemctl is-active --quiet srm.service || exit 1
if systemctl list-units --all --plain --no-legend 'srm-snell@*' | grep -qw active; then echo 'FAIL snell-server still running'; exit 1; fi
if compgen -G '/etc/systemd/system/multi-user.target.wants/srm*' > /dev/null; then echo 'FAIL unit still enabled'; exit 1; fi
[[ ! -e /usr/local/sbin/srm && ! -L /usr/local/sbin/vasma ]] || exit 1
echo 'PASS uninstall stops sing-box and snell-server and removes manager, units (also the version check) and both commands'
