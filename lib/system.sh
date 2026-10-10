owned_root() {
    [[ -f $SRM_ROOT/.srm-owned && -f $DATA/.srm-owned ]] || { err '没有找到本脚本的安装标记。'; return 1; }
}
setup() {
    require_linux || return 1
    local path self=$1
    for path in "$SRM_ROOT" "$DATA"; do
        [[ ! -e $path || -f $path/.srm-owned ]] || { err "$path 已存在且不属于本脚本。"; return 1; }
    done
    if [[ -e /etc/systemd/system/$SERVICE && ! -f $SRM_ROOT/.srm-owned ]]; then err '服务名已被占用。'; return 1; fi
    if [[ -e /usr/local/sbin/srm && ! -f $SRM_ROOT/.srm-owned ]]; then err '快捷命令已被占用。'; return 1; fi
    ensure_dependencies || return 1
    if ! id srm >/dev/null 2>&1; then
        useradd --system --no-create-home --home-dir "$DATA" --shell /usr/sbin/nologin srm || return 1
    elif [[ ! -f $SRM_ROOT/.srm-owned ]]; then err 'srm 系统用户已存在，请先排查。'; return 1; fi
    install -d -m 755 "$SRM_ROOT" "$SRM_ROOT/core" || return 1
    install -d -m 750 -o root -g srm "$DATA" "$DATA/generations" "$DATA/certs" || return 1
    touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned" || return 1
    [[ -x $CORE ]] || core_download "$CORE" || return 1
    # Must be a bundled distribution, not the development loader.
    grep -q '^# SRM_BUNDLE$' "$self" || { err '请先运行 bash build.sh，再使用 dist/srm。'; return 1; }
    if [[ $(readlink -f "$self") != "$SRM_ROOT/manager.sh" ]]; then install -m 755 "$self" "$SRM_ROOT/manager.sh" || return 1; fi
    local existing
    existing=$(command -v srm 2>/dev/null) || existing=''
    if [[ -n $existing && $existing != /usr/local/sbin/srm ]]; then
        msg "注意：系统已有 srm 命令（${existing}，可能是 secure-delete），本脚本的 srm 会优先；原命令请用完整路径。"
    fi
    ln -sfn "$SRM_ROOT/manager.sh" /usr/local/sbin/srm || return 1
    link_vasma
    cat > "/etc/systemd/system/$SERVICE" <<UNIT
[Unit]
Description=srm sing-box nodes
After=network-online.target
Wants=network-online.target
[Service]
User=srm
Group=srm
ExecStart=$CORE run -c $DATA/current/config.json
Restart=on-failure
RestartSec=3
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictSUIDSGID=true
# Only for node ports below 1024 (e.g. 443); no other privilege.
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload || return 1
    msg '运行环境就绪。'
}
# `vasma` is the v3 command name. Never shadow a v3 installation that still owns it.
link_vasma() {
    local existing
    existing=$(command -v vasma 2>/dev/null) || existing=''
    if [[ -z $existing || $(readlink -f "$existing") == "$SRM_ROOT/manager.sh" ]]; then
        ln -sfn "$SRM_ROOT/manager.sh" /usr/local/sbin/vasma
    else msg "vasma 仍指向旧版脚本（$existing），保持不变；可使用 srm 命令。"; fi
}
new_candidate() {
    local tmp
    tmp=$(mktemp) || return 1
    chmod 600 "$tmp"
    if [[ -f $STATE ]]; then state_upgrade "$STATE" > "$tmp"; else empty_state > "$tmp"; fi || { rm -f "$tmp"; return 1; }
    printf '%s\n' "$tmp"
}
service_healthy() {
    local candidate=$1 tries port kind output unit
    for ((tries=0; tries<15; tries++)); do
        if systemctl is-active --quiet "$SERVICE"; then
            local good=1
            while IFS=$'\t' read -r port kind; do
                [[ -n $port ]] || continue
                if [[ $kind == udp ]]; then output=$(ss -H -lun "sport = :$port"); else output=$(ss -H -ltn "sport = :$port"); fi
                [[ -n $output ]] || good=0
            done < <(jq -r ".nodes[]|select(.enabled)|.port as \$p|($(proto_jq_transports))[]|[\$p,.]|@tsv" "$candidate")
            # Helper services must run and listen on their loopback port as well.
            while IFS=$'\t' read -r unit port; do
                [[ -n $unit ]] || continue
                systemctl is-active --quiet "$unit" && [[ -n $(ss -H -ltn "sport = :$port") ]] || good=0
            done < <(jq -r "$PROTO_JQ_DEFS .nodes[]|select(.enabled)|($(proto_jq sidecar empty)) as \$u|[\$u,.local_port]|@tsv" "$candidate")
            [[ $good == 1 ]] && return 0
        fi
        sleep 1
    done
    return 1
}
# Helper services (registry hook "sidecar"): unit names of STATE's enabled nodes,
# or of all its nodes with "true".
sidecar_units() {
    [[ -n ${1:-} && -f $1 ]] || return 0
    jq -r --argjson all "${2:-false}" "$PROTO_JQ_DEFS .nodes[]|select(.enabled or \$all)|$(proto_jq sidecar empty)" "$1"
}
# Helper units systemd knows: loaded (running, failed or stopped) or enabled.
sidecar_known() {
    { systemctl list-units --all --plain --no-legend --no-pager 'srm-*@*.service' 2>/dev/null || true
      ls /etc/systemd/system/multi-user.target.wants/ 2>/dev/null || true; } |
        grep -oE 'srm-[a-z0-9]+@[a-f0-9]{16}\.service' | sort -u
}
# Writes the helper files of STATE's enabled nodes into generation GEN.
sidecar_render() {
    local node id dir file
    while IFS= read -r node; do
        [[ -n $node ]] || continue
        id=$(jq -r .id <<< "$node") || return 1
        dir=$2/sidecar/$id
        install -d -m 750 "$2/sidecar" "$dir" && chgrp srm "$2/sidecar" "$dir" || return 1
        proto_call "$(jq -r .type <<< "$node")" sidecar_render "$node" "$dir" || return 1
        for file in "$dir"/*; do
            [[ -L $file || ! -f $file ]] || { chmod 640 "$file" && chgrp srm "$file"; } || return 1
        done
    done < <(jq -c "$PROTO_JQ_DEFS .nodes[]|select(.enabled)|select(($(proto_jq sidecar empty))|length > 0)" "$1")
}
# (Re)starts the helper services of STATE's enabled nodes and stops every other one;
# without a state all of them stop.
sidecars_sync() {
    local want unit failures=0
    want=$(sidecar_units "${1:-}") || return 1
    for unit in $(sidecar_known); do
        grep -Fxq "$unit" <<< "$want" || systemctl disable --now "$unit" >/dev/null 2>&1 || failures=1
    done
    for unit in $want; do
        { systemctl restart "$unit" && systemctl enable "$unit" >/dev/null 2>&1; } || failures=1
    done
    return "$failures"
}
switch_generation() {
    local target=$1
    rm -f "$DATA/.current-next" || return 1
    ln -s "$target" "$DATA/.current-next" && mv -Tf "$DATA/.current-next" "$DATA/current"
}
recover_pending() {
    [[ -f $DATA/pending.json ]] || return 0
    local old active
    old=$(jq -er '.old // ""' "$DATA/pending.json") || return 1
    active=$(jq -r .active "$DATA/pending.json") || return 1
    if [[ -n $old ]]; then
        [[ $old == "$DATA/generations/"* && -f $old/state.json ]] || { err '回滚记录异常，需要人工检查。'; return 1; }
        switch_generation "$old" || return 1
        if [[ $active == 1 ]]; then
            sidecars_sync "$STATE" && systemctl restart "$SERVICE" && service_healthy "$STATE" || { err '恢复原配置后服务启动失败。'; return 1; }
        else systemctl stop "$SERVICE" && sidecars_sync || return 1; fi
    else
        systemctl stop "$SERVICE" && sidecars_sync || return 1
        rm -f "$DATA/current"
    fi
    firewall_sync "$STATE" || return 1
    rm -f "$DATA/pending.json"
    msg '已恢复中断操作之前的配置。'
}
apply_state() (
    owned_root || exit 1
    local candidate gen old='' active=0 count switched=0
    # The generation keeps the upgraded copy, so a rollback to an older-schema
    # generation is migrated too; the file passed in is never modified.
    candidate=$(mktemp) || exit 1
    trap 'rm -f "$candidate"' EXIT
    state_upgrade "$1" > "$candidate" && validate_state "$candidate" || exit 1
    gen=$(mktemp -d "$DATA/generations/g.XXXXXXXX") || exit 1
    chmod 750 "$gen" && chgrp srm "$gen" || exit 1
    if ! render_config "$candidate" > "$gen/config.json" || ! "$CORE" check -c "$gen/config.json" || ! sidecar_render "$candidate" "$gen"; then
        rm -rf "$gen"; err '核心校验失败，原节点未改动。'; exit 1
    fi
    install -m 600 "$candidate" "$gen/state.json" || exit 1
    chmod 640 "$gen/config.json" && chgrp srm "$gen/config.json" || exit 1
    [[ ! -L $DATA/current ]] || old=$(readlink "$DATA/current")
    systemctl is-active --quiet "$SERVICE" && active=1
    jq -n --arg old "$old" --argjson active "$active" '{old:$old,active:$active}' > "$DATA/pending.json" || exit 1
    trap 'rm -f "$candidate"; [[ $switched == 0 ]] || recover_pending' EXIT
    trap 'exit 130' INT TERM HUP
    switched=1
    switch_generation "$gen" || exit 1
    count=$(jq '[.nodes[]|select(.enabled)]|length' "$candidate")
    if [[ $count == 0 ]]; then
        systemctl stop "$SERVICE" && sidecars_sync || exit 1
    else
        if ! sidecars_sync "$candidate" || ! systemctl restart "$SERVICE" || ! service_healthy "$candidate"; then err '新配置启动失败，恢复上一份配置。'; exit 1; fi
        systemctl enable "$SERVICE" >/dev/null || exit 1
    fi
    if ! firewall_sync "$candidate"; then err '端口规则应用失败，恢复上一份节点配置和端口规则。'; exit 1; fi
    if [[ -n $old ]]; then ln -sfn "$old" "$DATA/previous" || exit 1; fi
    rm -f "$DATA/pending.json" || exit 1
    switched=0
    if [[ $count == 0 ]]; then msg '所有节点已停用。'; else msg '配置已应用，服务和监听正常；外部客户端连通仍需验证。'; fi
)
rollback_config() {
    owned_root || return 1
    [[ -f $DATA/previous/state.json ]] || { err '没有可回滚的配置。'; return 1; }
    apply_state "$DATA/previous/state.json"
}
update_core() {
    owned_root || return 1
    local tmp old_active=0
    if [[ $("$CORE" version | head -n 1) == "sing-box version $CORE_VERSION" ]]; then msg "已是本脚本验证的核心版本 $CORE_VERSION。"; return 0; fi
    tmp=$(mktemp "$SRM_ROOT/core/.candidate.XXXXXX") || return 1
    if ! core_download "$tmp"; then rm -f "$tmp"; return 1; fi
    if [[ -f $DATA/current/config.json ]] && ! "$tmp" check -c "$DATA/current/config.json"; then rm -f "$tmp"; return 1; fi
    systemctl is-active --quiet "$SERVICE" && old_active=1
    cp -p "$CORE" "$CORE.previous" && mv -f "$tmp" "$CORE" || return 1
    if [[ $old_active == 0 ]]; then msg '核心已更新；服务保持停止状态。'; return 0; fi
    if systemctl restart "$SERVICE" && service_healthy "$STATE"; then msg "核心已更新到 $CORE_VERSION。"; return 0; fi
    mv -f "$CORE.previous" "$CORE"
    systemctl restart "$SERVICE"
    err '新核心启动失败，已恢复原核心。'; return 1
}
update_script() {
    owned_root || return 1
    local source=$1 expected=$2 tmp
    [[ $expected =~ ^[a-f0-9]{64}$ ]] || { err '需要发布方提供的 SHA256。'; return 1; }
    tmp=$(mktemp "$SRM_ROOT/.manager.XXXXXX") || return 1
    case $source in https://*) fetch "$source" "$tmp" || { rm -f "$tmp"; return 1; };; /*) cp "$source" "$tmp" || return 1;; *) err '请输入 HTTPS 地址或本地绝对路径。'; rm -f "$tmp"; return 1;; esac
    if [[ $(sha256 "$tmp") != "$expected" ]] || ! bash -n "$tmp" || ! grep -q '^# SRM_BUNDLE$' "$tmp"; then
        err '脚本校验失败，原脚本未改动。'; rm -f "$tmp"; return 1
    fi
    cp -p "$SRM_ROOT/manager.sh" "$SRM_ROOT/manager.previous.sh" && chmod 755 "$tmp" && mv -f "$tmp" "$SRM_ROOT/manager.sh" || return 1
    msg '脚本更新完成，请退出菜单后重新输入 srm 打开。核心和节点配置未自动升级。'
}
bbr_status() {
    sysctl net.ipv4.tcp_congestion_control net.ipv4.tcp_available_congestion_control net.core.default_qdisc
}
bbr_enable() {
    owned_root || return 1
    local ctl=/etc/sysctl.d/90-srm-bbr.conf
    [[ ! -e $ctl || -f $DATA/bbr-before.json ]] || { err "$ctl 已存在，不覆盖。"; return 1; }
    modprobe tcp_bbr 2>/dev/null || true
    sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw bbr || { err '当前内核不支持 BBR，跳过；不会换内核或重启。'; return 1; }
    if [[ ! -f $DATA/bbr-before.json ]]; then
        jq -n --arg cc "$(sysctl -n net.ipv4.tcp_congestion_control)" --arg q "$(sysctl -n net.core.default_qdisc)" '{cc:$cc,qdisc:$q}' > "$DATA/bbr-before.json" || return 1
    fi
    printf 'net.core.default_qdisc = fq\nnet.ipv4.tcp_congestion_control = bbr\n' > "$ctl" || return 1
    sysctl -p "$ctl" && bbr_status
}
bbr_restore() {
    [[ -f $DATA/bbr-before.json ]] || return 0
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr && $(sysctl -n net.core.default_qdisc) == fq ]]; then
        sysctl -w "net.ipv4.tcp_congestion_control=$(jq -r .cc "$DATA/bbr-before.json")" "net.core.default_qdisc=$(jq -r .qdisc "$DATA/bbr-before.json")" || return 1
    else msg 'BBR 当前值已被其他操作修改，保留当前值。'; fi
    rm -f /etc/sysctl.d/90-srm-bbr.conf "$DATA/bbr-before.json"
}
show_status() {
    if [[ -f $STATE ]]; then jq -r '.nodes[]|[.id,.name,.type,(.port|tostring),(if .enabled then "启用" else "停用" end)]|@tsv' "$STATE"; else msg '尚无节点。'; fi
    # shellcheck disable=SC2046 # unit names have no spaces
    systemctl --no-pager --full status "$SERVICE" $(sidecar_units "$STATE" true) || true
    msg '节点变更时自动同步 UFW/firewalld 端口规则；云安全组需在服务商控制台放行对应端口。'
}
show_logs() {
    local unit args=(-u "$SERVICE")
    for unit in $(sidecar_units "$STATE" true); do args+=(-u "$unit"); done
    journalctl "${args[@]}" -n 50 --no-pager
}
uninstall() {
    owned_root || return 1
    msg "删除本脚本服务、续期任务、$SRM_ROOT、$DATA 和快捷命令；节点凭据与本脚本证书会删除。系统依赖、其他服务和防火墙保留。"
    [[ ${assume_yes:-0} == 1 ]] || yesno '已导出需要的节点资料，确认卸载' || return 0
    systemctl disable --now "$SERVICE" srm-renew.timer 2>/dev/null || true
    sidecars_sync || true
    if systemctl is-active --quiet "$SERVICE" || systemctl is-active --quiet srm-renew.service; then err '服务仍在运行，停止卸载。'; return 1; fi
    local unit
    for unit in $(sidecar_known); do
        ! systemctl is-active --quiet "$unit" || { err "$unit 仍在运行，停止卸载。"; return 1; }
    done
    firewall_clear || { err '端口规则清理失败，保留数据以便重试卸载。'; return 1; }
    bbr_restore || return 1
    rm -f "/etc/systemd/system/$SERVICE" /etc/systemd/system/srm-renew.service /etc/systemd/system/srm-renew.timer /etc/systemd/system/srm-*@.service
    [[ $(readlink /usr/local/sbin/srm) != "$SRM_ROOT/manager.sh" ]] || rm -f /usr/local/sbin/srm
    [[ $(readlink /usr/local/sbin/vasma) != "$SRM_ROOT/manager.sh" ]] || rm -f /usr/local/sbin/vasma
    rm -rf "$SRM_ROOT" "$DATA"
    userdel srm || true
    systemctl daemon-reload
    msg '卸载完成。'
}
update_latest() {
    owned_root || return 1
    local tmp url digest
    tmp=$(mktemp) || return 1
    if ! fetch "https://api.github.com/repos/$SRM_REPO/releases/latest" "$tmp"; then rm -f "$tmp"; return 1; fi
    url=$(jq -r '.assets[]?|select(.name=="srm")|.browser_download_url' "$tmp")
    digest=$(jq -r '.assets[]?|select(.name=="srm")|.digest // empty' "$tmp")
    rm -f "$tmp"
    if [[ -z $url ]]; then msg '发布仓库暂时没有独立脚本安装包，保留当前版本。'; return 0; fi
    [[ $url == "https://github.com/$SRM_REPO/releases/download/"*/srm && $digest == sha256:* ]] || { err '发布信息不符合预期。'; return 1; }
    if [[ $(sha256 "$SRM_ROOT/manager.sh") == "${digest#sha256:}" ]]; then msg '已是最新发布的脚本。'; return 0; fi
    update_script "$url" "${digest#sha256:}"
}
