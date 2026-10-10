menu_header() {
    local status='未部署' counts='0 / 0' renew='未配置' routing='未启用' updates color='' reset=''
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
    # Versions come from the daily check's cache; the menu never looks them up.
    updates=$(update_hint)
    printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$color" "$reset"
    printf '  sing-box-reality-manager (srm)  v%s\n' "$SRM_VERSION"
    printf '  %s\n' "$(proto_labels 3)"
    printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$color" "$reset"
    printf '  服务：%s    节点：%s（启用 / 总数）\n' "$status" "$counts"
    printf '  分流：%s    证书续期：%s\n' "$routing" "$renew"
    [[ -z $updates ]] || printf '  可更新：%s（选 5 更新）\n' "$updates"
    printf '\n'
}
main_menu() {
    require_linux || return 1
    # Leaving quick deploy without a node is fine here; `srm add` treats it as a failure.
    local IN_MENU=1
    # A v3 installation whose nodes have not moved: offered before anything else.
    if migrate_offered; then menu_header; migrate_offer; fi
    # No node yet: straight into quick deploy; 0 there shows the menu.
    if [[ ! -f $STATE ]] || ! jq -e '.nodes|length > 0' "$STATE" >/dev/null 2>&1; then
        menu_header
        with_lock node_add "$SRM_SELF"
    fi
    while :; do
        menu_header
        msg $'  1. 添加节点 · 快速部署\n  2. 节点管理 · 链接 / 二维码 / 完整配置\n  3. 流媒体分流 · 解锁 DNS / 代理出口\n  4. 运行状态 · 日志 / 重启 / 防火墙\n  5. 更新 · 新版本检查 / 回滚\n  6. BBR 与系统检测\n  7. 卸载\n  8. 证书管理 · 到期时间 / 自动续期'
        ! migrate_pending || msg '  9. 迁移旧版节点 · 发现 v3 安装'
        msg $'\n  0. 退出\n'
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
          9) if migrate_pending; then migrate_menu; else err '无效选项。'; fi;;
          *) err '无效选项。';;
        esac
    done
}
status_menu() {
    show_status
    msg $'\n1.查看最近 50 行日志（分享前请检查敏感信息）\n2.重启本脚本节点（连接会断开几秒）\n3.重新同步防火墙端口规则\n0.返回'
    ask '请选择' || return 0
    case $REPLY in
      1) show_logs;;
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
  srm add [协议] [选项]   部署节点，协议：$PROTOCOLS；不写协议时打开快速部署列表
                            --port 端口|random  --domain 证书域名（需要证书的协议；先检查解析到本机）
                            --name 名称  --host 客户端连接的地址（默认自动检测本机公网 IP）
                            --yes（不提问，未给的选项用默认值）  --json（结果输出为 JSON，其余信息写到 stderr）
                            进阶：--sni 域名（Reality / ShadowTLS 的伪装目标，要通过检测；或证书域名）
                            --cert auto|webroot|import|selfsigned（自签只用于客户端能校验证书指纹的协议）
                            --webroot 目录  --cert-file 文件  --key-file 文件  --email 邮箱
                            --transport tcp|ws|grpc|httpupgrade（只用于能选传输方式的协议）
                            --proto-version 6|5  --proto-mode default|unshaped（只用于 Snell：版本和 v6 模式）
                            --hop off|auto|起-止（只用于 Hysteria2：端口跳跃，默认 off；auto = 20000 起第一段
                            空闲的 1000 个端口；开启后范围内的 UDP 转到节点端口）
                            --bbr enable|keep
  srm list                列出节点：ID、名称、协议、端口、状态
  srm nodes               节点管理菜单：原始链接、二维码、启停、改端口、重置凭据
  srm node ID 操作 [值]   toggle | delete | rotate | port 端口 | name 名称 | retarget 伪装目标域名
                          | hop off|auto|起-止（端口跳跃）
  srm export ID [格式]    uri（默认）| qr | outbound（sing-box）| clash | surge | clients（全部客户端）| details
                          只在本机生成，不联网
  srm profile 客户端 [ID]  完整客户端配置（含节点、国内直连的基本分流和 DNS），客户端：$PROFILE_CLIENTS
                          （clash = Clash Verge / Clash Meta for Android）；不写 ID 为全部启用的节点；只在本机生成
  srm profile-link 客户端 [ID] [--port 端口] [--minutes 分钟]
                          临时导入链接：在随机路径上开一个临时下载端口，下载一次或到时间（默认 10 分钟）
                          自动关闭并撤掉防火墙放行；给出二维码和该 App 的一键导入链接
  srm protocols           支持的协议和传输层
  srm routing [show]      流媒体分流菜单；show 只查看
  srm routing dns IP      设置解锁 DNS
  srm routing egress 地址 [端口] [用户名]   设置 SOCKS5 代理出口；有用户名时从标准输入读密码
  srm routing add 名称 dns|proxy 域名… [--nodes ID,…|all]
                          添加或替换平台规则（netflix.com 等域名后缀）；--nodes 只对这些节点生效，
                          all 对所有节点；不写时替换的规则保留原来的节点
  srm routing del 名称    删除平台规则
  srm certs [status]      证书管理；status 只查看
  srm renew               检查证书续期
  srm firewall            同步本脚本的 UFW / firewalld / iptables 端口规则和端口跳跃转发
  srm firewall-restore    按当前节点补回防火墙端口规则和端口跳跃转发（服务每次启动前自动运行；
                          别的操作正在进行时只补端口跳跃转发，端口规则由那个操作同步）
  srm hop-sync            旧版服务单元用的名字，同 firewall-restore
  srm status              运行状态
  srm logs                最近 50 行日志
  srm restart             重启本脚本节点
  srm rollback            恢复上一份节点配置
  srm rollback-script     恢复上一个版本的脚本
  srm bbr [status|on]     查看或开启 BBR + FQ
  srm update [core|$(program_types | tr '\n' '|')script] [--yes]
                          手动更新，不写为全部（脚本、sing-box、$(program_labels)）；core 只更新 sing-box，
                          $(program_types | paste -sd / -) 只更新 $(program_labels)，script 只更新脚本（不重启服务）；
                          更新 sing-box 或 $(program_labels) 会重启服务、断开连接几秒，--yes 跳过确认
  srm update-check [on|off|status|run]
                          每日检查新版本（只查版本号，不下载、不重启）：开启、关闭、查看（默认）、立即检查
  srm migrate [--apply] [--yes] [--host 地址]
                          迁移旧版（v3，$V3_ROOT）的节点：默认只预览能迁移和不能迁移的内容；
                          --apply 执行（停止旧服务，srm 在原端口接管，失败恢复旧服务），--yes 不再确认
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
      # Installed from a terminal: the menu opens right away (quick deploy without nodes).
      install) with_lock setup "$SRM_SELF" || return 1; if [[ -t 0 && -t 1 ]]; then main_menu; fi;;
      add) shift; with_lock node_add "$SRM_SELF" "$@";;
      list) require_root && list_nodes;;
      nodes) require_linux && node_menu;;
      node)
        [[ -n ${2:-} && -n ${3:-} ]] || { err '用法：srm node ID toggle|delete|rotate|port 端口|name 名称|retarget 目标域名|hop off|auto|起-止'; return 1; }
        with_lock node_change "$2" "$3" "${4:-}";;
      export) require_root && export_node "${2:-}" "${3:-uri}";;
      profile) require_root && profile_render "${2:-}" "$STATE" "${3:-}";;
      profile-link)
        local client=${2:-} id='' port='' minutes=10
        shift 2 2>/dev/null || shift
        while (( $# )); do
            case $1 in
              --port|--minutes)
                [[ $# -ge 2 && -n $2 ]] || { err "$1 需要一个值。"; return 1; }
                if [[ $1 == --port ]]; then port=$2; else minutes=$2; fi
                shift 2; continue;;
              -*) err "未知参数：$1（可用参数见 srm --help）"; return 1;;
              *) id=$1;;
            esac
            shift
        done
        [[ $minutes =~ ^[1-9][0-9]{0,3}$ ]] || { err '--minutes 要是 1–9999 的整数。'; return 1; }
        with_lock profile_link "$client" "$id" "$port" "$((minutes * 60))";;
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
      # Run by srm.service before every start (also at boot), possibly while a locked
      # transaction restarts the service; hop-sync is its name in units written before.
      firewall-restore|hop-sync) require_root && firewall_restore;;
      status) require_linux && show_status;;
      logs) require_linux && show_logs;;
      restart) with_lock restart_nodes;;
      rollback) with_lock rollback_config;;
      rollback-script) with_lock rollback_script;;
      bbr)
        case ${2:-status} in
          status) require_linux && bbr_status;; on) with_lock bbr_enable;;
          *) err '用法：srm bbr [status|on]'; return 1;;
        esac;;
      update)
        local target=all
        shift
        while (( $# )); do
            case $1 in
              -y|--yes) assume_yes=1;;
              all|core|script) target=$1;;
              *)
                proto_has "$1" program_latest || { err "用法：srm update [core|$(program_types | tr '\n' '|')script] [--yes]"; return 1; }
                target=$1;;
            esac
            shift
        done
        require_linux && update_run "$target";;
      update-check)
        case ${2:-status} in
          on|off) with_lock update_check_set "$2";;
          status) require_linux && update_summary;;
          run) require_linux && update_check_run;;
          *) err '用法：srm update-check [on|off|status|run]'; return 1;;
        esac;;
      migrate) shift; migrate_command "$@";;
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
