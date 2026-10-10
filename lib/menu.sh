# All mutation menu paths execute under with_lock.
# node_add SELF [TYPE] [--name N] [--host H] [--port P|random] [--domain D] [--sni D]
#          [--cert auto|webroot|import|selfsigned] [--webroot DIR] [--cert-file F] [--key-file F]
#          [--email E] [--transport tcp|ws|grpc|httpupgrade] [--proto-version V] [--proto-mode M]
#          [--bbr enable|keep] [--yes] [--json]
# Interactive (the menu, `srm add` without --yes): without TYPE the quick-deploy list
# opens. Only the domain is typed (protocols that need a certificate); besides it at
# most two questions with defaults: the protocol's own one, port, name. The server
# address, handshake target and certificate method are chosen automatically.
# --json prints one JSON object on stdout and everything else on stderr. Outside the
# menu, leaving without a new node is a failure (exit code non-zero, no JSON).
node_add() {
    local self=$1 arg json=0 rc=0
    shift
    for arg in "$@"; do [[ $arg != --json ]] || json=1; done
    DEPLOYED_NODE=''
    if [[ $json == 0 ]]; then node_add_main "$self" "$@" || rc=$?
    else node_add_main "$self" "$@" >&2 || rc=$?; fi
    [[ $rc == 0 ]] || return "$rc"
    if [[ -z $DEPLOYED_NODE ]]; then
        [[ -n ${IN_MENU:-} ]] || { err '没有部署节点。'; return 1; }
        return 0
    fi
    [[ $json == 0 ]] || deploy_json <<< "$DEPLOYED_NODE"
}
node_add_main() {
    local self=$1 type='' var assume_yes=0 rc
    local opt_name='' opt_host='' opt_port='' opt_domain='' opt_sni='' opt_cert='' opt_webroot='' opt_cert_file='' opt_key_file='' opt_email='' opt_bbr='' opt_transport=''
    local opt_proto_version='' opt_proto_mode=''
    shift
    if [[ -n ${1:-} && $1 != -* ]]; then type=$1; shift; fi
    while (( $# )); do
        case $1 in
          -y|--yes) assume_yes=1; shift; continue;;
          --json) shift; continue;;
          --name|--host|--port|--domain|--sni|--cert|--webroot|--cert-file|--key-file|--email|--transport|--proto-version|--proto-mode|--bbr) ;;
          *) err "未知参数：$1（可用参数见 srm --help）"; return 1;;
        esac
        [[ $# -ge 2 && -n $2 ]] || { err "$1 需要一个值。"; return 1; }
        var=${1#--}; var=opt_${var//-/_}
        printf -v "$var" '%s' "$2"
        shift 2
    done
    if [[ -n $type ]]; then
        proto_known "$type" || { err "不支持的协议：$type（可选：$PROTOCOLS）"; return 1; }
    elif [[ $assume_yes == 1 ]]; then err "非交互模式需要指定协议：$PROTOCOLS"; return 1; fi
    # 3 from node_deploy: the user went back or has no domain; the list comes (back).
    while :; do
        if [[ -z $type ]]; then quick_pick || return 0; type=$REPLY; fi
        rc=0; node_deploy "$type" || rc=$?
        [[ $rc == 3 ]] || return "$rc"
        # Options that belonged to the previous protocol do not follow to the next one.
        type='' opt_domain='' opt_sni='' opt_cert='' opt_webroot='' opt_cert_file='' opt_key_file=''
        opt_transport='' opt_proto_version='' opt_proto_mode=''
    done
}
# The quick-deploy list; REPLY = protocol type, failure = back.
quick_pick() {
    local type i more label
    while :; do
        msg $'\n快速部署（任一步输入 0 返回；同一协议可以部署多个节点）'
        i=0
        for type in $QUICK_PROTOCOLS; do
            i=$((i+1)); label=$(proto_call "$type" label)
            printf '  %s. %-18s %s\n' "$i" "${label%%（*}" "$(proto_quick_hint "$type")"
        done
        more=''
        for type in $(quick_more); do label=$(proto_call "$type" label); more+="${more:+、}${label%%（*}"; done
        printf '  %s. 更多协议…          %s\n' "$((i+1))" "$more"
        ask '请选择' 1 || return 1
        # shellcheck disable=SC2086 # one type per word
        if type=$(nth_word "$REPLY" $QUICK_PROTOCOLS); then REPLY=$type; return 0; fi
        if [[ $REPLY != "$((i+1))" ]]; then err "请选择 1–$((i+1))。"; continue; fi
        quick_pick_more && return 0
    done
}
nth_word() {
    local n=$1
    shift
    [[ $n =~ ^[1-9][0-9]*$ ]] && (( n <= $# )) || return 1
    printf '%s\n' "${!n}"
}
# Protocols outside the first page, those without a domain first.
quick_more() {
    local need type
    for need in none optional required; do
        for type in $PROTOCOLS; do
            [[ " $QUICK_PROTOCOLS " != *" $type "* && $(proto_call "$type" domain) == "$need" ]] && printf '%s\n' "$type"
        done
    done
    return 0
}
proto_quick_hint() {
    if proto_has "$1" hint; then proto_call "$1" hint
    elif [[ $(proto_call "$1" domain) == required ]]; then printf '需要域名'
    else printf '不需要域名'; fi
}
quick_pick_more() {
    local types type i=0 label
    types=$(quick_more)
    msg $'\n更多协议：'
    for type in $types; do
        i=$((i+1)); label=$(proto_call "$type" label)
        printf '  %s. %-18s %s\n' "$i" "${label%%（*}" "$(proto_quick_hint "$type")"
    done
    while :; do
        ask '请选择' 1 || return 1
        # shellcheck disable=SC2086 # one type per word
        if type=$(nth_word "$REPLY" $types); then REPLY=$type; return 0; fi
        err "请选择 1–$i。"
    done
}
# Interactive: the certificate domain, asked (ASK=1) and checked until it resolves to
# this server. Returns 3 for "no domain, pick another protocol" or back, 0 when the
# domain is set in opt_sni (also when the user goes on despite a CDN in front).
cert_domain_confirm() {
    local ask_first=$1
    while :; do
        if [[ $ask_first == 1 ]]; then
            msg "$(proto_call "$type" label) 需要一个已经解析到本机（$host）的域名，用来申请免费证书。"
            ask '域名（没有域名直接回车，换一个协议）' || return 3
            [[ -n $REPLY ]] || return 3
            REPLY=$(tr '[:upper:]' '[:lower:]' <<< "$REPLY")
            if [[ $REPLY =~ ^[0-9.]+$ ]] || ! valid_domain "$REPLY"; then err '域名格式不对，例如 vpn.example.com（中文域名请用 Punycode）。'; continue; fi
            opt_sni=$REPLY
        fi
        # Imported certificates and website-directory validation do not need it.
        [[ -z $opt_cert || $opt_cert == auto ]] || return 0
        cert_reusable "$opt_sni" && return 0
        domain_resolves_here "$opt_sni" "$host" && return 0
        msg $'  1. 重新检查（刚改好解析的话，等一两分钟再选）\n  2. 换一个域名\n  3. 没有域名，换一个协议\n  4. 仍然申请证书（域名开了 CDN 代理时选）\n  0. 返回'
        while :; do
            ask '请选择' 1 || return 3
            case $REPLY in 1) ask_first=0;; 2) ask_first=1;; 3) return 3;; 4) return 0;; *) err '请选择 0–4。'; continue;; esac
            break
        done
    done
}
# One deployment of TYPE with node_add_main's options. Returns 3 to go back to the
# protocol list.
node_deploy() {
    local type=$1 name host port sni='' bbr=keep candidate node id tmp transport cert_avoid_port='' need questions=0 checked='' saved
    # Protocol prompt hooks fill these.
    local mode=none email='' webroot='' cert='' key='' stream='' proto_version='' proto_mode=''
    # Answers given in this round only; going back to the list forgets them.
    local opt_sni=$opt_sni opt_cert=$opt_cert opt_webroot=$opt_webroot opt_cert_file=$opt_cert_file opt_key_file=$opt_key_file
    local opt_transport=$opt_transport opt_proto_version=$opt_proto_version opt_proto_mode=$opt_proto_mode
    need=$(proto_call "$type" domain) || return 1
    if [[ -n $opt_domain ]]; then
        [[ $need != none ]] || { err "$(proto_call "$type" label) 不需要域名，请去掉 --domain。"; return 1; }
        [[ -z $opt_sni || $opt_sni == "$opt_domain" ]] || { err '--domain 和 --sni 不一致。'; return 1; }
        opt_sni=$opt_domain
    fi
    if [[ -n $opt_host ]]; then host=$opt_host
    else
        msg '检测本机公网 IP…'
        if detect_public_ip; then host=$PUBLIC_IP; msg "本机公网 IP：$host"
        elif [[ $assume_yes == 1 ]]; then err '没有检测到本机公网 IP，非交互模式缺少参数：--host'; return 1
        else
            while :; do
                ask '没有检测到本机公网 IP，请填写客户端连接用的 IP 或域名' || return 3
                host=$REPLY
                valid_host "$host" && break
                err '地址不合法，例如 203.0.113.5 或 vpn.example.com。'
            done
        fi
    fi
    valid_host "$host" || { err '地址不合法。'; return 1; }
    # The domain comes first: without one the user picks another protocol right away.
    # Optional-domain protocols need one only when a domain certificate was asked for.
    if [[ $need == required || ( $need == optional && -n $opt_cert && $opt_cert != selfsigned ) ]] &&
       [[ -z $opt_sni ]] && ! { [[ ! $host =~ ^[0-9.]+$ ]] && valid_domain "$host"; }; then
        [[ $assume_yes != 1 ]] || { err '非交互模式缺少参数：证书域名（--domain）'; return 1; }
        cert_domain_confirm 1 || return 3
        checked=$opt_sni
    fi
    if [[ $assume_yes != 1 ]] && proto_has "$type" variant && [[ -z $opt_transport$opt_proto_version$opt_proto_mode ]]; then
        proto_call "$type" variant || return 3
        questions=$((questions+1))
    fi
    port=${opt_port:-random}
    if [[ -z $opt_port && $assume_yes != 1 ]]; then
        while :; do
            ask '端口（1–65535，回车随机选一个空闲端口）' 随机 || return 3
            if [[ $REPLY == 随机 ]]; then port=random; break; fi
            if valid_port "$REPLY" && port_free "$REPLY"; then port=$REPLY; break; fi
            err '端口要在 1–65535 之间，并且没有被占用。'
        done
        questions=$((questions+1))
    fi
    if [[ $port != random ]]; then valid_port "$port" || { err '端口必须在 1–65535。'; return 1; }; fi
    name=$(default_node_name "$type${PUBLIC_LOC:+-$PUBLIC_LOC}")
    if [[ -n $opt_name ]]; then name=$opt_name
    elif [[ $assume_yes != 1 ]] && (( questions < 2 )); then ask '节点名称' "$name" || return 3; name=$REPLY; fi
    # Paths that only the command line chose a method for (--cert webroot / import).
    if [[ $assume_yes != 1 ]]; then
        case $opt_cert in
          webroot) [[ -n $opt_webroot ]] || { ask '现有网站根目录绝对路径' || return 3; opt_webroot=$REPLY; };;
          import)
            [[ -n $opt_cert_file ]] || { ask '完整证书链绝对路径' || return 3; opt_cert_file=$REPLY; }
            [[ -n $opt_key_file ]] || { ask '私钥绝对路径' || return 3; opt_key_file=$REPLY; };;
        esac
    fi
    # The questions are over; protocol options take their defaults without asking.
    saved=$assume_yes; assume_yes=1
    proto_call "$type" prompt || { assume_yes=$saved; return 1; }
    assume_yes=$saved
    [[ -z $sni ]] || valid_domain "$sni" || { err '域名不合法，请使用 ASCII/Punycode 域名。'; return 1; }
    [[ -z $opt_transport || -n $stream ]] || { err "--transport 不适用于 $(proto_call "$type" label)。"; return 1; }
    [[ -z $opt_proto_version$opt_proto_mode || -n $proto_version ]] || { err "--proto-version、--proto-mode 不适用于 $(proto_call "$type" label)。"; return 1; }
    case ${opt_bbr:-keep} in 1|enable) bbr=enable;; 2|keep) bbr=keep;; *) err '--bbr 只能是 enable 或 keep。'; return 1;; esac
    # A domain from the command line is checked here, still before any certificate request.
    while [[ $mode == auto && -n $sni && $sni != "$checked" ]] && ! cert_reusable "$sni"; do
        if [[ $assume_yes == 1 ]]; then
            domain_resolves_here "$sni" "$host" || { err '没有申请证书。域名开了 CDN 代理时，改用 --cert webroot 或 --cert import。'; return 1; }
            break
        fi
        opt_sni=$sni
        cert_domain_confirm 0 || return 3
        checked=$opt_sni
        # Another domain was typed: the protocol options follow it.
        saved=$assume_yes; assume_yes=1
        proto_call "$type" prompt || { assume_yes=$saved; return 1; }
        assume_yes=$saved
    done
    msg "部署：$name / $(proto_call "$type" label) / $host:${port/#random/随机端口}${sni:+ / $sni}"
    [[ -f $SRM_ROOT/.srm-owned ]] || setup "$self" || return 1
    ensure_dependencies || return 1
    transport=$(proto_call "$type" transport) || return 1
    [[ " $transport " != *" tcp "* || $port == random ]] || cert_avoid_port=$port
    # Both 80 and 443 taken: the menu offers the other ways to get the certificate.
    if [[ $mode == auto && $assume_yes != 1 ]] && ! cert_reusable "$sni" && ! cert_auto_mode >/dev/null; then
        msg $'80 和 443 端口都有程序在用，Let\'s Encrypt 没法自动验证域名：\n  1. 用现有网站目录验证（网站保持运行）\n  2. 导入已有证书\n  0. 返回'
        ask '请选择' 1 || return 3
        case $REPLY in
          1) mode=webroot; ask '现有网站根目录绝对路径' || return 3; webroot=$REPLY;;
          2) mode=import; ask '完整证书链绝对路径' || return 3; cert=$REPLY; ask '私钥绝对路径' || return 3; key=$REPLY;;
          *) err '无效选项。'; return 3;;
        esac
    fi
    [[ $mode != auto && $mode != webroot ]] || msg "证书由 Let's Encrypt 免费签发；继续表示同意该机构的服务条款。"
    if [[ $port == random ]]; then port=$(choose_port) || return 1; else port_free "$port" || { err '端口被占用，原服务未改动。'; return 1; }; fi
    cert_port_ok "$port" "$transport" || return 1
    [[ " $transport " != *" tcp "* ]] || cert_avoid_port=$port
    id=$(random_hex 8) || return 1
    proto_call "$type" create || return 1
    # A reused certificate may validate on this node's port.
    if [[ -n $(jq -r '.cert_dir // empty' <<< "$REPLY") ]] && ! cert_port_ok "$port" "$transport" "$sni"; then
        msg '证书已经申请好，换一个端口重新部署时会直接复用。'; return 1
    fi
    node=$(jq -n --arg id "$id" --arg name "$name" --arg host "$host" --arg sni "$sni" --arg type "$type" --argjson port "$port" --argjson fields "$REPLY" \
        '{id:$id,name:$name,host:$host} + (if $sni == "" then {} else {sni:$sni} end) + {port:$port,type:$type,enabled:true} + $fields') || return 1
    if [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) == 1 ]]; then
        node=$(printf '%s' "$node" | jq '.listen="0.0.0.0"') || return 1
    fi
    candidate=$(new_candidate) || return 1
    tmp=$(mktemp) || return 1
    jq --argjson n "$node" '.nodes += [$n]' "$candidate" > "$tmp" && mv "$tmp" "$candidate" || return 1
    if [[ -f $STATE ]] && jq -e 'any(.nodes[]; .enabled)' "$STATE" >/dev/null 2>&1; then
        msg '应用新配置会重启服务，已有节点的连接会断开几秒。'
    fi
    if apply_state "$candidate"; then
        rm -f "$candidate"
        if [[ $bbr == enable ]]; then
            if [[ $(sysctl -n net.ipv4.tcp_congestion_control) == bbr ]]; then msg 'BBR 已开启。'; else bbr_enable || msg '节点已部署；BBR 未启用，原因见上方。'; fi
        fi
        DEPLOYED_NODE=$node
        printf '%s' "$node" | deploy_summary
        if [[ $assume_yes != 1 ]]; then printf '按回车继续' >&2; IFS= read -r _ || true; fi
        return 0
    fi
    # A self-signed certificate made for this node is unused once the deploy fails.
    rm -rf "$DATA/selfsigned/$id"
    rm -f "$candidate"; return 1
}
# One screen after deploying: address, cloud firewall, link and QR code, and the
# snippet of every client that supports the protocol (node JSON on stdin).
deploy_summary() {
    local node transport port
    node=$(cat)
    port=$(jq -r .port <<< "$node")
    transport=$(proto_call "$(jq -r .type <<< "$node")" transport | tr '[:lower:] ' '[:upper:]+')
    msg ''
    msg "━━━━━━━━ 部署完成：$(jq -r .name <<< "$node")（$(proto_call "$(jq -r .type <<< "$node")" label)）━━━━━━━━"
    msg "服务器：$(jq -r .host <<< "$node")    端口：$port/$transport    节点 ID：$(jq -r .id <<< "$node")"
    msg "云服务器安全组：连不上时，到服务商控制台的安全组（云防火墙）放行入站 $transport $port；本机的 UFW / firewalld 已自动放行。"
    client_snippets qr <<< "$node"
    msg '以后在菜单里选「2. 节点管理」可以再次查看链接、二维码和这些配置。'
}
# Client configurations of the node on stdin, one section per supported client;
# with "qr" the share link is also drawn as a QR code (locally, no network).
client_snippets() {
    local node type clients link out client
    node=$(cat)
    type=$(jq -r .type <<< "$node")
    clients=$(proto_call "$type" link_clients) || return 1
    if [[ -n $clients ]]; then
        link=$(share_uri <<< "$node") || return 1
        msg $'\n── 分享链接 ──'
        msg "$link"
        if [[ ${1:-} == qr ]]; then
            if command -v qrencode >/dev/null; then
                if use_color; then qrencode -t ANSIUTF8 <<< "$link"; else qrencode -t UTF8 <<< "$link"; fi
            else msg '（未安装 qrencode，没有二维码。）'; fi
        fi
    fi
    out=$(surge_proxy <<< "$node") || return 1
    if [[ -n $out ]]; then
        msg $'\n── Surge：手机版新建代理后按下面逐项填写 ──'
        surge_form <<< "$out" || return 1
        msg 'Mac 版或在配置文本里编辑：把下面整行放进配置的 [Proxy] 段'
        msg "$out"
    fi
    out=$(clash_proxy <<< "$node") || return 1
    [[ -z $out ]] || { msg $'\n── Clash Meta (mihomo)：放进 proxies: 列表 ──'; msg "$out"; }
    msg $'\n── sing-box：放进 outbounds 列表 ──'
    client_outbound <<< "$node" || return 1
    for client in $clients; do
        msg ''
        client_import_hint "$client"
    done
    out=$(jq -r '.cert_sha256 // empty' <<< "$node")
    [[ -z $out ]] || msg $'\n'"自签证书：以上 Surge、Clash Meta、sing-box 配置已带证书指纹；只导入链接的客户端会跳过证书校验，客户端能填证书 SHA-256 指纹时填：$out"
    out=$(client_note <<< "$node") || return 1
    [[ -z $out ]] || msg $'\n'"说明：$out"
    if [[ $(proto_call "$type" transport) == udp ]]; then
        msg $'\n'"只走 UDP：Shadowrocket 等客户端的 TCP 延迟测试对这个节点显示不出延迟，属于正常；连不上多半是本地网络限制了 UDP，可以在菜单里选「1. 添加节点」换 TCP 类协议（VLESS Reality、AnyTLS）。"
    fi
}
client_import_hint() {
    case $1 in
      Shadowrocket) msg '── Shadowrocket：扫上面的二维码，或复制分享链接后打开 Shadowrocket，会提示从剪贴板添加 ──';;
      v2rayN) msg '── v2rayN：复制分享链接，在 v2rayN 主界面按 Ctrl+V（从剪贴板导入分享链接）──';;
    esac
}
# `srm add --json`: the deploy summary as one object; clients the protocol does not
# support are absent.
deploy_json() {
    local node type link='' clients surge clash outbound
    node=$(cat)
    type=$(jq -r .type <<< "$node")
    clients=$(proto_call "$type" link_clients) || return 1
    [[ -z $clients ]] || link=$(share_uri <<< "$node") || return 1
    surge=$(surge_proxy <<< "$node") && outbound=$(client_outbound <<< "$node") || return 1
    clash=$(jq -c "$PROTO_JQ_DEFS $(proto_jq clash empty)" <<< "$node") || return 1
    jq -n --argjson node "$node" --arg label "$(proto_call "$type" label)" --arg transport "$(proto_call "$type" transport)" \
      --arg link "$link" --arg clients "$clients" --arg surge "$surge" --arg clash "${clash:-null}" --argjson outbound "$outbound" \
      --arg note "$(client_note <<< "$node")" '
      ($clients|split(" ")|map(select(. != ""))) as $apps |
      {id:$node.id,name:$node.name,type:$node.type,protocol:$label,host:$node.host,port:$node.port,
       firewall:[$transport|split(" ")[]|{port:$node.port,protocol:.}],
       share_link:(if $link == "" then null else $link end),
       clients:({}
         + (if $surge == "" then {} else {surge:$surge} end)
         + (($clash|fromjson) as $c|if $c == null then {} else {clash_meta:$c} end)
         + {sing_box:$outbound}
         + (if any($apps[]; . == "Shadowrocket") then {shadowrocket:$link} else {} end)
         + (if any($apps[]; . == "v2rayN") then {v2rayn:$link} else {} end))}
      + (if $node.cert_sha256 then {cert_sha256:$node.cert_sha256} else {} end)
      + (if $note == "" then {} else {note:$note} end)'
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
      clash) printf '%s' "$node" | clash_proxy;;
      surge) printf '%s' "$node" | surge_proxy;;
      clients) printf '%s' "$node" | client_snippets;;
      details)
        printf '%s' "$node" | jq "del($(proto_call "$type" secrets))" || return 1
        if [[ $(printf '%s' "$node" | jq -r '.cert_dir // empty') ]]; then
            openssl x509 -in "$(printf '%s' "$node" | jq -r .cert_dir)/fullchain.pem" -noout -subject -enddate
        fi;;
      *) err '格式只能是 uri、qr、outbound、clash、surge、clients 或 details。'; return 1;;
    esac
}
list_nodes() {
    [[ -f $STATE ]] || { msg '尚无节点。'; return 0; }
    jq -r '.nodes[]|[.id,.name,.type,(.port|tostring),(if .enabled then "启用" else "停用" end)]|@tsv' "$STATE"
}
node_change() {
    local id=$1 action=$2 value=${3:-} candidate tmp type node dropped='' name local_port
    candidate=$(new_candidate) || return 1
    node=$(node_json "$candidate" "$id") || { rm -f "$candidate"; err '节点不存在。'; return 1; }
    type=$(printf '%s' "$node" | jq -r .type)
    tmp=$(mktemp) || return 1
    case $action in
      toggle)
        if [[ $(printf '%s' "$node" | jq -r .enabled) == false ]]; then
            port_free "$(printf '%s' "$node" | jq -r .port)" "$id" || { rm -f "$tmp" "$candidate"; err '端口被占用，无法启用。'; return 1; }
            # A helper's loopback port may have been taken while the node was off.
            local_port=$(printf '%s' "$node" | jq -r '.local_port // empty')
            if [[ -n $local_port && -n $(ss -H -ltn "sport = :$local_port") ]]; then
                rm -f "$tmp" "$candidate"; err "本机端口 $local_port 已被其他程序占用，无法启用；请删除此节点后重新部署。"; return 1
            fi
            cert_port_ok "$(printf '%s' "$node" | jq -r .port)" "$(proto_call "$type" transport)" || { rm -f "$tmp" "$candidate"; return 1; }
        fi
        jq --arg id "$id" '(.nodes[]|select(.id==$id)|.enabled) |= not' "$candidate" > "$tmp";;
      delete)
        # Rules limited to this node lose it; a rule left with no node goes too.
        dropped=$(jq -r --arg id "$id" '.policies[]|select(.inbounds == [$id])|.name' "$candidate") || dropped=''
        jq --arg id "$id" '.nodes |= map(select(.id!=$id)) |
          .policies |= map(if .inbounds then .inbounds -= [$id] else . end | select(.inbounds != []))' "$candidate" > "$tmp";;
      port)
        port_free "$value" "$id" || { rm -f "$tmp" "$candidate"; err '端口无效或被占用。'; return 1; }
        cert_port_ok "$value" "$(proto_call "$type" transport)" || { rm -f "$tmp" "$candidate"; return 1; }
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
    local count index=0 id name type port status current
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
    msg $'1.详情 2.原始分享链接 3.二维码 4.客户端配置（Surge / Clash Meta / sing-box / Shadowrocket / v2rayN）\n5.启用/停用 6.修改端口 7.重置凭据 8.修改名称 9.删除'
    ! proto_has "$type" retarget_select || msg "10.$(proto_call "$type" retarget_label)"
    ask '操作' 1 || return 0
    case $REPLY in
      1) export_node "$id" details;; 2) export_node "$id" uri;; 3) export_node "$id" qr;; 4) export_node "$id" clients;;
      5) with_lock node_change "$id" toggle;;
      6) ask '新端口' || return 0; with_lock node_change "$id" port "$REPLY";;
      7) yesno '旧凭据会失效，确认重置' && with_lock node_change "$id" rotate;;
      8) ask '新名称' || return 0; with_lock node_change "$id" name "$REPLY";;
      9) yesno '确认删除此节点' && with_lock node_change "$id" delete;;
      10)
        proto_has "$type" retarget_select || { err '此协议的节点不支持切换握手目标。'; return 1; }
        current=$(node_json "$STATE" "$id" | jq -r '.sni // empty')
        proto_call "$type" retarget_select "$current" || return 0
        [[ $REPLY != "$current" ]] || { msg '当前已经使用此目标，无需修改。'; return 0; }
        msg '更换后客户端要重新导入（或把 SNI 改成新目标）；端口和凭据不变，应用时节点会断开几秒。'
        if with_lock node_change "$id" retarget "$REPLY"; then
            msg $'\n新的客户端配置：'; node_json "$STATE" "$id" | client_snippets qr
        fi;;
      *) err '无效选项。';;
    esac
}
