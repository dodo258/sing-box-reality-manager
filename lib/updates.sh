# Called under the same flock as node/configuration changes.
update_all() {
    owned_root || return 1
    local before after backup
    backup=$(mktemp "$SRM_ROOT/.update-before.XXXXXX") || return 1
    cp -p "$SRM_ROOT/manager.sh" "$backup" || return 1
    before=$(sha256 "$backup")
    if ! update_latest; then rm -f "$backup"; return 1; fi
    after=$(sha256 "$SRM_ROOT/manager.sh")
    # Load the new script's validated core version without reacquiring our lock.
    if bash -c 'source "$1" && update_core' bash "$SRM_ROOT/manager.sh"; then
        rm -f "$backup"
        msg '脚本和已验证核心已检查完成；协议实现随核心更新。'
        return 0
    fi
    if [[ $before != "$after" ]]; then
        mv -f "$backup" "$SRM_ROOT/manager.sh" || return 1
        err '核心更新失败，管理脚本已恢复为更新前版本。'
    else rm -f "$backup"; fi
    return 1
}
# No automatic updates: replacing the core restarts the service and drops connections.
update_menu() {
    msg $'\n更新与回滚（不会自动更新；更新核心要重启服务，所有连接会断开几秒）\n1.一键更新脚本和已验证核心\n2.仅更新脚本（不重启服务）\n3.仅更新已验证核心\n4.回滚配置\n5.回滚脚本\n0.返回'
    ask '请选择' || return 0
    case $REPLY in
      1) yesno '更新会重启服务，所有连接断开几秒，确认更新' && with_lock update_all;;
      2) with_lock update_latest;;
      3) yesno '更新会重启服务，所有连接断开几秒，确认更新' && with_lock update_core;;
      4) yesno '恢复上一份配置（影响本脚本节点）' && with_lock rollback_config;;
      5) with_lock rollback_script;;
      *) err '无效选项。';;
    esac
}
restart_nodes() {
    owned_root || return 1
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    if [[ $(jq '[.nodes[]|select(.enabled)]|length' "$STATE") == 0 ]]; then msg '没有启用的节点。'; return 0; fi
    "$CORE" check -c "$DATA/current/config.json" && sidecars_sync "$STATE" && restart_unit "$SERVICE" && service_healthy "$STATE"
}
