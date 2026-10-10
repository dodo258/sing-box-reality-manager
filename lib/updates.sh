# Updates are manual: replacing sing-box or a program next to it restarts it and drops
# connections for a few seconds. A daily timer only looks up version numbers
# (update_check_run) and writes $DATA/update-check.json; the menu header reads that
# file and never reaches the network.
# Protocols whose server program srm downloads (registry program_* hooks).
program_types() {
    local type
    for type in $PROTOCOLS; do proto_has "$type" program_latest && printf '%s\n' "$type"; done
    return 0
}
program_labels() {
    local type out=''
    for type in $(program_types); do out+="${out:+ / }$(proto_call "$type" program_label)"; done
    printf '%s\n' "$out"
}
# Program variants (e.g. v6) that TYPE's nodes in the state use.
program_keys() {
    [[ -f $STATE ]] || return 0
    jq -r --arg t "$1" "$PROTO_JQ_DEFS .nodes[]|select(.type == \$t)|$(proto_jq program_key empty)" "$STATE" | sort -u
}
core_installed() { "$CORE" version 2>/dev/null | awk 'NR == 1 {print $3}'; }
update_item() {
    local newer=false
    [[ -z $4 ]] || ! version_newer "$4" "$3" || newer=true
    jq -c --arg n "$2" --arg c "$3" --arg l "$4" --argjson newer "$newer" \
        '. + [{name:$n,current:(if $c == "" then null else $c end),latest:(if $l == "" then null else $l end),newer:$newer}]' <<< "$1"
}
update_cache_write() {
    local tmp
    tmp=$(mktemp "$DATA/.update-check.XXXXXX") || return 1
    if printf '%s\n' "$1" > "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$DATA/update-check.json"; then return 0; fi
    rm -f "$tmp"; return 1
}
# After a manual update the cached entry NAME runs VERSION; the hint goes away.
update_cache_mark() {
    local file=$DATA/update-check.json latest cache
    [[ -f $file ]] || return 0
    latest=$(jq -r --arg n "$1" '.items[]|select(.name == $n)|.latest // empty' "$file") || return 0
    local newer=false
    [[ -z $latest ]] || ! version_newer "$latest" "$2" || newer=true
    cache=$(jq --arg n "$1" --arg v "$2" --argjson newer "$newer" '(.items[]|select(.name == $n)) |= (.current = $v | .newer = $newer)' "$file") &&
        update_cache_write "$cache" || true
}
# The daily timer's job: looks up the newest versions and records them. It downloads
# no program, replaces no file other than the cache, restarts nothing and takes no
# lock (the lock would resume an interrupted change).
update_check_run() {
    owned_root || return 1
    local items='[]' errors=() release latest='' type key version keys lines label
    if release=$(core_release); then latest=${release% *}; else errors+=('sing-box：没有查到最新版本'); fi
    items=$(update_item "$items" sing-box "$(core_installed)" "$latest") || return 1
    for type in $(program_types); do
        keys=$(program_keys "$type")
        [[ -n $keys ]] || continue
        label=$(proto_call "$type" program_label)
        # shellcheck disable=SC2086 # one key per word
        lines=$(proto_call "$type" program_latest $keys) || true
        for key in $keys; do
            version=$(awk -F '\t' -v k="$key" '$1 == k {print $2}' <<< "$lines")
            [[ -n $version ]] || errors+=("$label $key：没有查到最新版本")
            items=$(update_item "$items" "$label $key" "$(proto_call "$type" program_current "$key")" "$version") || return 1
        done
    done
    local cache
    cache=$(jq -n --arg at "$(date '+%Y-%m-%d %H:%M')" --argjson items "$items" '{checked_at:$at,items:$items,errors:$ARGS.positional}' --args ${errors[@]+"${errors[@]}"}) &&
        update_cache_write "$cache" || return 1
    (( ${#errors[@]} == 0 ))
}
# "sing-box 1.14.1 → 1.14.3，Snell v6 …" from the cache; empty when nothing is newer.
update_hint() {
    [[ -f $DATA/update-check.json ]] && command -v jq >/dev/null || return 0
    jq -r '[.items[]?|select(.newer)|"\(.name) \(.current // "未知") → \(.latest)"]|join("，")' "$DATA/update-check.json" 2>/dev/null || true
}
update_summary() {
    local file=$DATA/update-check.json
    if systemctl is-enabled --quiet "$CHECK_UNIT.timer" 2>/dev/null; then
        msg '每日检查：已开启（每天凌晨只查一次版本号，不下载、不重启）'
    else msg '每日检查：已关闭'; fi
    if [[ ! -f $file ]]; then msg '还没有检查过新版本。'
    elif ! jq -r '"上次检查：\(.checked_at)",
          (.items[]|"  \(.name)：当前 \(.current // "未知")，最新 \(.latest // "未查到")\(if .newer then "（可更新）" else "" end)"),
          (.errors[]?|"  \(.)")' "$file" 2>/dev/null; then
        msg '检查记录无法读取，下次检查会重写。'
    fi
}
update_check_install() {
    cat > "/etc/systemd/system/$CHECK_UNIT.service" <<UNIT
[Unit]
Description=srm daily version check (version numbers only: no download, no restart)
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/srm update-check run
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA
CapabilityBoundingSet=
UNIT
    cat > "/etc/systemd/system/$CHECK_UNIT.timer" <<'UNIT'
[Unit]
Description=srm daily version check
[Timer]
OnCalendar=*-*-* 02:00:00
RandomizedDelaySec=4h
Persistent=true
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload
}
# On unless turned off in the menu; reinstalling keeps it off.
update_check_setup() {
    update_check_install || return 1
    [[ -e $DATA/update-check.off ]] || systemctl enable --now "$CHECK_UNIT.timer" >/dev/null 2>&1
}
update_check_set() {
    owned_root || return 1
    case $1 in
      on)
        rm -f "$DATA/update-check.off"
        update_check_setup || { err '每日检查开启失败。'; return 1; }
        msg '每日检查已开启：每天凌晨只查一次版本号，有新版本时在菜单顶部提示。';;
      off)
        touch "$DATA/update-check.off" || return 1
        systemctl disable --now "$CHECK_UNIT.timer" >/dev/null 2>&1 || { err '每日检查关闭失败。'; return 1; }
        rm -f "$DATA/update-check.json"
        msg '每日检查已关闭；需要时在菜单「5. 更新」里选「立即检查新版本」。';;
      *) err '每日检查只能是 on 或 off。'; return 1;;
    esac
}
# Under the lock. Programs of TYPE (or of every type) used by nodes: each variant is
# replaced only when a newer build downloads and verifies, then its enabled nodes'
# services restart; a failed health check puts the previous build back.
update_programs() {
    owned_root || return 1
    local type keys failures=0
    for type in $(program_types); do
        [[ -z ${1:-} || $1 == "$type" ]] || continue
        keys=$(program_keys "$type")
        if [[ -z $keys ]]; then msg "没有 $(proto_call "$type" program_label) 节点，不需要更新。"; continue; fi
        # shellcheck disable=SC2086 # one key per word
        update_program "$type" $keys || failures=1
    done
    return "$failures"
}
update_program() {
    local type=$1 label lines key latest current path tmp units unit failures=0
    shift
    label=$(proto_call "$type" program_label)
    # A variant missing from the lookup fails alone; the others still update.
    lines=$(proto_call "$type" program_latest "$@") || failures=1
    [[ -n $lines ]] || { err "$label 没有更新。"; return 1; }
    # fd 3: downloads and restarts must not read the remaining lines.
    while IFS=$'\t' read -r key latest <&3; do
        current=$(proto_call "$type" program_current "$key")
        if ! version_newer "$latest" "$current"; then
            msg "$label $key 已是最新版本 $current，不需要重启。"; update_cache_mark "$label $key" "$current"; continue
        fi
        path=$(proto_call "$type" program_path "$key")
        tmp=$(mktemp "${path%/*}/.candidate.XXXXXX") || return 1
        if ! proto_call "$type" program_fetch "$key" "$latest" "$tmp"; then
            rm -f "$tmp"; err "$label $key 保持 $current，没有替换。"; failures=1; continue
        fi
        cp -p "$path" "$path.previous" && mv -f "$tmp" "$path" || { rm -f "$tmp"; failures=1; continue; }
        # Services of the enabled nodes running this variant; none, or nodes stopped
        # with sing-box, means nothing to restart: they start the new build later.
        units=''
        if systemctl is-active --quiet "$SERVICE"; then
            units=$(jq -r --arg t "$type" --arg k "$key" "$PROTO_JQ_DEFS .nodes[]|select(.enabled and .type == \$t)|select(($(proto_jq program_key empty)) == \$k)|$(proto_jq sidecar empty)" "$STATE") || units=''
        fi
        local good=1
        for unit in $units; do restart_unit "$unit" || good=0; done
        if [[ $good == 1 ]] && { [[ -z $units ]] || service_healthy "$STATE"; }; then
            printf '%s\n' "$latest" > "${path%/*}/version"
            update_cache_mark "$label $key" "$latest"
            msg "$label $key 已从 $current 更新到 $latest。"
            [[ -n $units ]] || msg '没有正在运行的节点用它，不需要重启；节点下次启动时用新版本。'
            continue
        fi
        mv -f "$path.previous" "$path"
        for unit in $units; do restart_unit "$unit" || true; done
        err "$label $latest 启动后健康检查失败，已恢复 $current。"; failures=1
    done 3<<< "$lines"
    return "$failures"
}
# Called under the same flock as node/configuration changes. The new script's own
# updaters replace sing-box and the programs.
update_all() {
    owned_root || return 1
    local before after backup
    backup=$(mktemp "$SRM_ROOT/.update-before.XXXXXX") || return 1
    cp -p "$SRM_ROOT/manager.sh" "$backup" || return 1
    before=$(sha256 "$backup")
    if ! update_latest; then rm -f "$backup"; return 1; fi
    after=$(sha256 "$SRM_ROOT/manager.sh")
    local rc=0
    bash -c 'source "$1" && declare -F update_core update_programs >/dev/null || exit 3
             rc=0; update_core || rc=1; update_programs || rc=1; exit "$rc"' bash "$SRM_ROOT/manager.sh" || rc=$?
    # sing-box and the programs no longer follow the script's version: their own
    # failure (a lookup or a download) keeps the new script, only a script that does
    # not load is reverted.
    if [[ $rc == 3 && $before != "$after" ]]; then
        mv -f "$backup" "$SRM_ROOT/manager.sh" || return 1
        err '新脚本无法加载，管理脚本已恢复为更新前版本。'
    else rm -f "$backup"; fi
    [[ $rc == 0 ]] || { err '更新没有全部完成，原因见上方；没更新的部分保持原版本。'; return 1; }
}
# Restarting drops every connection: the menu asks "confirm / back" (back by default).
update_confirm() {
    [[ ${assume_yes:-0} != 1 ]] || return 0
    msg '更新需要重启服务，所有连接会断开几秒。'
    msg '  1. 确认更新'
    msg '  0. 返回'
    ask '请选择' 0 || return 1
    [[ $REPLY == 1 ]]
}
# TARGET: all, core, script, programs (all types) or one program type; menu choices
# and `srm update` both come here.
update_run() {
    local target=${1:-all}
    if [[ $target == script ]]; then with_lock update_latest; return; fi
    update_confirm || { msg '已返回，没有更新。'; return 0; }
    case $target in
      all) with_lock update_all;;
      core) with_lock update_core;;
      programs) with_lock update_programs;;
      *) with_lock update_programs "$target";;
    esac
}
update_menu() {
    local labels toggle=off
    labels=$(program_labels)
    msg $'\n更新（不会自动更新；更新 sing-box 或 '"$labels"$' 要重启服务，所有连接会断开几秒）'
    update_summary
    systemctl is-enabled --quiet "$CHECK_UNIT.timer" 2>/dev/null || toggle=on
    msg "
1. 全部更新（脚本、sing-box、$labels）
2. 只更新 sing-box
3. 只更新 $labels
4. 只更新脚本（不重启服务）
5. 立即检查新版本（只查版本号，不下载）
6. $(if [[ $toggle == off ]]; then printf '关闭'; else printf '开启'; fi)每日检查
7. 回滚配置
8. 回滚脚本
0. 返回"
    ask '请选择' || return 0
    case $REPLY in
      1) update_run all;;
      2) update_run core;;
      3) update_run programs;;
      4) update_run script;;
      5) update_check_run; update_summary;;
      6) with_lock update_check_set "$toggle";;
      7) yesno '恢复上一份配置（影响本脚本节点）' && with_lock rollback_config;;
      8) with_lock rollback_script;;
      *) err '无效选项。';;
    esac
}
restart_nodes() {
    owned_root || return 1
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    if [[ $(jq '[.nodes[]|select(.enabled)]|length' "$STATE") == 0 ]]; then msg '没有启用的节点。'; return 0; fi
    "$CORE" check -c "$DATA/current/config.json" && sidecars_sync "$STATE" && restart_unit "$SERVICE" && service_healthy "$STATE"
}
