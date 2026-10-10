# Conservative built-in domain groups; exact additions remain visible/editable.
platform_domains() {
    case $1 in
      netflix) printf '%s\n' 'netflix.com nflxvideo.net nflximg.net nflximg.com nflxso.net nflxext.com';;
      disney) printf '%s\n' 'disneyplus.com disney-plus.net dssott.com bamgrid.com';;
      youtube) printf '%s\n' 'youtube.com youtubei.googleapis.com googlevideo.com ytimg.com youtu.be';;
      *) return 1;;
    esac
}
routing_conflicts() {
    # Compare opposite modes only; same-mode rules share the same resolver/outbound.
    # A suffix includes itself and its subdomains, but not lookalike hostnames.
    jq -r --arg name "${2:-}" '
      .policies as $p |
      range(0; $p|length) as $i | range($i+1; $p|length) as $j |
      $p[$i] as $a | $p[$j] as $b |
      select($a.mode != $b.mode and ($name == "" or $a.name == $name or $b.name == $name)) |
      $a.domains[] as $x | $b.domains[] as $y |
      select($x == $y or ($x|endswith("."+$y)) or ($y|endswith("."+$x))) |
      "\($a.name) [\($a.mode)] \($x) ↔ \($b.name) [\($b.mode)] \($y)"
    ' "$1"
}
routing_check_conflicts() {
    local conflicts
    conflicts=$(routing_conflicts "$1" "${2:-}") || return 1
    [[ -n $conflicts ]] || return 0
    err 'DNS 解锁与代理出口的域名范围重叠，请先修改或删除冲突规则：'
    printf '%s\n' "$conflicts" >&2
    return 1
}
routing_show() {
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    jq '{unlock_dns,egress:(if .egress then (.egress|del(.password)) else null end),policies}' "$STATE" || return 1
    if ! routing_check_conflicts "$STATE"; then msg '已有规则保持原状，重叠部分按当前配置由代理规则优先处理。'; fi
    return 0
}
routing_menu() {
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    msg '解锁 DNS 需要客户端把域名或 DNS 查询交给本服务器；仅发送已解析 IP 时，SNI 嗅探不会自动重写该 IP。指定代理出口可按可识别的域名分流。'
    msg '流媒体分流：1.查看 2.设置解锁 DNS 3.设置代理出口（SOCKS5） 4.添加/替换平台规则 5.删除平台规则'
    ask '操作' 1 || return 0
    local host port user name mode domains
    case $REPLY in
      1) routing_show;;
      2) ask '解锁 DNS 的 IP 地址' || return 0; routing_change dns "$REPLY";;
      3)
        msg '只把命中平台的流量送到此 SOCKS5 出口。出口需支持 UDP 才能承载 QUIC；不会自动回落本机。'
        ask '出口 IP/域名' || return 0; host=$REPLY
        ask '出口端口' 1080 || return 0; port=$REPLY
        ask '用户名（无认证则留空）' || return 0; user=$REPLY
        routing_change egress "$host" "$port" "$user";;
      4)
        ask '平台：netflix / disney / youtube / 自定义名称' netflix || return 0; name=$REPLY
        domains=$(platform_domains "$name") || domains=''
        ask '匹配域名后缀，空格分隔（会显示完整范围）' "$domains" || return 0; domains=$REPLY
        ask '方式：dns 或 proxy' dns || return 0; mode=$REPLY
        routing_change add "$name" "$mode" "$domains";;
      5) ask '要删除的规则名称' || return 0; routing_change del "$REPLY";;
      *) err '无效选项。'; return 1;;
    esac
}
# Non-interactive routing changes, shared with the menu:
#   dns IP | egress HOST PORT [USER] (password read from stdin) | add NAME dns|proxy DOMAIN… | del NAME
# Domain arguments may also hold several space-separated suffixes.
routing_change() {
    local op=${1:-} candidate tmp host port user pass='' name mode domains rc=1
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    shift
    candidate=$(new_candidate) || return 1
    tmp=$(mktemp) || { rm -f "$candidate"; return 1; }
    case $op in
      dns)
        host=${1:-}
        if [[ $host =~ ^[0-9.]+$ || $host =~ ^[0-9a-fA-F:]+$ ]] && valid_ip "$host"; then
            jq --arg host "$host" '.unlock_dns=$host' "$candidate" > "$tmp" && rc=0
        else err '解锁 DNS 请输入 IP。'; fi;;
      egress)
        host=${1:-} port=${2:-1080} user=${3:-}
        if ! valid_host "$host"; then err '出口地址无效。'
        elif ! [[ $port =~ ^[1-9][0-9]{0,4}$ ]] || ((port > 65535)); then err '出口端口无效。'
        else
            if [[ -n $user ]]; then
                printf '密码（不回显，无认证则留空）：' >&2; IFS= read -rs pass || pass=''; printf '\n' >&2
            fi
            jq --arg host "$host" --argjson port "$port" --arg user "$user" --arg pass "$pass" '.egress={type:"socks",version:"5",server:$host,server_port:$port} + (if $user!="" then {username:$user,password:$pass} else {} end)' "$candidate" > "$tmp" && rc=0
        fi;;
      add)
        name=${1:-} mode=${2:-}
        shift 2 2>/dev/null || shift $#
        if [[ -z $name ]] || (( $# == 0 )); then err '用法：srm routing add 名称 dns|proxy 域名后缀…'
        elif [[ $mode != dns && $mode != proxy ]]; then err '方式只能是 dns 或 proxy。'
        else
            domains=$(printf '%s\n' "$@" | jq -Rsc 'split("\n")|map(split(" ")[])|map(select(length>0)|ascii_downcase)|unique') &&
            jq --arg name "$name" --arg mode "$mode" --argjson domains "$domains" '.policies=(.policies|map(select(.name!=$name)))+[{name:$name,mode:$mode,domains:$domains}]' "$candidate" > "$tmp" &&
            routing_check_conflicts "$tmp" "$name" && rc=0
        fi;;
      del)
        name=${1:-}
        if jq -e --arg name "$name" 'any(.policies[]; .name==$name)' "$candidate" >/dev/null; then
            jq --arg name "$name" '.policies|=map(select(.name!=$name))' "$candidate" > "$tmp" && rc=0
        else err "没有名为 ${name:-空} 的规则。"; fi;;
      *) err '用法：srm routing [show|dns|egress|add|del]';;
    esac
    if [[ $rc == 0 ]]; then
        rc=1
        if mv "$tmp" "$candidate" && apply_state "$candidate"; then rc=0; fi
    fi
    rm -f "$candidate" "$tmp"
    return "$rc"
}
