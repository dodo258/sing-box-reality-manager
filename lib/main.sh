menu_header() {
    local status='未部署' counts='0 / 0' renew='未配置' routing='未启用' color='' reset=''
    if use_color; then color=$'\033[1;36m'; reset=$'\033[0m'; fi
    if [[ -f $SRM_ROOT/.srm-owned ]]; then
        status='已安装，服务未运行'
        systemctl is-active --quiet "$SERVICE" && status='运行中'
    fi
    if [[ -f $STATE ]] && command -v jq >/dev/null; then
        counts=$(jq -r '"\([.nodes[]|select(.enabled)]|length) / \(.nodes|length)"' "$STATE")
        routing=$(jq -r 'if (.policies|length)==0 then "未启用" else "\(.policies|length) 条平台规则" end' "$STATE")
    fi
    systemctl is-active --quiet srm-renew.timer && renew='每日自动检查'
    printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$color" "$reset"
    printf '  sing-box-reality-manager (srm)  v%s\n' "$SRM_VERSION"
    printf '  %s\n' "$(proto_labels)"
    printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$color" "$reset"
    printf '  服务：%s    节点：%s（启用 / 总数）\n' "$status" "$counts"
    printf '  分流：%s    证书续期：%s\n\n' "$routing" "$renew"
}
main_menu() {
    require_linux || return 1
    while :; do
        menu_header
        msg $'  1. 部署节点\n  2. 节点管理 · 原始链接 / 二维码\n  3. 流媒体分流 · 解锁 DNS / 代理出口\n  4. 运行状态 · 日志 / 重启 / 防火墙\n  5. 更新与回滚\n  6. BBR 与系统检测\n  7. 卸载\n  8. 证书管理 · 到期时间 / 自动续期\n\n  0. 退出\n'
        ask '请选择' || return 0
        case $REPLY in
          1) with_lock node_add "$SRM_SELF";;
          2) node_menu;;
          3) with_lock routing_menu;;
          4) status_menu;;
          5) update_menu;;
          6)
            bbr_status
            msg 'BBR 为主机级 TCP 设置。共存测试请保持现状。'
            yesno '当前内核支持时自动开启 BBR + FQ（不更换内核、不重启）' && with_lock bbr_enable;;
          7) with_lock uninstall; [[ -f $SRM_ROOT/.srm-owned ]] || return 0;;
          8) certificate_menu;;
          *) err '无效选项。';;
        esac
    done
}
status_menu() {
    show_status
    msg $'\n1.查看最近 50 行日志（分享前请检查敏感信息）\n2.重启本脚本节点（连接会断开几秒）\n3.重新同步防火墙端口规则\n0.返回'
    ask '请选择' || return 0
    case $REPLY in
      1) journalctl -u "$SERVICE" -n 50 --no-pager;;
      2) yesno '重启会断开所有连接几秒，确认重启' && with_lock restart_nodes;;
      3) with_lock firewall_sync "$STATE";;
      *) err '无效选项。';;
    esac
}
rollback_script() {
    owned_root || return 1
    [[ -f $SRM_ROOT/manager.previous.sh ]] || { err '没有可回滚的脚本版本。'; return 1; }
    bash -n "$SRM_ROOT/manager.previous.sh" && install -m 755 "$SRM_ROOT/manager.previous.sh" "$SRM_ROOT/manager.sh" && msg '脚本已回滚，请重新运行。'
}
usage() {
    cat <<EOF
srm $SRM_VERSION：sing-box 节点管理（$(proto_labels)）
用法：srm [命令] [参数]；任何命令加 --help 显示本帮助。
日常使用只需输入 srm 打开菜单，所有功能都能在菜单里选；下面的命令给进阶用户和自动化脚本。

  srm                     打开管理菜单（常驻，做完回到菜单，输入 0 返回或退出）
  srm menu                同上
  srm install             只安装运行环境（核心、服务、srm / vasma 命令）
  srm add [协议] [选项]   部署节点，协议：$PROTOCOLS
                            --name 名称  --host 地址  --port 端口|random  --sni 域名
                            --cert auto|webroot|import  --webroot 目录  --cert-file 文件  --key-file 文件
                            --email 邮箱  --bbr enable|keep  --yes（不提问，未给的选项用默认值）
  srm list                列出节点：ID、名称、协议、端口、状态
  srm nodes               节点管理菜单：原始链接、二维码、启停、改端口、重置凭据
  srm node ID 操作 [值]   toggle | delete | rotate | port 端口 | name 名称 | retarget 目标域名
  srm export ID [格式]    uri（默认）| qr | outbound | details；只在本机生成，不联网
  srm protocols           支持的协议和传输层
  srm routing [show]      流媒体分流菜单；show 只查看
  srm routing dns IP      设置解锁 DNS
  srm routing egress 地址 [端口] [用户名]   设置 SOCKS5 代理出口；有用户名时从标准输入读密码
  srm routing add 名称 dns|proxy 域名… [--nodes ID,…]
                          添加或替换平台规则（netflix.com 等域名后缀）；--nodes 只对这些节点生效
  srm routing del 名称    删除平台规则
  srm certs [status]      证书管理；status 只查看
  srm renew               检查证书续期
  srm firewall            同步本脚本的 UFW / firewalld 端口规则
  srm status              运行状态
  srm logs                最近 50 行日志
  srm restart             重启本脚本节点
  srm rollback            恢复上一份节点配置
  srm rollback-script     恢复上一个版本的脚本
  srm bbr [status|on]     查看或开启 BBR + FQ
  srm update              更新脚本和已验证核心
  srm update-script       仅更新脚本
  srm update-core         仅更新已验证核心
  srm uninstall [--yes]   卸载（默认需要确认）
  srm render STATE        用 state 文件生成 sing-box 配置（调试用）
  srm version             版本
  srm help                本帮助
EOF
}
list_protocols() {
    local type
    for type in $PROTOCOLS; do printf '%s\t%s\t%s\n' "$type" "$(proto_call "$type" label)" "$(proto_call "$type" transport)"; done
}
main() {
    umask 077
    local arg assume_yes=0
    for arg in "$@"; do
        case $arg in --help|-h) usage; return 0;; esac
    done
    case ${1:-menu} in
      menu) main_menu;;
      install) with_lock setup "$SRM_SELF";;
      add) shift; with_lock node_add "$SRM_SELF" "$@";;
      list) require_root && list_nodes;;
      nodes) require_linux && node_menu;;
      node)
        [[ -n ${2:-} && -n ${3:-} ]] || { err '用法：srm node ID toggle|delete|rotate|port 端口|name 名称|retarget 目标域名'; return 1; }
        with_lock node_change "$2" "$3" "${4:-}";;
      export) require_root && export_node "${2:-}" "${3:-uri}";;
      protocols) list_protocols;;
      routing)
        case ${2:-menu} in
          menu) with_lock routing_menu;; show) require_root && routing_show;;
          dns|egress|add|del) shift; with_lock routing_change "$@";;
          *) err '用法：srm routing [show|dns|egress|add|del]'; return 1;;
        esac;;
      certs)
        require_linux || return 1
        case ${2:-menu} in
          menu) certificate_menu;; status) certificate_status;;
          *) err '用法：srm certs [status]'; return 1;;
        esac;;
      renew) with_lock renew_certificates;;
      firewall) with_lock firewall_sync "$STATE";;
      status) require_linux && show_status;;
      logs) require_linux && journalctl -u "$SERVICE" -n 50 --no-pager;;
      restart) with_lock restart_nodes;;
      rollback) with_lock rollback_config;;
      rollback-script) with_lock rollback_script;;
      bbr)
        case ${2:-status} in
          status) require_linux && bbr_status;; on) with_lock bbr_enable;;
          *) err '用法：srm bbr [status|on]'; return 1;;
        esac;;
      update) with_lock update_all;;
      update-script) with_lock update_latest;;
      update-core) with_lock update_core;;
      uninstall)
        case ${2:-} in -y|--yes) assume_yes=1;; '') ;; *) err '用法：srm uninstall [--yes]'; return 1;; esac
        with_lock uninstall;;
      render)
        [[ -n ${2:-} ]] || { err '用法：srm render STATE'; return 1; }
        local state rc=1
        state=$(mktemp) || return 1
        state_upgrade "$2" > "$state" && render_config "$state" && rc=0
        rm -f "$state"; return "$rc";;
      version|--version) printf 'srm %s / tested core %s\n' "$SRM_VERSION" "$CORE_VERSION";;
      help) usage;;
      *) err "未知命令：$1。可用命令见 srm --help。"; return 1;;
    esac
}
