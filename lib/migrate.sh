# Moving a v3 installation (the v2ray-agent based install.sh) to srm. V3_ROOT is only
# ever read: nodes come from v3's sing-box configuration fragments (including the
# 30_–33_ multi-instance files) with their keys and certificates, and from protocols
# that kept files of their own (registry hook v3_scan). The registry hooks v3_import,
# v3_scan and v3_prepare hold everything protocol-specific.
V3_ROOT=/etc/v2ray-agent
V3_UNIT_DIR=/etc/systemd/system
# Crontab lines of v3 that renew certificates or update geo data and restart v3's
# services; after moving they are commented out, never deleted.
V3_CRON_JOBS='RenewTLS UpdateGeo'
MIGRATE_MARK='# srm 迁移后停用：'
# Settings-only fragments of v3 that need nothing in srm.
V3_PLAIN_FILES='log.json sniff.json'
# Menu item while v3 is there and nothing has been moved yet; no network, no root
# files beyond a directory listing.
migrate_pending() {
    [[ -d $V3_ROOT && ! -f $DATA/migrated-v3.json ]] || return 1
    compgen -G "$V3_ROOT/sing-box/conf/config/*.json" >/dev/null || compgen -G "$V3_ROOT/*/nodes/*.env" >/dev/null
}
# The first-screen question, unless a preview found nothing that can move (the item
# stays, for after the user fixed a reason shown there).
migrate_offered() { migrate_pending && [[ ! -f $DATA/migrate-v3-nothing ]]; }
# Reads V3_ROOT into the plan file $1: {nodes:[{node,label,cert,units,note}],skipped:[{label,reason}],units:[]}.
# Nodes get their final id here; host is set when applying.
migrate_scan() {
    local plan=$1 file base inbound conf=$V3_ROOT/sing-box/conf/config type line units=() i
    [[ -d $V3_ROOT ]] || { err "没有找到旧版安装（$V3_ROOT）。"; return 1; }
    printf '%s\n' '{"nodes":[],"skipped":[],"units":[]}' > "$plan" || return 1
    for file in "$conf"/*.json; do
        [[ -f $file ]] || continue
        base=${file##*/}
        if ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then migrate_skip "$plan" "$base" '文件无法解析'; continue; fi
        if jq -e '.inbounds|type == "array" and length > 0' "$file" >/dev/null; then
            while IFS= read -r inbound; do migrate_inbound "$plan" "$base" "$inbound" || return 1; done < <(jq -c '.inbounds[]' "$file")
        elif [[ " $V3_PLAIN_FILES " == *" $base "* ]] || { [[ $base == dns.json ]] && jq -e '(.dns.rules // [])|length == 0' "$file" >/dev/null; }; then
            continue
        else
            migrate_skip "$plan" "分流 / 出站设置 $base" 'v4 的分流按平台规则设置，不能自动迁移；迁移后在菜单「3. 流媒体分流」里重新设置'
        fi
    done
    # The sing-box service of v3 stops only when at least one of its nodes moves.
    if jq -e '.nodes|length > 0' "$plan" >/dev/null; then
        [[ ! -f $V3_UNIT_DIR/dodo258-sing-box.service ]] || units+=(dodo258-sing-box.service)
        # Older releases used the upstream unit name.
        ! grep -qF "$V3_ROOT/" "$V3_UNIT_DIR/sing-box.service" 2>/dev/null || units+=(sing-box.service)
    fi
    for type in $PROTOCOLS; do
        proto_has "$type" v3_scan || continue
        while IFS= read -r line; do
            [[ -n $line ]] || continue
            migrate_scanned "$plan" "$line" || return 1
        done < <(proto_call "$type" v3_scan "$V3_ROOT")
    done
    for file in "$V3_ROOT"/xray/conf/*.json; do
        [[ -f $file ]] || continue
        while IFS=$'\t' read -r type i; do
            migrate_skip "$plan" "Xray $type（端口 $i）" 'v4 只用 sing-box；旧 Xray 服务继续运行，迁移不会停掉它' runs
        done < <(jq -r '.inbounds[]?|select(.port != null and (.listen // "") != "127.0.0.1")|[.protocol,(.port|tostring)]|@tsv' "$file" 2>/dev/null)
    done
    [[ ! -d $V3_ROOT/website-manager ]] || migrate_skip "$plan" '网站' 'v4 不管理网站；nginx 和网站文件保持原样' runs
    if compgen -G "$V3_ROOT/subscribe*" >/dev/null; then
        migrate_skip "$plan" '订阅链接' 'v4 不提供订阅；已导入的节点照常可用，新设备请用菜单「2. 节点管理」里的分享链接'
    fi
    local tmp
    tmp=$(mktemp) || return 1
    jq --args '.units = ([$ARGS.positional[], .nodes[].units[]]|unique)' ${units[@]+"${units[@]}"} < "$plan" > "$tmp" && mv "$tmp" "$plan"
}
# migrate_skip PLAN LABEL REASON [stops|runs]: "stops" marks a node of v3's sing-box
# service, which stops with the service when other nodes move; "runs" something of v3
# that keeps running (Xray, the website) on v3's certificates and geo data.
migrate_skip() {
    local tmp
    tmp=$(mktemp) || return 1
    jq --arg l "$2" --arg r "$3" --arg k "${4:-}" '.skipped += [{label:$l,reason:$r} + (if $k == "" then {} else {($k):true} end)]' "$1" > "$tmp" && mv "$tmp" "$1"
}
# A node from a v3_scan line or from an inbound; checks what every node needs and adds it.
migrate_add() {
    local plan=$1 label=$2 node=$3 cert=${4:-null} unit_list=${5:-[]} note=${6:-} port id taken tmp check stops=''
    # Nodes without units of their own are served by v3's sing-box service.
    [[ $unit_list != '[]' ]] || stops=stops
    port=$(jq -r .port <<< "$node")
    valid_port "$port" || { migrate_skip "$plan" "$label" '端口无效' $stops; return 0; }
    taken=$([[ ! -f $STATE ]] || jq -r --argjson p "$port" '.nodes[]|select(.port == $p or .local_port == $p)|.name' "$STATE" | head -n 1)
    [[ -z $taken ]] || { migrate_skip "$plan" "$label" "端口 $port 已被 srm 的节点「$taken」使用" $stops; return 0; }
    taken=$(jq -r --argjson p "$port" '.nodes[].node|select(.port == $p or .local_port == $p)|.name' "$plan" | head -n 1)
    [[ -z $taken ]] || { migrate_skip "$plan" "$label" "端口 $port 和要迁移的节点「$taken」重复" $stops; return 0; }
    id=$(random_hex 8) || return 1
    node=$(jq -c --arg id "$id" --arg name "$(jq -r .type <<< "$node")-$port" '{id:$id,name:$name} + . + {enabled:true}' <<< "$node") || return 1
    if [[ $cert != null ]]; then node=$(jq -c --argjson c "$cert" --arg dir "$(migrate_cert_dir "$cert" "$id")" '. + {cert_dir:$dir} + ($c.pins // {})' <<< "$node") || return 1; fi
    # Anything v4 would refuse is reported now, not when applying.
    check=$(mktemp) || return 1
    jq -n --argjson n "$node" '{schema:2,nodes:[$n + {host:"192.0.2.1"}],policies:[],unlock_dns:null,egress:null}' > "$check"
    if ! validate_state "$check" 2>/dev/null; then rm -f "$check"; migrate_skip "$plan" "$label" '节点数据 v4 不接受（字段格式不符）' $stops; return 0; fi
    rm -f "$check"
    tmp=$(mktemp) || return 1
    jq --argjson n "$node" --arg l "$label" --argjson c "$cert" --argjson u "$unit_list" --arg note "$note" \
        '.nodes += [{node:$n,label:$l,cert:$c,units:$u} + (if $note == "" then {} else {note:$note} end)]' "$plan" > "$tmp" && mv "$tmp" "$plan"
}
migrate_scanned() {
    local plan=$1 line=$2 label
    label=$(jq -r .label <<< "$line") || return 1
    if jq -e 'has("skip")' <<< "$line" >/dev/null; then migrate_skip "$plan" "$label" "$(jq -r .skip <<< "$line")"; return; fi
    migrate_add "$plan" "$label" "$(jq -c .node <<< "$line")" null "$(jq -c .units <<< "$line")" "$(jq -r '.note // ""' <<< "$line")"
}
migrate_inbound() {
    local plan=$1 file=$2 in=$3 label port type rc fields='' reason='' cert=null note=''
    port=$(jq -r '.listen_port // empty' <<< "$in")
    label="$(jq -r '.type // "?"' <<< "$in")（端口 ${port:-?}，$file）"
    case $(jq -r '.listen // "::"' <<< "$in") in
      127.0.0.1|::1|localhost) migrate_skip "$plan" "$label" '只监听本机、由 nginx 转发的节点，v4 不使用 nginx' stops; return 0;;
    esac
    for type in $PROTOCOLS; do
        proto_has "$type" v3_import || continue
        rc=0; proto_call "$type" v3_import "$in" || rc=$?
        case $rc in 0) fields=$REPLY; break;; 2) reason=$REPLY; break;; esac
    done
    [[ -z $fields$reason ]] || label="$(proto_call "$type" label)（端口 $port，$file）"
    if [[ -n $reason ]]; then migrate_skip "$plan" "$label" "$reason" stops; return 0; fi
    [[ -n $fields ]] || { migrate_skip "$plan" "$label" 'v4 不支持这种节点' stops; return 0; }
    if jq -e '.tls.certificate_path' <<< "$in" >/dev/null; then
        migrate_cert "$type" "$(jq -r .tls.certificate_path <<< "$in")" "$(jq -r '.tls.key_path // ""' <<< "$in")" "$(jq -r '.sni // ""' <<< "$fields")" ||
            { migrate_skip "$plan" "$label" "$REPLY" stops; return 0; }
        cert=$REPLY
    fi
    if jq -e '(.users|length) > 1' <<< "$in" >/dev/null; then
        note="这个端口还有 $(( $(jq '.users|length' <<< "$in") - 1 )) 个用户（$(jq -r '[.users[1:][]|.name // .username // "?"]|join("、")' <<< "$in")）不迁移，v4 每个节点只保留第一个用户。"
    fi
    migrate_add "$plan" "$label" "$(jq -c --arg t "$type" --argjson p "$port" '. + {type:$t,port:$p}' <<< "$fields")" "$cert" '[]' "$note"
}
# REPLY = the certificate of a TLS node: {kind:"ca",domain,cert,key} or, for a
# self-signed one (only protocols whose clients pin it), {kind:"self",cert,key,pins}.
# On failure REPLY is the reason.
migrate_cert() {
    local type=$1 cert=$2 key=$3 domain=$4 subject issuer pin pubkey
    [[ -r $cert && -r $key ]] || { REPLY="证书文件不存在：$cert"; return 1; }
    subject=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null) && issuer=$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null) ||
        { REPLY="证书无法读取：$cert"; return 1; }
    if [[ ${subject#subject=} == "${issuer#issuer=}" ]]; then
        [[ $(proto_call "$type" domain) == optional ]] || { REPLY='自签证书只能用于客户端能校验证书指纹的协议'; return 1; }
        cert_valid "$cert" "$key" "$domain" || { REPLY='自签证书与 SNI / 私钥不匹配，或已到期'; return 1; }
        pin=$(openssl x509 -in "$cert" -outform der | openssl dgst -sha256 | awk '{print $NF}') &&
            pubkey=$(openssl x509 -in "$cert" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64 -A) || return 1
        REPLY=$(jq -nc --arg c "$cert" --arg k "$key" --arg pin "$pin" --arg pub "$pubkey" '{kind:"self",cert:$c,key:$k,pins:{cert_sha256:$pin,pubkey_sha256:$pub}}')
        return 0
    fi
    valid_domain "$domain" && cert_valid "$cert" "$key" "$domain" || { REPLY="证书不是 $domain 的、已到期或与私钥不匹配"; return 1; }
    REPLY=$(jq -nc --arg d "$domain" --arg c "$cert" --arg k "$key" '{kind:"ca",domain:$d,cert:$c,key:$k}')
}
migrate_cert_dir() {
    if [[ $(jq -r .kind <<< "$1") == self ]]; then printf '%s\n' "$DATA/selfsigned/$2"
    else printf '%s\n' "$DATA/certs/$(jq -r .domain <<< "$1")/active"; fi
}
# What moves, what does not, and what applying does.
migrate_show() {
    local plan=$1 count
    msg "发现旧版（v3）安装：$V3_ROOT"
    count=$(jq '.nodes|length' "$plan")
    if [[ $count == 0 ]]; then msg $'\n没有可以迁移的节点。'
    else
        msg $'\n能迁移的节点（端口、密码和密钥都不变，正在用的客户端不用改）：'
        jq -r '.nodes|to_entries[]|"  \(.key+1). \(.value.label)"
            + (if .value.node.sni then " · \(.value.node.sni)" else "" end)
            + (if .value.cert.kind == "self" then " · 自签证书" else "" end)
            + (if .value.note then "\n     说明：\(.value.note)" else "" end)' "$plan"
    fi
    if jq -e '.skipped|length > 0' "$plan" >/dev/null; then
        msg $'\n不能迁移：'
        jq -r '.skipped[]|"  - \(.label)：\(.reason)"' "$plan"
    fi
    [[ $count != 0 ]] || return 0
    msg $'\n迁移时会：'
    msg "  - 停止并停用旧服务：$(jq -r '.units|join("、")' "$plan")$(jq -r 'if any(.skipped[]; .stops) and any(.units[]; test("sing-box")) then "；上面不能迁移的旧 sing-box 节点随之停止" else "" end' "$plan")"
    msg '  - 由 srm 在原端口启动这些节点；启动或健康检查失败就恢复旧服务'
    msg "  - 注释掉旧版定时任务（${V3_CRON_JOBS// /、}），行首加 #，不删除"
    if jq -e 'any(.skipped[]; .runs)' "$plan" >/dev/null; then
        msg "    注意：继续运行的旧版网站 / Xray 用的证书（$V3_ROOT/tls）从此不再自动续期，Xray 的 geo 数据也不再更新，请在证书到期前自行处理"
    fi
    if jq -e 'any(.nodes[]; .cert.kind == "ca")' "$plan" >/dev/null; then
        if migrate_renewable "$plan"; then
            msg "  - 证书改由 srm 续期：到期前 30 天自动向 Let's Encrypt 重新申请（用 80 或 443 端口验证）"
        else
            msg "  - 注意：迁移后 80 和 443 端口都被占用，srm 没法自动给迁移过来的证书重新申请；到期前请空出 80 端口，再在菜单「8. 证书管理」里选「立即检查续期」"
        fi
    fi
    msg "  - $V3_ROOT 里的文件一个字节都不改"
}
# Whether a certificate request could validate on 80 or 443 once the nodes moved: the
# port is not used by any TCP node (srm's or moving) and nothing listens on it now.
# Cautious: a v3 node that stops with its service still counts as a listener.
migrate_renewable() {
    local taken port
    taken=" $({ [[ ! -f $STATE ]] || jq -r ".nodes[]|select(any(($(proto_jq_transports))[]; . == \"tcp\"))|.port" "$STATE"
               jq -r ".nodes[].node|select(any(($(proto_jq_transports))[]; . == \"tcp\"))|.port" "$1"; } | tr '\n' ' ') "
    for port in 80 443; do
        [[ $taken != *" $port "* && -z $(ss -H -ltn "sport = :$port" 2>/dev/null) ]] && return 0
    done
    return 1
}
# Menu: preview, then 「确认 / 返回」 (Enter = back).
migrate_menu() {
    local plan rc=0
    plan=$(mktemp) || return 1
    migrate_scan "$plan" && migrate_show "$plan" || rc=1
    if [[ $rc == 0 ]] && jq -e '.nodes|length > 0' "$plan" >/dev/null; then
        msg $'\n  1. 确认迁移（服务会重启，连接断开几秒）\n  0. 返回'
        ask '请选择' 0 && [[ $REPLY == 1 ]] && { with_lock migrate_apply "$SRM_SELF" || rc=1; }
    elif [[ $rc == 0 && -d $DATA ]]; then
        # Nothing can move: the first screen stops asking; item 9 stays.
        date '+%F %T' > "$DATA/migrate-v3-nothing" || true
    fi
    rm -f "$plan"
    return "$rc"
}
# First screen of the menu while v3 is there and nothing has moved yet.
migrate_offer() {
    msg $'\n发现旧版节点（'"$V3_ROOT"$'），要迁移过来吗？\n  1. 是，先看看能迁移哪些\n  0. 否（以后在菜单「9. 迁移旧版节点」里也能迁移）'
    ask '请选择' 1 || return 0
    [[ $REPLY == 1 ]] || return 0
    migrate_menu || true
}
# srm migrate [--apply] [--yes] [--host ADDR]: a preview by default.
migrate_command() {
    local apply=0 assume_yes=0 opt_host='' plan rc=0
    while (( $# )); do
        case $1 in
          --apply) apply=1;;
          -y|--yes) assume_yes=1;;
          --host) [[ -n ${2:-} ]] || { err '--host 需要一个值。'; return 1; }; opt_host=$2; shift;;
          *) err '用法：srm migrate [--apply] [--yes] [--host 地址]'; return 1;;
        esac
        shift
    done
    require_root || return 1
    if [[ $apply == 0 ]]; then
        plan=$(mktemp) || return 1
        migrate_scan "$plan" && migrate_show "$plan" || rc=1
        [[ $rc != 0 ]] || msg $'\n以上只是预览，没有改动。加 --apply 执行迁移。'
        rm -f "$plan"; return "$rc"
    fi
    if [[ $assume_yes != 1 ]]; then
        plan=$(mktemp) || return 1
        migrate_scan "$plan" && migrate_show "$plan" || rc=1
        rm -f "$plan"
        [[ $rc == 0 ]] || return 1
        msg $'\n  1. 确认迁移（服务会重启，连接断开几秒）\n  0. 返回'
        ask '请选择' 0 && [[ $REPLY == 1 ]] || { err '没有迁移。'; return 1; }
    fi
    with_lock migrate_apply "$SRM_SELF"
}
# Under the lock, already confirmed. Old services stop only after the new configuration
# passed sing-box check; when srm cannot take over their ports, they come back.
migrate_apply() {
    local self=$1 plan candidate config tmp node unit host units=() created=() rc=0
    plan=$(mktemp) && candidate=$(mktemp) && config=$(mktemp) || return 1
    migrate_scan "$plan" || { rm -f "$plan" "$candidate" "$config"; return 1; }
    if ! jq -e '.nodes|length > 0' "$plan" >/dev/null; then rm -f "$plan" "$candidate" "$config"; err '没有可以迁移的节点。'; return 1; fi
    host=${opt_host:-}
    if [[ -z $host ]]; then
        msg '检测本机公网 IP…'
        if detect_public_ip; then host=$PUBLIC_IP
        elif [[ ${assume_yes:-0} == 1 ]]; then rm -f "$plan" "$candidate" "$config"; err '没有检测到本机公网 IP，非交互模式缺少参数：--host'; return 1
        else
            while :; do
                ask '没有检测到本机公网 IP，请填写客户端连接用的 IP 或域名' || { rm -f "$plan" "$candidate" "$config"; return 1; }
                host=$REPLY; valid_host "$host" && break
                err '地址不合法，例如 203.0.113.5 或 vpn.example.com。'
            done
        fi
    fi
    valid_host "$host" || { rm -f "$plan" "$candidate" "$config"; err '地址不合法。'; return 1; }
    [[ -f $SRM_ROOT/.srm-owned ]] || setup "$self" || { rm -f "$plan" "$candidate" "$config"; return 1; }
    ensure_dependencies || { rm -f "$plan" "$candidate" "$config"; return 1; }
    # Programs and certificates first; nothing of v3 has been touched yet.
    while IFS= read -r node; do
        ! proto_has "$(jq -r .node.type <<< "$node")" v3_prepare || proto_call "$(jq -r .node.type <<< "$node")" v3_prepare "$(jq -c .node <<< "$node")" || rc=1
        [[ $rc == 0 ]] || break
        migrate_install_cert "$node" || { rc=1; break; }
        [[ $(jq -r '.cert.kind // ""' <<< "$node") != self ]] || created+=("$DATA/selfsigned/$(jq -r .node.id <<< "$node")")
    done < <(jq -c '.nodes[]' "$plan")
    if [[ $rc == 0 ]]; then
        tmp=$(new_candidate) || rc=1
        if [[ $rc == 0 ]]; then
            local listen='::'
            [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null) != 1 ]] || listen=0.0.0.0
            jq --slurpfile p "$plan" --arg host "$host" --arg listen "$listen" \
                '.nodes += [$p[0].nodes[].node + {host:$host} + (if $listen == "::" then {} else {listen:$listen} end)]' "$tmp" > "$candidate" || rc=1
            rm -f "$tmp"
        fi
    fi
    # The whole configuration must pass before any old service stops.
    if [[ $rc == 0 ]] && ! { validate_state "$candidate" && render_config "$candidate" > "$config" && "$CORE" check -c "$config"; }; then
        err '迁移后的配置没有通过校验（节点数据或 sing-box check），旧服务没有停止。'; rc=1
    fi
    if [[ $rc != 0 ]]; then
        rm -rf "$plan" "$candidate" "$config" ${created[@]+"${created[@]}"}
        err '迁移没有执行，旧版节点保持原样。'; return 1
    fi
    while IFS= read -r unit; do [[ -z $unit ]] || units+=("$unit"); done < <(jq -r '.units[]' "$plan")
    # Interrupted from here on, the old services come back as well.
    trap 'migrate_restore_units; exit 130' INT TERM HUP
    migrate_stop_units ${units[@]+"${units[@]}"} || rc=1
    if [[ $rc == 0 ]]; then
        msg '应用新配置，srm 接管原端口…'
        apply_state "$candidate" || rc=1
    fi
    if [[ $rc != 0 ]]; then
        migrate_restore_units || err "旧服务没能全部恢复，请检查：systemctl status ${units[*]:-}"
        rm -rf "$plan" "$candidate" "$config" ${created[@]+"${created[@]}"}
        trap - INT TERM HUP
        err '迁移失败，已恢复旧服务；旧版节点保持原样。'; return 1
    fi
    trap - INT TERM HUP
    migrate_cron || err '旧版定时任务没能注释掉，请手动在 crontab -e 里给它们的行首加 #。'
    if jq -e 'any(.nodes[]; .cert.kind == "ca")' "$plan" >/dev/null; then install_renew_timer || err '证书续期定时任务注册失败。'; fi
    jq -n --arg at "$(date '+%F %T')" --slurpfile p "$plan" '{migrated_at:$at,units:$p[0].units,nodes:[$p[0].nodes[].node.id]}' > "$DATA/migrated-v3.json"
    msg $'\n迁移完成：'
    jq -r '.nodes[]|"  \(.node.name) · 端口 \(.node.port)"' "$plan"
    msg '在菜单「2. 节点管理」里能看到这些节点的分享链接、二维码和各客户端配置。'
    msg "旧版文件仍在 $V3_ROOT，没有改动；确认一切正常后可自行删除。"
    local vasma
    vasma=$(command -v vasma 2>/dev/null) || vasma=''
    [[ -z $vasma || $(readlink -f "$vasma") == "$SRM_ROOT/manager.sh" ]] || msg '旧版的 vasma 命令仍打开旧脚本，以后请输入 srm 打开菜单。'
    rm -f "$plan" "$candidate" "$config"
}
# Certificates the node needs inside srm's own directories (copies; v3 files stay as they are).
migrate_install_cert() {
    local entry=$1 kind dir tmp domain cert_rc
    kind=$(jq -r '.cert.kind // ""' <<< "$entry")
    case $kind in
      self)
        dir=$DATA/selfsigned/$(jq -r .node.id <<< "$entry")
        install -d -m 750 "$DATA/selfsigned" "$dir" && chgrp srm "$DATA/selfsigned" "$dir" &&
            install -m 640 "$(jq -r .cert.cert <<< "$entry")" "$dir/fullchain.pem" &&
            install -m 640 "$(jq -r .cert.key <<< "$entry")" "$dir/key.pem" && chgrp srm "$dir/fullchain.pem" "$dir/key.pem";;
      ca)
        domain=$(jq -r .cert.domain <<< "$entry")
        # A valid certificate srm already has for the domain stays.
        cert_reusable "$domain" && return 0
        tmp=$(mktemp -d) || return 1
        cp "$(jq -r .cert.cert <<< "$entry")" "$tmp/fullchain.pem" && cp "$(jq -r .cert.key <<< "$entry")" "$tmp/key.pem" && activate_cert "$domain" "$tmp" v3
        cert_rc=$?; rm -rf "$tmp"; return "$cert_rc";;
    esac
}
# Stops and disables UNITS, remembering what each was, so migrate_restore_units can
# put them back. Disabled as well: a reboot must not start them next to srm.
MIGRATE_RESTORE=''
migrate_stop_units() {
    local unit active enabled
    MIGRATE_RESTORE=''
    for unit in "$@"; do
        active=0; enabled=0
        systemctl is-active --quiet "$unit" && active=1
        systemctl is-enabled --quiet "$unit" 2>/dev/null && enabled=1
        MIGRATE_RESTORE+="$unit $active $enabled"$'\n'
        msg "停止旧服务 $unit"
        if ! systemctl disable --now "$unit" >/dev/null 2>&1 && systemctl is-active --quiet "$unit"; then
            err "$unit 停不下来。"; return 1
        fi
    done
}
migrate_restore_units() {
    local unit active enabled failures=0
    while read -r unit active enabled; do
        [[ -n $unit ]] || continue
        [[ $enabled == 0 ]] || systemctl enable "$unit" >/dev/null 2>&1 || failures=1
        if [[ $active == 1 ]]; then
            msg "恢复旧服务 $unit"
            systemctl start "$unit" && systemctl is-active --quiet "$unit" || failures=1
        fi
    done <<< "$MIGRATE_RESTORE"
    return "$failures"
}
# Comments out v3's own cron jobs (V3_CRON_JOBS run by V3_ROOT/install.sh).
migrate_cron() {
    local current updated job pattern=''
    current=$(crontab -l 2>/dev/null) || return 0
    for job in $V3_CRON_JOBS; do pattern+="${pattern:+|}$job"; done
    updated=$(awk -v root="$V3_ROOT/install.sh" -v jobs="^($pattern)\$" -v mark="$MIGRATE_MARK" '
        { n = split($0, f, /[ \t]+/); hit = 0
          for (i = 1; i < n; i++) if (f[i] == root && f[i+1] ~ jobs) hit = 1
          if (hit && $0 !~ /^[ \t]*#/) print mark $0; else print }' <<< "$current") || return 1
    [[ $updated != "$current" ]] || return 0
    printf '%s\n' "$updated" | crontab - || return 1
    msg "已注释掉旧版定时任务（${V3_CRON_JOBS// /、}）。"
}
