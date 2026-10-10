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
    # Rules limited to disjoint sets of nodes never meet the same connection.
    jq -r --arg name "${2:-}" '
      def shared($a; $b): $a.inbounds == null or $b.inbounds == null or any($a.inbounds[]; . as $i | any($b.inbounds[]; . == $i));
      .policies as $p |
      range(0; $p|length) as $i | range($i+1; $p|length) as $j |
      $p[$i] as $a | $p[$j] as $b |
      select($a.mode != $b.mode and shared($a; $b) and ($name == "" or $a.name == $name or $b.name == $name)) |
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
    jq '(.nodes|map({key:.id,value:.name})|from_entries) as $names |
      {unlock_dns,egress:(if .egress then (.egress|del(.password)) else null end),
       policies:[.policies[]|. + {nodes:(if .inbounds then [.inbounds[]|$names[.]] else "全部节点" end)}]}' "$STATE" || return 1
    if ! routing_check_conflicts "$STATE"; then msg '已有规则保持原状，重叠部分按当前配置由代理规则优先处理。'; fi
    return 0
}
routing_menu() {
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    msg '解锁 DNS 需要客户端把域名或 DNS 查询交给本服务器；仅发送已解析 IP 时，SNI 嗅探不会自动重写该 IP。指定代理出口可按可识别的域名分流。'
    msg '流媒体分流：1.查看 2.设置解锁 DNS 3.设置代理出口（SOCKS5） 4.添加/替换平台规则 5.删除平台规则'
    ask '操作' 1 || return 0
    local host port user name mode domains scope
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
        routing_scope_select "$name" || return 0; scope=$REPLY
        routing_change add "$name" "$mode" "$domains" ${scope:+--nodes "$scope"};;
      5) ask '要删除的规则名称' || return 0; routing_change del "$REPLY";;
      *) err '无效选项。'; return 1;;
    esac
}
# Picks the nodes rule NAME applies to by menu number. REPLY = comma-separated
# node IDs, "all" for every node, or empty to keep an existing rule's scope
# (every node for a new rule). Replacing a rule offers its current nodes first.
routing_scope_select() {
    local count index=0 name type port picks pick ids='' current default=全部
    count=$(jq '.nodes|length' "$STATE") || return 1
    REPLY=''
    (( count > 1 )) || return 0
    current=$(jq -r --arg name "$1" '. as $s | .policies[]|select(.name==$name and .inbounds)|
      [.inbounds[] as $i | $s.nodes|map(.id)|index($i)+1|tostring]|join(" ")' "$STATE") || return 1
    [[ -z $current ]] || default=$current
    msg '作用范围（可以只让部分节点走这条规则）：'
    while IFS=$'\t' read -r name type port; do
        index=$((index+1))
        printf '  %s. %s | %s | 端口 %s\n' "$index" "$name" "$type" "$port"
    done < <(jq -r '.nodes[]|[.name,.type,(.port|tostring)]|@tsv' "$STATE")
    ask "节点序号，多个用空格分隔（输入「全部」= 所有节点）" "$default" || return 1
    [[ $REPLY != 全部 ]] || { REPLY=all; return 0; }
    [[ $REPLY =~ ^[0-9\ ]+$ ]] || { err "请输入 1–$count 的序号。"; return 1; }
    picks=$REPLY
    for pick in $picks; do
        [[ $pick =~ ^[1-9][0-9]{0,5}$ ]] && (( pick <= count )) || { err "请输入 1–$count 的序号。"; return 1; }
        ids+=${ids:+,}$(jq -r --argjson i "$((pick-1))" '.nodes[$i].id' "$STATE") || return 1
    done
    [[ -n $ids ]] || { err "请输入 1–$count 的序号。"; return 1; }
    REPLY=$ids
}
# Comma-separated node IDs → JSON array; every ID must name an existing node.
routing_node_ids() {
    local list
    list=$(jq -c --arg ids "$2" '[$ids|split(",")[]|select(length>0)]|unique' <<< null) || return 1
    jq -e --argjson ids "$list" '. as $s | ($ids|length) > 0 and all($ids[]; . as $i | any($s.nodes[]; .id == $i))' "$1" >/dev/null ||
        { err "节点 ID 不存在：$2（在节点管理里查看 ID）"; return 1; }
    printf '%s\n' "$list"
}
# Non-interactive routing changes, shared with the menu:
#   dns IP | egress HOST PORT [USER] (password read from stdin) | del NAME
#   add NAME dns|proxy DOMAIN… [--nodes ID,ID…|all]
#     --nodes limits the rule to those nodes, "all" makes it apply to every node;
#     without it a replaced rule keeps its nodes and a new rule applies to every node.
# Domain arguments may also hold several space-separated suffixes.
routing_change() {
    local op=${1:-} candidate tmp host port user pass='' name mode domains nodes='' rc=1 max=0 arg suffixes=()
    [[ -f $STATE ]] || { err '请先部署节点。'; return 1; }
    shift
    case $op in dns|del) max=1;; egress) max=3;; esac
    (( max == 0 || $# <= max )) || { err "多余的参数：${*:max+1}"; return 1; }
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
        elif [[ -n $user ]] && ! read_secret '密码（不回显）'; then err '没有从标准输入读到密码，未修改。'
        else
            [[ -z $user ]] || pass=$REPLY
            jq --arg host "$host" --argjson port "$port" --arg user "$user" --arg pass "$pass" '.egress={type:"socks",version:"5",server:$host,server_port:$port} + (if $user!="" then {username:$user,password:$pass} else {} end)' "$candidate" > "$tmp" && rc=0
        fi;;
      add)
        name=${1:-} mode=${2:-}
        shift 2 2>/dev/null || shift $#
        while (( $# )); do
            arg=$1; shift
            if [[ $arg == --nodes ]]; then nodes=${1:-,}; shift $(( $# ? 1 : 0 ))
            else suffixes+=("$arg"); fi
        done
        if [[ -z $name ]] || (( ${#suffixes[@]} == 0 )); then err '用法：srm routing add 名称 dns|proxy 域名后缀… [--nodes 节点ID,…|all]'
        elif [[ $mode != dns && $mode != proxy ]]; then err '方式只能是 dns 或 proxy。'
        elif [[ -n $nodes && $nodes != all ]] && ! nodes=$(routing_node_ids "$candidate" "$nodes"); then :
        else
            [[ -n $nodes ]] || nodes=$(jq -c --arg name "$name" 'first(.policies[]|select(.name==$name)|.inbounds) // null' "$candidate") || nodes=null
            [[ $nodes != all ]] || nodes=null
            domains=$(printf '%s\n' "${suffixes[@]}" | jq -Rsc 'split("\n")|map(split(" ")[])|map(select(length>0)|ascii_downcase)|unique') &&
            jq --arg name "$name" --arg mode "$mode" --argjson domains "$domains" --argjson nodes "$nodes" '
              .policies=(.policies|map(select(.name!=$name)))+[{name:$name,mode:$mode,domains:$domains} + (if $nodes then {inbounds:$nodes} else {} end)]' "$candidate" > "$tmp" &&
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
