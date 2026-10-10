# Protocol registry. Each protocol is one block of proto_<type>_<hook> functions;
# other modules dispatch through proto_call / proto_jq and never match on types.
#   label            display name
#   transport        tcp or udp, used by firewall rules and health checks
#   validate         jq boolean for the protocol's own node fields (def text available)
#   render_inbound   jq array of sing-box server inbounds for one node
#   share_uri        jq string: raw share link
#   client_outbound  jq object: sing-box client outbound
#   secrets          jq paths hidden from node details
#   prompt           ask protocol options; sets sni plus its own option variables
#   create           generate credentials after confirmation; REPLY = JSON fields
#   rotate           new credentials; REPLY = JSON fields to merge into the node
# Optional: retarget_label / retarget_select / retarget (change a Reality handshake target).
PROTO_HOOKS='label transport validate render_inbound share_uri client_outbound secrets prompt create rotate'
PROTOCOLS=''
PROTO_JQ_DEFS='
  def base_inbound: {tag:.id,listen:(.listen // "::"),listen_port:.port};
  def base_outbound: {tag:.name,server:.host,server_port:.port};
  def uri_host: if (.host|contains(":")) then "["+.host+"]" else .host end;
  def tls_files: {certificate_path:(.cert_dir+"/fullchain.pem"),key_path:(.cert_dir+"/key.pem")};
'
proto_register() {
    local type=$1 hook
    [[ $type =~ ^[a-z][a-z0-9]*$ ]] || { err "协议名不合法：$type"; return 1; }
    for hook in $PROTO_HOOKS; do
        declare -F "proto_${type}_$hook" >/dev/null || { err "协议 $type 缺少 proto_${type}_$hook，未注册。"; return 1; }
    done
    proto_known "$type" || PROTOCOLS="${PROTOCOLS:+$PROTOCOLS }$type"
}
proto_known() { [[ $1 =~ ^[a-z][a-z0-9]*$ && " $PROTOCOLS " == *" $1 "* ]]; }
proto_call() {
    local type=$1 hook=$2
    shift 2
    proto_known "$type" || { err "不支持的协议：${type:-空}（可选：$PROTOCOLS）"; return 1; }
    declare -F "proto_${type}_$hook" >/dev/null || { err "协议 $type 不支持此操作。"; return 1; }
    "proto_${type}_$hook" "$@"
}
proto_has() { proto_known "$1" && declare -F "proto_$1_$2" >/dev/null; }
# Builds `if .type=="a" then (<a hook>) elif … else <fallback> end` for jq.
proto_jq() {
    local hook=$1 fallback=$2 type out='' keyword=if
    for type in $PROTOCOLS; do
        out+="$keyword .type==\"$type\" then ($("proto_${type}_$hook")) "
        keyword=elif
    done
    printf '%s else %s end' "$out" "$fallback"
}
# Transport as a jq string expression, e.g. for firewall and listener checks.
proto_jq_transport() {
    local type out='' keyword=if
    for type in $PROTOCOLS; do
        out+="$keyword .type==\"$type\" then \"$("proto_${type}_transport")\" "
        keyword=elif
    done
    printf '%s else "tcp" end' "$out"
}
proto_by_index() {
    local type i=0
    for type in $PROTOCOLS; do
        i=$((i+1))
        [[ $1 != "$i" ]] || { printf '%s\n' "$type"; return 0; }
    done
    return 1
}
proto_labels() {
    local type out=''
    for type in $PROTOCOLS; do out+="${out:+ · }$("proto_${type}_label")"; done
    printf '%s\n' "$out"
}

# --- VLESS Reality -----------------------------------------------------------
REALITY_TARGETS='www.ctrip.com www.ixigua.com'
proto_vless_label() { printf 'VLESS Reality'; }
proto_vless_transport() { printf 'tcp'; }
proto_vless_validate() {
    printf '%s' '(.uuid|test("^[a-f0-9-]{36}$")) and (.private_key|text) and (.public_key|text) and (.short_id|test("^[a-f0-9]{16}$"))'
}
proto_vless_render_inbound() {
    printf '%s' '[base_inbound + {type:"vless",users:[{uuid:.uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:.sni,reality:{enabled:true,handshake:{server:.sni,server_port:443},private_key:.private_key,short_id:[.short_id]}}}]'
}
proto_vless_share_uri() {
    printf '%s' '"vless://\(.uuid)@\(uri_host):\(.port)?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&fp=chrome&sni=\(.sni|@uri)&pbk=\(.public_key|@uri)&sid=\(.short_id)#\(.name|@uri)"'
}
proto_vless_client_outbound() {
    printf '%s' 'base_outbound + {type:"vless",uuid:.uuid,flow:"xtls-rprx-vision",tls:{enabled:true,server_name:.sni,utls:{enabled:true,fingerprint:"chrome"},reality:{enabled:true,public_key:.public_key,short_id:.short_id}}}'
}
proto_vless_secrets() { printf '%s' '.uuid,.private_key,.public_key,.short_id'; }
proto_vless_prompt() {
    if [[ -n ${opt_sni:-} ]]; then
        reality_target_allowed "$opt_sni" || return 1
        sni=$opt_sni
    elif [[ ${assume_yes:-0} == 1 ]]; then sni=${REALITY_TARGETS%% *}
    else reality_target_select || return 1; sni=$REPLY; fi
}
proto_vless_create() {
    local pair private public uuid short
    reality_target_check "$sni" || return 1
    pair=$("$CORE" generate reality-keypair) || return 1
    private=$(printf '%s\n' "$pair" | awk '/PrivateKey:/{print $2}')
    public=$(printf '%s\n' "$pair" | awk '/PublicKey:/{print $2}')
    # Every node gets its own shortId; nothing is shared between deployments.
    uuid=$("$CORE" generate uuid) && short=$(random_hex 8) || return 1
    REPLY=$(jq -nc --arg uuid "$uuid" --arg private "$private" --arg public "$public" --arg short "$short" \
        '{uuid:$uuid,private_key:$private,public_key:$public,short_id:$short}')
}
proto_vless_rotate() {
    local uuid
    uuid=$("$CORE" generate uuid) || return 1
    REPLY=$(jq -nc --arg v "$uuid" '{uuid:$v}')
}
proto_vless_retarget_label() { printf '切换 Reality 目标（携程 / 西瓜视频）'; }
proto_vless_retarget_select() { reality_target_select; }
# REPLY = JSON fields to merge, or empty when the node already uses the target.
proto_vless_retarget() {
    local node=$1 target=$2
    reality_target_allowed "$target" || return 1
    if [[ $(printf '%s' "$node" | jq -r .sni) == "$target" ]]; then
        msg '当前已经使用此目标，无需修改。'; REPLY=''; return 0
    fi
    reality_target_check "$target" || return 1
    REPLY=$(jq -nc --arg sni "$target" '{sni:$sni}')
}
reality_target_allowed() {
    [[ " $REALITY_TARGETS " == *" $1 "* ]] || { err "Reality 目标只能选择：$REALITY_TARGETS"; return 1; }
}
reality_target_select() {
    msg $'Reality 握手目标（无需拥有该域名或申请证书）：\n1. 携程：www.ctrip.com\n2. 西瓜视频：www.ixigua.com'
    ask '选择目标（0 返回）' 1 || return 1
    case $REPLY in
      1) REPLY=www.ctrip.com;;
      2) REPLY=www.ixigua.com;;
      *) err '请选择 1 或 2。'; return 1;;
    esac
}
reality_target_check() {
    local domain=$1 output rc=0
    valid_domain "$domain" || return 1
    output=$(mktemp) || return 1
    msg "检查 Reality 目标 ${domain} 的 TLS 1.3、证书和 HTTP/2…"
    timeout 15 openssl s_client -connect "$domain:443" -servername "$domain" \
        -tls1_3 -alpn h2 -verify_hostname "$domain" -verify_return_error \
        </dev/null > "$output" 2>&1 || rc=$?
    if [[ $rc != 0 ]] || ! grep -q 'TLSv1.3' "$output" ||
       ! grep -q 'ALPN protocol: h2$' "$output" || ! grep -q 'Verify return code: 0 (ok)' "$output"; then
        rm -f "$output"
        err '目标检测失败，请重新部署并选择另一个目标，或检查本机 DNS / 网络 / 系统时间。'
        return 1
    fi
    rm -f "$output"
}

# --- Shared TLS certificate handling (AnyTLS, Hysteria2) ---------------------
# Option variables (mode email webroot cert key) are locals of node_add.
tls_prompt() {
    ask_opt "${opt_sni:-}" '证书域名' "$host" || return 1; sni=$REPLY
    if [[ -z ${opt_cert:-} && ${assume_yes:-0} != 1 ]]; then
        msg 'Lets Encrypt 免费证书：1.自动验证（使用空闲 80 或 443） 2.现有网站目录验证（网站保持运行） 3.导入已有证书'
    fi
    ask_opt "${opt_cert:-}" '证书方式' 1 || return 1
    case $REPLY in
      1|auto) mode=auto;;
      2|webroot) mode=webroot; ask_opt "${opt_webroot:-}" '现有网站根目录绝对路径' || return 1; webroot=$REPLY;;
      3|import)
        mode=import
        ask_opt "${opt_cert_file:-}" '完整证书链绝对路径' || return 1; cert=$REPLY
        ask_opt "${opt_key_file:-}" '私钥绝对路径' || return 1; key=$REPLY;;
      *) err '证书方式无效。'; return 1;;
    esac
    if [[ $mode != import ]]; then
        ask_opt "${opt_email:-}" '证书联系邮箱（可留空）' '' 1 || return 1; email=$REPLY
        [[ -z $email || $email == *@*.* ]] || { err '邮箱格式不正确。'; return 1; }
        msg '自动申请使用 Lets Encrypt；继续表示同意该机构的服务条款。'
    fi
}
tls_create() {
    local tmp password cert_rc
    if [[ $mode == import ]]; then
        cert_valid "$cert" "$key" "$sni" || { err '证书与域名/私钥不匹配，或一天内到期。'; return 1; }
        tmp=$(mktemp -d) || return 1
        cp "$cert" "$tmp/fullchain.pem" && cp "$key" "$tmp/key.pem" && activate_cert "$sni" "$tmp"
        cert_rc=$?; rm -rf "$tmp"; [[ $cert_rc == 0 ]] || return 1
        msg '导入的外部证书需由原签发工具续期，再导入新证书。'
    else issue_certificate "$sni" "$mode" "$email" "$webroot" || return 1; fi
    password=$(random_hex 24) || return 1
    REPLY=$(jq -nc --arg password "$password" --arg cert "$DATA/certs/$sni/active" '{password:$password,cert_dir:$cert}')
}
tls_validate() { printf '%s' '(.password|text) and (.cert_dir|text and startswith("/"))'; }
tls_rotate() {
    local value
    value=$(random_hex 24) || return 1
    REPLY=$(jq -nc --arg v "$value" '{password:$v}')
}

# --- AnyTLS ------------------------------------------------------------------
proto_anytls_label() { printf 'AnyTLS'; }
proto_anytls_transport() { printf 'tcp'; }
proto_anytls_validate() { tls_validate; }
proto_anytls_render_inbound() {
    printf '%s' '[base_inbound + {type:"anytls",users:[{name:.id,password:.password}],tls:({enabled:true,server_name:.sni} + tls_files)}]'
}
proto_anytls_share_uri() { printf '%s' '"anytls://\(.password|@uri)@\(uri_host):\(.port)?sni=\(.sni|@uri)#\(.name|@uri)"'; }
proto_anytls_client_outbound() { printf '%s' 'base_outbound + {type:"anytls",password:.password,tls:{enabled:true,server_name:.sni}}'; }
proto_anytls_secrets() { printf '%s' '.password'; }
proto_anytls_prompt() { tls_prompt; }
proto_anytls_create() { tls_create; }
proto_anytls_rotate() { tls_rotate; }

# --- Hysteria2 ---------------------------------------------------------------
proto_hysteria2_label() { printf 'Hysteria2'; }
proto_hysteria2_transport() { printf 'udp'; }
proto_hysteria2_validate() { tls_validate; }
proto_hysteria2_render_inbound() {
    printf '%s' '[base_inbound + {type:"hysteria2",users:[{name:.id,password:.password}],tls:({enabled:true,server_name:.sni,alpn:["h3"]} + tls_files)}]'
}
proto_hysteria2_share_uri() { printf '%s' '"hysteria2://\(.password|@uri)@\(uri_host):\(.port)?sni=\(.sni|@uri)&alpn=h3#\(.name|@uri)"'; }
proto_hysteria2_client_outbound() { printf '%s' 'base_outbound + {type:"hysteria2",password:.password,tls:{enabled:true,server_name:.sni,alpn:["h3"]}}'; }
proto_hysteria2_secrets() { printf '%s' '.password'; }
proto_hysteria2_prompt() { tls_prompt; }
proto_hysteria2_create() { tls_create; }
proto_hysteria2_rotate() { tls_rotate; }

proto_register vless
proto_register anytls
proto_register hysteria2
