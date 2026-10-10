# All mutation menu paths execute under with_lock.
# node_add SELF [TYPE] [--name N] [--host H] [--port P|random] [--sni D] [--cert auto|webroot|import]
#          [--webroot DIR] [--cert-file F] [--key-file F] [--email E] [--bbr enable|keep] [--yes]
node_add() {
    local self=$1 type='' name host port sni='' bbr=keep candidate node id tmp transport var assume_yes=0
    local opt_name='' opt_host='' opt_port='' opt_sni='' opt_cert='' opt_webroot='' opt_cert_file='' opt_key_file='' opt_email='' opt_bbr=''
    # Protocol prompt hooks fill these.
    local mode=none email='' webroot='' cert='' key=''
    shift
    if [[ -n ${1:-} && $1 != -* ]]; then type=$1; shift; fi
    while (( $# )); do
        case $1 in
          -y|--yes) assume_yes=1; shift; continue;;
          --name|--host|--port|--sni|--cert|--webroot|--cert-file|--key-file|--email|--bbr) ;;
          *) err "未知参数：$1（可用参数见 srm --help）"; return 1;;
        esac
        [[ $# -ge 2 && -n $2 ]] || { err "$1 需要一个值。"; return 1; }
        var=${1#--}; var=opt_${var//-/_}
        printf -v "$var" '%s' "$2"
        shift 2
    done
    if [[ -z $type ]]; then
        if [[ $assume_yes == 1 ]]; then err "非交互模式需要指定协议：$PROTOCOLS"; return 1; fi
        local t i=0
        msg '部署节点（任一步输入 0 返回；同一协议可以部署多个节点，端口和凭据各自独立）'
        for t in $PROTOCOLS; do i=$((i+1)); printf '%s. %s\n' "$i" "$(proto_call "$t" label)"; done
        ask '协议' 1 || return 1
        type=$(proto_by_index "$REPLY") || { err "请选择 1–$i。"; return 1; }
    fi
    proto_known "$type" || { err "不支持的协议：$type（可选：$PROTOCOLS）"; return 1; }
    ask_opt "$opt_name" '节点名称' "$(default_node_name "$type")" || return 1; name=$REPLY
    ask_opt "$opt_host" '客户端连接的服务器 IP 或域名（域名需 DNS only 灰云）' || return 1; host=$REPLY
    valid_host "$host" || { err '地址不合法。'; return 1; }
    ask_opt "$opt_port" '端口：1–65535，回车随机（10000–50000 里的空闲端口）' random || return 1; port=$REPLY
    if [[ $port != random ]]; then valid_port "$port" || { err '端口必须在 1–65535。'; return 1; }; fi
    proto_call "$type" prompt || return 1
    valid_domain "$sni" || { err '域名不合法，请使用 ASCII/Punycode 域名。'; return 1; }
    if [[ ! -f $STATE ]]; then
        [[ -n $opt_bbr || $assume_yes == 1 ]] || msg 'BBR：1.内核支持时自动启用（主机级 TCP 设置） 2.保持现状（与现有程序共存时选择）'
        ask_opt "$opt_bbr" 'BBR 设置' 2 || return 1
        case $REPLY in 1|enable) bbr=enable;; 2|keep) bbr=keep;; *) err '无效选项。'; return 1;; esac
    fi
    msg "部署：$name / $(proto_call "$type" label) / $host:$port / $sni"
    if [[ $assume_yes != 1 ]]; then yesno '开始安装缺失依赖、申请证书并部署' || return 0; fi
    [[ -f $SRM_ROOT/.srm-owned ]] || setup "$self" || return 1
    ensure_dependencies || return 1
    if [[ $port == random ]]; then port=$(choose_port) || return 1; else port_free "$port" || { err '端口被占用，原服务未改动。'; return 1; }; fi
    id=$(random_hex 8) || return 1
    proto_call "$type" create || return 1
    node=$(jq -n --arg id "$id" --arg name "$name" --arg host "$host" --arg sni "$sni" --arg type "$type" --argjson port "$port" --argjson fields "$REPLY" \
        '{id:$id,name:$name,host:$host,sni:$sni,port:$port,type:$type,enabled:true} + $fields') || return 1
    if [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) == 1 ]]; then
        node=$(printf '%s' "$node" | jq '.listen="0.0.0.0"') || return 1
    fi
    candidate=$(new_candidate) || return 1
    tmp=$(mktemp) || return 1
    jq --argjson n "$node" '.nodes += [$n]' "$candidate" > "$tmp" && mv "$tmp" "$candidate" || return 1
    if apply_state "$candidate"; then
        rm -f "$candidate"
        if [[ $bbr == enable ]]; then
            if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr ]]; then msg 'BBR 已开启。'; else bbr_enable || msg '节点已部署；BBR 未启用，原因见上方。'; fi
        fi
        transport=$(proto_call "$type" transport | tr '[:lower:]' '[:upper:]')
        msg "节点 ID：$id"
        msg "节点端口：${port}/${transport}；如仍无法连接，请在服务商控制台的云安全组允许 ${transport} ${port}。"
        printf '%s' "$node" | share_uri
        msg '二维码、详情和客户端配置：在菜单里选「2. 节点管理」。'
        return 0
    fi
    rm -f "$candidate"; return 1
}
# Another node of the same protocol gets a numbered default name: <type>, <type>-2, …
default_node_name() {
    local name=$1 n=1
    [[ -f $STATE ]] || { printf '%s\n' "$name"; return 0; }
    while jq -e --arg n "$name" 'any(.nodes[]; .name == $n)' "$STATE" >/dev/null; do
        n=$((n+1)); name=$1-$n
    done
    printf '%s\n' "$name"
}
# Viewing nodes never touches the network: links and QR codes are built locally.
export_node() {
    local id=$1 format=$2 node type link
    node=$(node_json "$STATE" "$id") || { err '节点不存在。'; return 1; }
    type=$(printf '%s' "$node" | jq -r .type)
    case $format in
      uri) printf '%s' "$node" | share_uri;;
      qr)
        link=$(printf '%s' "$node" | share_uri) || return 1
        if command -v qrencode >/dev/null; then
            if use_color; then printf '%s' "$link" | qrencode -t ANSIUTF8; else printf '%s' "$link" | qrencode -t UTF8; fi
        else msg '未安装 qrencode，只显示链接：'; msg "$link"; fi;;
      outbound) printf '%s' "$node" | client_outbound;;
      details)
        printf '%s' "$node" | jq "del($(proto_call "$type" secrets))" || return 1
        if [[ $(printf '%s' "$node" | jq -r '.cert_dir // empty') ]]; then
            openssl x509 -in "$(printf '%s' "$node" | jq -r .cert_dir)/fullchain.pem" -noout -subject -enddate
        fi;;
      *) err '格式只能是 uri、qr、outbound 或 details。'; return 1;;
    esac
}
list_nodes() {
    [[ -f $STATE ]] || { msg '尚无节点。'; return 0; }
    jq -r '.nodes[]|[.id,.name,.type,(.port|tostring),(if .enabled then "启用" else "停用" end)]|@tsv' "$STATE"
}
node_change() {
    local id=$1 action=$2 value=${3:-} candidate tmp type node dropped='' name
    candidate=$(new_candidate) || return 1
    node=$(node_json "$candidate" "$id") || { rm -f "$candidate"; err '节点不存在。'; return 1; }
    type=$(printf '%s' "$node" | jq -r .type)
    tmp=$(mktemp) || return 1
    case $action in
      toggle)
        if [[ $(printf '%s' "$node" | jq -r .enabled) == false ]]; then
            port_free "$(printf '%s' "$node" | jq -r .port)" "$id" || { rm -f "$tmp" "$candidate"; err '端口被占用，无法启用。'; return 1; }
        fi
        jq --arg id "$id" '(.nodes[]|select(.id==$id)|.enabled) |= not' "$candidate" > "$tmp";;
      delete)
        # Rules limited to this node lose it; a rule left with no node goes too.
        dropped=$(jq -r --arg id "$id" '.policies[]|select(.inbounds == [$id])|.name' "$candidate") || dropped=''
        jq --arg id "$id" '.nodes |= map(select(.id!=$id)) |
          .policies |= map(if .inbounds then .inbounds -= [$id] else . end | select(.inbounds != []))' "$candidate" > "$tmp";;
      port)
        port_free "$value" "$id" || { rm -f "$tmp" "$candidate"; err '端口无效或被占用。'; return 1; }
        jq --arg id "$id" --argjson p "$value" '(.nodes[]|select(.id==$id)|.port)=$p' "$candidate" > "$tmp";;
      name)
        [[ -n $value ]] || { rm -f "$tmp" "$candidate"; err '名称不能为空。'; return 1; }
        jq --arg id "$id" --arg name "$value" '(.nodes[]|select(.id==$id)|.name)=$name' "$candidate" > "$tmp";;
      retarget)
        proto_has "$type" retarget || { rm -f "$tmp" "$candidate"; err '此协议的节点不支持切换握手目标。'; return 1; }
        proto_call "$type" retarget "$node" "$value" || { rm -f "$tmp" "$candidate"; return 1; }
        [[ -n $REPLY ]] || { rm -f "$tmp" "$candidate"; return 0; }
        jq --arg id "$id" --argjson f "$REPLY" '(.nodes[]|select(.id==$id)) += $f' "$candidate" > "$tmp";;
      rotate)
        proto_call "$type" rotate || { rm -f "$tmp" "$candidate"; return 1; }
        jq --arg id "$id" --argjson f "$REPLY" '(.nodes[]|select(.id==$id)) += $f' "$candidate" > "$tmp";;
      *) rm -f "$tmp" "$candidate"; err '操作只能是 toggle、port、name、rotate、retarget 或 delete。'; return 1;;
    esac
    local rc=1
    if mv "$tmp" "$candidate" && apply_state "$candidate"; then
        rc=0
        while IFS= read -r name; do [[ -z $name ]] || msg "分流规则「$name」只作用于这个节点，已一并删除。"; done <<< "$dropped"
    fi
    rm -f "$candidate" "$tmp"
    return "$rc"
}
node_menu() {
    [[ -f $STATE ]] || { msg '尚无节点。'; return 0; }
    local count index=0 id name type port status
    count=$(jq '.nodes|length' "$STATE") || return 1
    (( count > 0 )) || { msg '尚无节点，请先部署。'; return 0; }
    msg $'\n已部署节点：'
    while IFS=$'\t' read -r name type port status; do
        index=$((index+1))
        printf '  %s. %s | %s | 端口 %s | %s\n' "$index" "$name" "$type" "$port" "$status"
    done < <(jq -r '.nodes[]|[.name,.type,(.port|tostring),(if .enabled then "启用" else "停用" end)]|@tsv' "$STATE")
    ask '节点序号（也可输入完整 ID；0 返回）' || return 0
    id=$REPLY
    if [[ $REPLY =~ ^[1-9][0-9]{0,5}$ ]] && (( REPLY <= count )); then
        id=$(jq -r --argjson i "$((REPLY-1))" '.nodes[$i].id' "$STATE") || return 1
    fi
    type=$(node_json "$STATE" "$id" | jq -r .type) || { err '节点不存在。'; return 1; }
    msg $'1.详情 2.原始分享链接 3.二维码 4.sing-box 客户端出站\n5.启用/停用 6.修改端口 7.重置凭据 8.修改名称 9.删除'
    ! proto_has "$type" retarget_select || msg "10.$(proto_call "$type" retarget_label)"
    ask '操作' 1 || return 0
    case $REPLY in
      1) export_node "$id" details;; 2) export_node "$id" uri;; 3) export_node "$id" qr;; 4) export_node "$id" outbound;;
      5) with_lock node_change "$id" toggle;;
      6) ask '新端口' || return 0; with_lock node_change "$id" port "$REPLY";;
      7) yesno '旧凭据会失效，确认重置' && with_lock node_change "$id" rotate;;
      8) ask '新名称' || return 0; with_lock node_change "$id" name "$REPLY";;
      9) yesno '确认删除此节点' && with_lock node_change "$id" delete;;
      10)
        proto_has "$type" retarget_select || { err '此协议的节点不支持切换握手目标。'; return 1; }
        proto_call "$type" retarget_select || return 0
        msg '切换后需更新客户端的原始链接 / SNI；端口和凭据保持不变，应用时可能短暂中断本脚本节点。'
        if with_lock node_change "$id" retarget "$REPLY"; then
            msg '当前节点原始链接：'; export_node "$id" uri
        fi;;
      *) err '无效选项。';;
    esac
}
