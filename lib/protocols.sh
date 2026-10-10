# Protocol registry. Each protocol is one block of proto_<type>_<hook> functions;
# other modules dispatch through proto_call / proto_jq and never match on types.
#   label            display name
#   transport        "tcp", "udp" or "tcp udp", used by firewall rules and health checks
#   validate         jq boolean for the protocol's own node fields (def text available)
#   render_inbound   jq array of sing-box server inbounds for one node
#   share_uri        jq string: raw share link (Shadowrocket, v2rayN and others import it)
#   client_outbound  jq object: sing-box client outbound
#   secrets          jq paths hidden from node details
#   prompt           ask protocol options; sets sni (empty when unused) plus its own option variables
#   create           generate credentials after confirmation; REPLY = JSON fields
#   rotate           new credentials; REPLY = JSON fields to merge into the node
# Optional: clash (jq object: Clash Meta / mihomo proxy), surge (jq string: Surge proxy line),
# retarget_label / retarget_select / retarget (change a Reality handshake target).
PROTO_HOOKS='label transport validate render_inbound share_uri client_outbound secrets prompt create rotate'
PROTOCOLS=''
PROTO_JQ_DEFS='
  def base_inbound: {tag:.id,listen:(.listen // "::"),listen_port:.port};
  def base_outbound: {tag:.name,server:.host,server_port:.port};
  def uri_host: if (.host|contains(":")) then "["+.host+"]" else .host end;
  def tls_files: {certificate_path:(.cert_dir+"/fullchain.pem"),key_path:(.cert_dir+"/key.pem")};
  # Self-signed nodes carry their certificate hashes; clients pin them instead of trusting a CA.
  def pinned: .cert_sha256 != null;
  def tls_client: {enabled:true,server_name:.sni} + (if pinned then {certificate_public_key_sha256:[.pubkey_sha256]} else {} end);
  def clash_base: {name:.name,server:.host,port:.port};
  def clash_pin: if pinned then {fingerprint:.cert_sha256} else {} end;
  def surge_head($type): "\(.name|gsub("[,=]";" ")) = \($type), \(.host), \(.port)";
  def surge_pin: if pinned then ", server-cert-fingerprint-sha256=\(.cert_sha256)" else "" end;
'
proto_register() {
    local type=$1 hook
    [[ $type =~ ^[a-z][a-z0-9]*$ ]] || { err "协议名不合法：$type"; return 1; }
    for hook in $PROTO_HOOKS; do
        declare -F "proto_${type}_$hook" >/dev/null || { err "协议 $type 缺少 proto_${type}_$hook，未注册。"; return 1; }
    done
    # Optional hooks come as a complete group or not at all.
    local optional=0
    for hook in retarget retarget_select retarget_label; do declare -F "proto_${type}_$hook" >/dev/null && optional=$((optional+1)); done
    (( optional == 0 || optional == 3 )) || { err "协议 $type 的 retarget 钩子不完整，未注册。"; return 1; }
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
# Builds `if .type=="a" then (<a hook>) elif … else <fallback> end` for jq;
# protocols without an optional hook fall through to the fallback.
proto_jq() {
    local hook=$1 fallback=$2 type out='' keyword=if
    for type in $PROTOCOLS; do
        declare -F "proto_${type}_$hook" >/dev/null || continue
        out+="$keyword .type==\"$type\" then ($("proto_${type}_$hook")) "
        keyword=elif
    done
    if [[ -z $out ]]; then printf '%s' "$fallback"; else printf '%s else %s end' "$out" "$fallback"; fi
}
# Transports as a jq array expression, e.g. ["tcp","udp"], for firewall and listener checks.
proto_jq_transports() {
    local type out='' keyword=if
    for type in $PROTOCOLS; do
        out+="$keyword .type==\"$type\" then (\"$("proto_${type}_transport")\"|split(\" \")) "
        keyword=elif
    done
    printf '%s else ["tcp"] end' "$out"
}
proto_by_index() {
    local type i=0
    for type in $PROTOCOLS; do
        i=$((i+1))
        [[ $1 != "$i" ]] || { printf '%s\n' "$type"; return 0; }
    done
    return 1
}
# All labels, or only the first N followed by the total count.
proto_labels() {
    local type out='' count=0
    for type in $PROTOCOLS; do
        count=$((count+1))
        [[ -n ${1:-} ]] && (( count > $1 )) && continue
        out+="${out:+ · }$("proto_${type}_label")"
    done
    if [[ -n ${1:-} ]] && (( count > $1 )); then out+=" 等 $count 种协议"; fi
    printf '%s\n' "$out"
}

# --- VLESS Reality -----------------------------------------------------------
REALITY_TARGETS='www.ctrip.com www.ixigua.com'
proto_vless_label() { printf 'VLESS Reality'; }
proto_vless_transport() { printf 'tcp'; }
proto_vless_validate() {
    printf '%s' '(.sni|text) and (.uuid|test("^[a-f0-9-]{36}$")) and (.private_key|text) and (.public_key|text) and (.short_id|test("^[a-f0-9]{16}$"))'
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
proto_vless_clash() {
    printf '%s' 'clash_base + {type:"vless",uuid:.uuid,network:"tcp",tls:true,udp:true,flow:"xtls-rprx-vision",servername:.sni,
      "reality-opts":{"public-key":.public_key,"short-id":.short_id},"client-fingerprint":"chrome"}'
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

# --- Shared TLS certificate handling ------------------------------------------
# Option variables (mode email webroot cert key) are locals of node_add.
# A protocol whose clients can pin a certificate passes "selfsigned": it then also
# offers a self-signed certificate, the default when the server has no domain.
SELF_SIGNED_SNI=www.bing.com
tls_prompt() {
    local allow=${1:-} default=1 domain=''
    # valid_domain also accepts dotted IPv4 addresses, which cannot get a certificate.
    if [[ ! $host =~ ^[0-9.]+$ ]] && valid_domain "$host"; then domain=$host; fi
    # Without any domain (no domain host, no --sni) the self-signed certificate is the default.
    [[ $allow != selfsigned || -n $domain || -n ${opt_sni:-} ]] || default=4
    if [[ -z ${opt_cert:-} && ${assume_yes:-0} != 1 ]]; then
        msg 'Lets Encrypt 免费证书：1.自动验证（使用空闲 80 或 443） 2.现有网站目录验证（网站保持运行） 3.导入已有证书'
        [[ $allow != selfsigned ]] || msg '不用域名：4.自签证书（客户端按证书指纹校验）'
    fi
    ask_opt "${opt_cert:-}" '证书方式' "$default" || return 1
    case $REPLY in
      1|auto) mode=auto;;
      2|webroot) mode=webroot;;
      3|import) mode=import;;
      4|selfsigned)
        [[ $allow == selfsigned ]] || { err '此协议需要域名证书，不支持自签证书。'; return 1; }
        mode=selfsigned; sni=${opt_sni:-$SELF_SIGNED_SNI}; return 0;;
      *) err '证书方式无效。'; return 1;;
    esac
    ask_opt "${opt_sni:-}" '证书域名（需解析到本机）' "$domain" || return 1; sni=$REPLY
    case $mode in
      webroot) ask_opt "${opt_webroot:-}" '现有网站根目录绝对路径' || return 1; webroot=$REPLY;;
      import)
        ask_opt "${opt_cert_file:-}" '完整证书链绝对路径' || return 1; cert=$REPLY
        ask_opt "${opt_key_file:-}" '私钥绝对路径' || return 1; key=$REPLY;;
    esac
    if [[ $mode != import ]]; then
        ask_opt "${opt_email:-}" '证书联系邮箱（可留空）' '' 1 || return 1; email=$REPLY
        [[ -z $email || $email == *@*.* ]] || { err '邮箱格式不正确。'; return 1; }
        msg '自动申请使用 Lets Encrypt；继续表示同意该机构的服务条款。'
    fi
}
# REPLY = certificate fields of the node: cert_dir, plus the pins of a self-signed one.
tls_create() {
    local tmp cert_rc
    case $mode in
      selfsigned) selfsigned_create; return;;
      import)
        cert_valid "$cert" "$key" "$sni" || { err '证书与域名/私钥不匹配，或一天内到期。'; return 1; }
        tmp=$(mktemp -d) || return 1
        cp "$cert" "$tmp/fullchain.pem" && cp "$key" "$tmp/key.pem" && activate_cert "$sni" "$tmp"
        cert_rc=$?; rm -rf "$tmp"; [[ $cert_rc == 0 ]] || return 1
        msg '导入的外部证书需由原签发工具续期，再导入新证书。';;
      *) issue_certificate "$sni" "$mode" "$email" "$webroot" || return 1;;
    esac
    REPLY=$(jq -nc --arg cert "$DATA/certs/$sni/active" '{cert_dir:$cert}')
}
# One self-signed certificate per node ($id is node_add's new node ID), valid for
# ten years and never renewed; clients pin its hashes.
selfsigned_create() {
    local dir=$DATA/selfsigned/$id cert_hash key_hash
    install -d -m 750 "$DATA/selfsigned" "$dir" && chgrp srm "$DATA/selfsigned" "$dir" || return 1
    if ! openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 3650 -subj "/CN=$sni" \
         -addext "subjectAltName=DNS:$sni" -keyout "$dir/key.pem" -out "$dir/fullchain.pem" >/dev/null 2>&1; then
        err '自签证书生成失败。'; return 1
    fi
    chmod 640 "$dir/key.pem" "$dir/fullchain.pem" && chgrp srm "$dir/key.pem" "$dir/fullchain.pem" || return 1
    # Certificate hash (Surge, mihomo, Hysteria2 links) and public key hash (sing-box).
    cert_hash=$(openssl x509 -in "$dir/fullchain.pem" -outform der | openssl dgst -sha256 | awk '{print $NF}') &&
        key_hash=$(openssl x509 -in "$dir/fullchain.pem" -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64 -A) || return 1
    REPLY=$(jq -nc --arg dir "$dir" --arg cert "$cert_hash" --arg key "$key_hash" '{cert_dir:$dir,cert_sha256:$cert,pubkey_sha256:$key}')
}
tls_validate() {
    printf '%s' '(.sni|text) and (.cert_dir|text and startswith("/")) and
      ((pinned|not) or ((.cert_sha256|test("^[a-f0-9]{64}$")) and (.pubkey_sha256|test("^[A-Za-z0-9+/]{43}=$"))))'
}
# Merges new credentials into REPLY (from tls_create) or into an empty object.
with_password() {
    local value
    value=$(random_hex 24) || return 1
    REPLY=$(jq -c --arg v "$value" '. + {password:$v}' <<< "${REPLY:-null}")
}
with_uuid() {
    local value
    value=$("$CORE" generate uuid) || return 1
    REPLY=$(jq -c --arg v "$value" '. + {uuid:$v}' <<< "${REPLY:-null}")
}
UUID_VALID='(.uuid|test("^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"))'

# --- AnyTLS ------------------------------------------------------------------
proto_anytls_label() { printf 'AnyTLS'; }
proto_anytls_transport() { printf 'tcp'; }
proto_anytls_validate() { printf '%s and (.password|text)' "$(tls_validate)"; }
proto_anytls_render_inbound() {
    printf '%s' '[base_inbound + {type:"anytls",users:[{name:.id,password:.password}],tls:({enabled:true,server_name:.sni} + tls_files)}]'
}
proto_anytls_share_uri() { printf '%s' '"anytls://\(.password|@uri)@\(uri_host):\(.port)?sni=\(.sni|@uri)#\(.name|@uri)"'; }
proto_anytls_client_outbound() { printf '%s' 'base_outbound + {type:"anytls",password:.password,tls:tls_client}'; }
proto_anytls_clash() { printf '%s' 'clash_base + {type:"anytls",password:.password,sni:.sni,udp:true}'; }
proto_anytls_surge() { printf '%s' '"\(surge_head("anytls")), password=\"\(.password)\", sni=\(.sni)"'; }
proto_anytls_secrets() { printf '%s' '.password'; }
proto_anytls_prompt() { tls_prompt; }
proto_anytls_create() { tls_create && with_password; }
proto_anytls_rotate() { REPLY=''; with_password; }

# --- Hysteria2 ---------------------------------------------------------------
proto_hysteria2_label() { printf 'Hysteria2'; }
proto_hysteria2_transport() { printf 'udp'; }
proto_hysteria2_validate() { proto_anytls_validate; }
proto_hysteria2_render_inbound() {
    printf '%s' '[base_inbound + {type:"hysteria2",users:[{name:.id,password:.password}],tls:({enabled:true,server_name:.sni,alpn:["h3"]} + tls_files)}]'
}
# The official client checks pinSHA256 only after normal verification, so a
# self-signed link also needs insecure=1 (v2.hysteria.network, client docs).
proto_hysteria2_share_uri() {
    printf '%s' '"hysteria2://\(.password|@uri)@\(uri_host):\(.port)?sni=\(.sni|@uri)&alpn=h3\(if pinned then "&insecure=1&pinSHA256=\(.cert_sha256)" else "" end)#\(.name|@uri)"'
}
proto_hysteria2_client_outbound() { printf '%s' 'base_outbound + {type:"hysteria2",password:.password,tls:(tls_client + {alpn:["h3"]})}'; }
proto_hysteria2_clash() { printf '%s' 'clash_base + {type:"hysteria2",password:.password,sni:.sni,alpn:["h3"]} + clash_pin'; }
proto_hysteria2_surge() { printf '%s' '"\(surge_head("hysteria2")), password=\"\(.password)\", sni=\(.sni)\(surge_pin)"'; }
proto_hysteria2_secrets() { printf '%s' '.password'; }
proto_hysteria2_prompt() { tls_prompt selfsigned; }
proto_hysteria2_create() { tls_create && with_password; }
proto_hysteria2_rotate() { REPLY=''; with_password; }

# --- Shadowsocks 2022 --------------------------------------------------------
# One method; its key is 16 random bytes in base64. TCP and UDP share the port.
SS_METHOD=2022-blake3-aes-128-gcm
proto_shadowsocks_label() { printf 'Shadowsocks 2022'; }
proto_shadowsocks_transport() { printf 'tcp udp'; }
proto_shadowsocks_validate() {
    printf '%s' '.sni == null and .method == "'"$SS_METHOD"'" and (.password|test("^[A-Za-z0-9+/]{22}==$"))'
}
proto_shadowsocks_render_inbound() { printf '%s' '[base_inbound + {type:"shadowsocks",method:.method,password:.password}]'; }
# SIP002: AEAD-2022 userinfo is not base64, method and password are percent-encoded.
proto_shadowsocks_share_uri() { printf '%s' '"ss://\(.method):\(.password|@uri)@\(uri_host):\(.port)#\(.name|@uri)"'; }
proto_shadowsocks_client_outbound() { printf '%s' 'base_outbound + {type:"shadowsocks",method:.method,password:.password}'; }
proto_shadowsocks_clash() { printf '%s' 'clash_base + {type:"ss",cipher:.method,password:.password,udp:true}'; }
proto_shadowsocks_surge() { printf '%s' '"\(surge_head("ss")), encrypt-method=\(.method), password=\"\(.password)\", udp-relay=true"'; }
proto_shadowsocks_secrets() { printf '%s' '.password'; }
proto_shadowsocks_prompt() { sni=''; }
proto_shadowsocks_create() {
    local key
    key=$(openssl rand -base64 16) || return 1
    REPLY=$(jq -nc --arg m "$SS_METHOD" --arg k "$key" '{method:$m,password:$k}')
}
proto_shadowsocks_rotate() {
    proto_shadowsocks_create && REPLY=$(jq -c '{password}' <<< "$REPLY")
}

# --- TUIC v5 -----------------------------------------------------------------
proto_tuic_label() { printf 'TUIC v5'; }
proto_tuic_transport() { printf 'udp'; }
proto_tuic_validate() { printf '%s and %s and (.password|text)' "$(tls_validate)" "$UUID_VALID"; }
proto_tuic_render_inbound() {
    printf '%s' '[base_inbound + {type:"tuic",users:[{name:.id,uuid:.uuid,password:.password}],congestion_control:"bbr",tls:({enabled:true,server_name:.sni,alpn:["h3"]} + tls_files)}]'
}
# tuic:// has no pin parameter; clients that cannot pin need allow_insecure=1.
proto_tuic_share_uri() {
    printf '%s' '"tuic://\(.uuid):\(.password|@uri)@\(uri_host):\(.port)?congestion_control=bbr&alpn=h3&sni=\(.sni|@uri)&udp_relay_mode=native\(if pinned then "&allow_insecure=1" else "" end)#\(.name|@uri)"'
}
proto_tuic_client_outbound() {
    printf '%s' 'base_outbound + {type:"tuic",uuid:.uuid,password:.password,congestion_control:"bbr",tls:(tls_client + {alpn:["h3"]})}'
}
proto_tuic_clash() {
    printf '%s' 'clash_base + {type:"tuic",uuid:.uuid,password:.password,alpn:["h3"],"congestion-controller":"bbr","udp-relay-mode":"native",sni:.sni} + clash_pin'
}
proto_tuic_surge() { printf '%s' '"\(surge_head("tuic-v5")), password=\"\(.password)\", uuid=\(.uuid), alpn=h3, sni=\(.sni)\(surge_pin)"'; }
proto_tuic_secrets() { printf '%s' '.uuid,.password'; }
proto_tuic_prompt() { tls_prompt selfsigned; }
proto_tuic_create() { tls_create && with_uuid && with_password; }
proto_tuic_rotate() { REPLY=''; with_uuid && with_password; }

# --- VLESS + TLS (tcp Vision / ws / grpc / httpupgrade) ----------------------
# Node field "transport" picks the stream; ws and httpupgrade carry a random
# path, grpc a random service name. ws and httpupgrade can sit behind a CDN.
proto_vlesstls_label() { printf 'VLESS TLS'; }
proto_vlesstls_transport() { printf 'tcp'; }
proto_vlesstls_validate() {
    printf '%s and %s and %s' "$(tls_validate)" "$UUID_VALID" '(
      (.transport == "tcp") or
      ((.transport == "ws" or .transport == "httpupgrade") and (.path|test("^/[A-Za-z0-9_-]+$"))) or
      (.transport == "grpc" and (.service_name|test("^[A-Za-z0-9_-]+$"))))'
}
STREAM_JQ_DEFS='
  def stream_alpn: if .transport == "grpc" then ["h2"] elif .transport == "tcp" then null else ["http/1.1"] end;
  def stream_server: if .transport == "ws" then {transport:{type:"ws",path:.path}}
    elif .transport == "httpupgrade" then {transport:{type:"httpupgrade",path:.path}}
    elif .transport == "grpc" then {transport:{type:"grpc",service_name:.service_name}} else {} end;
  def stream_client: if .transport == "ws" then {transport:{type:"ws",path:.path,headers:{Host:.sni}}}
    elif .transport == "httpupgrade" then {transport:{type:"httpupgrade",path:.path,host:.sni}}
    elif .transport == "grpc" then {transport:{type:"grpc",service_name:.service_name}} else {} end;
  def stream_query: "type=\(.transport)" + (if .transport == "tcp" then "&flow=xtls-rprx-vision"
    elif .transport == "grpc" then "&serviceName=\(.service_name)&mode=gun&alpn=h2"
    else "&host=\(.sni|@uri)&path=\(.path|@uri)&alpn=http%2F1.1" end);
  def stream_clash: if .transport == "tcp" then {network:"tcp",flow:"xtls-rprx-vision"}
    elif .transport == "grpc" then {network:"grpc","grpc-opts":{"grpc-service-name":.service_name}}
    else {network:"ws","ws-opts":({path:.path,headers:{Host:.sni}} + (if .transport == "httpupgrade" then {"v2ray-http-upgrade":true} else {} end))} end;
'
PROTO_JQ_DEFS+=$STREAM_JQ_DEFS
proto_vlesstls_render_inbound() {
    printf '%s' '[base_inbound + {type:"vless",users:[{name:.id,uuid:.uuid} + (if .transport == "tcp" then {flow:"xtls-rprx-vision"} else {} end)],
      tls:({enabled:true,server_name:.sni} + (if stream_alpn then {alpn:stream_alpn} else {} end) + tls_files)} + stream_server]'
}
proto_vlesstls_share_uri() {
    printf '%s' '"vless://\(.uuid)@\(uri_host):\(.port)?encryption=none&security=tls&sni=\(.sni|@uri)&fp=chrome&\(stream_query)#\(.name|@uri)"'
}
proto_vlesstls_client_outbound() {
    printf '%s' 'base_outbound + {type:"vless",uuid:.uuid} + (if .transport == "tcp" then {flow:"xtls-rprx-vision"} else {} end)
      + {tls:(tls_client + {utls:{enabled:true,fingerprint:"chrome"}} + (if stream_alpn then {alpn:stream_alpn} else {} end))} + stream_client'
}
proto_vlesstls_clash() {
    printf '%s' 'clash_base + {type:"vless",uuid:.uuid,tls:true,servername:.sni,"client-fingerprint":"chrome",udp:true} + stream_clash'
}
proto_vlesstls_secrets() { printf '%s' '.uuid'; }
# Sets stream (a local of node_add) from --transport or the menu.
proto_vlesstls_prompt() {
    tls_prompt || return 1
    [[ -n ${opt_transport:-} || ${assume_yes:-0} == 1 ]] ||
        msg '传输方式：1.tcp（Vision，直连最快） 2.ws（可套 CDN） 3.grpc 4.httpupgrade（可套 CDN）'
    ask_opt "${opt_transport:-}" '传输方式' 1 || return 1
    case $REPLY in
      1|tcp) stream=tcp;; 2|ws) stream=ws;; 3|grpc) stream=grpc;; 4|httpupgrade) stream=httpupgrade;;
      *) err '传输方式只能是 tcp、ws、grpc 或 httpupgrade。'; return 1;;
    esac
}
proto_vlesstls_create() {
    local route
    route=$(random_hex 8) && tls_create && with_uuid || return 1
    REPLY=$(jq -c --arg t "$stream" --arg r "$route" '. + {transport:$t} +
      (if $t == "grpc" then {service_name:$r} elif $t == "tcp" then {} else {path:("/"+$r)} end)' <<< "$REPLY")
}
proto_vlesstls_rotate() { REPLY=''; with_uuid; }

# --- Trojan ------------------------------------------------------------------
proto_trojan_label() { printf 'Trojan'; }
proto_trojan_transport() { printf 'tcp'; }
proto_trojan_validate() { proto_anytls_validate; }
proto_trojan_render_inbound() {
    printf '%s' '[base_inbound + {type:"trojan",users:[{name:.id,password:.password}],tls:({enabled:true,server_name:.sni} + tls_files)}]'
}
proto_trojan_share_uri() { printf '%s' '"trojan://\(.password|@uri)@\(uri_host):\(.port)?security=tls&sni=\(.sni|@uri)&type=tcp#\(.name|@uri)"'; }
proto_trojan_client_outbound() { printf '%s' 'base_outbound + {type:"trojan",password:.password,tls:tls_client}'; }
proto_trojan_clash() { printf '%s' 'clash_base + {type:"trojan",password:.password,sni:.sni,udp:true}'; }
proto_trojan_surge() { printf '%s' '"\(surge_head("trojan")), password=\"\(.password)\", sni=\(.sni)"'; }
proto_trojan_secrets() { printf '%s' '.password'; }
proto_trojan_prompt() { tls_prompt; }
proto_trojan_create() { tls_create && with_password; }
proto_trojan_rotate() { REPLY=''; with_password; }

# --- VMess (TLS + ws) --------------------------------------------------------
# alterId 0: VMess AEAD only. Kept for older clients.
proto_vmess_label() { printf 'VMess TLS+ws'; }
proto_vmess_transport() { printf 'tcp'; }
proto_vmess_validate() { printf '%s and %s and %s' "$(tls_validate)" "$UUID_VALID" '(.path|test("^/[A-Za-z0-9_-]+$"))'; }
proto_vmess_render_inbound() {
    printf '%s' '[base_inbound + {type:"vmess",users:[{name:.id,uuid:.uuid,alterId:0}],
      tls:({enabled:true,server_name:.sni,alpn:["http/1.1"]} + tls_files),transport:{type:"ws",path:.path}}]'
}
# v2rayN format: vmess:// + base64 of a JSON object with string values.
proto_vmess_share_uri() {
    printf '%s' '"vmess://" + ({v:"2",ps:.name,add:.host,port:(.port|tostring),id:.uuid,aid:"0",scy:"auto",net:"ws",type:"none",
      host:.sni,path:.path,tls:"tls",sni:.sni,alpn:"http/1.1",fp:"chrome"}|tojson|@base64)'
}
proto_vmess_client_outbound() {
    printf '%s' 'base_outbound + {type:"vmess",uuid:.uuid,security:"auto",alter_id:0,
      tls:(tls_client + {utls:{enabled:true,fingerprint:"chrome"},alpn:["http/1.1"]}),transport:{type:"ws",path:.path,headers:{Host:.sni}}}'
}
proto_vmess_clash() {
    printf '%s' 'clash_base + {type:"vmess",uuid:.uuid,alterId:0,cipher:"auto",tls:true,servername:.sni,udp:true,network:"ws","ws-opts":{path:.path,headers:{Host:.sni}}}'
}
proto_vmess_surge() {
    printf '%s' '"\(surge_head("vmess")), username=\(.uuid), ws=true, ws-path=\(.path), ws-headers=Host:\(.sni), tls=true, sni=\(.sni), vmess-aead=true"'
}
proto_vmess_secrets() { printf '%s' '.uuid'; }
proto_vmess_prompt() { tls_prompt; }
proto_vmess_create() {
    local route
    route=$(random_hex 8) && tls_create && with_uuid || return 1
    REPLY=$(jq -c --arg r "/$route" '. + {path:$r}' <<< "$REPLY")
}
proto_vmess_rotate() { REPLY=''; with_uuid; }

# --- Naive -------------------------------------------------------------------
# HTTP/2 over TLS only (no QUIC). Naive clients connect by the certificate domain,
# so the link uses sni as its host. Clash Meta and Surge have no naive client.
proto_naive_label() { printf 'Naive'; }
proto_naive_transport() { printf 'tcp'; }
proto_naive_validate() { printf '%s and (.username|test("^[a-f0-9]{12}$")) and (.password|text)' "$(tls_validate)"; }
proto_naive_render_inbound() {
    printf '%s' '[base_inbound + {type:"naive",network:"tcp",users:[{username:.username,password:.password}],tls:({enabled:true,server_name:.sni} + tls_files)}]'
}
proto_naive_share_uri() { printf '%s' '"naive+https://\(.username):\(.password|@uri)@\(.sni):\(.port)#\(.name|@uri)"'; }
proto_naive_client_outbound() { printf '%s' 'base_outbound + {type:"naive",username:.username,password:.password,tls:tls_client}'; }
proto_naive_secrets() { printf '%s' '.username,.password'; }
proto_naive_prompt() { tls_prompt; }
proto_naive_create() {
    local user
    user=$(random_hex 6) && tls_create && with_password || return 1
    REPLY=$(jq -c --arg u "$user" '. + {username:$u}' <<< "$REPLY")
}
proto_naive_rotate() { REPLY=''; with_password; }

# --- Hysteria v1 (older clients only) ----------------------------------------
# Clients must state their bandwidth; links and snippets use 30 Mbps up and
# 100 Mbps down, which users can raise in their client.
proto_hysteria_label() { printf 'Hysteria v1（兼容老客户端）'; }
proto_hysteria_transport() { printf 'udp'; }
proto_hysteria_validate() { proto_anytls_validate; }
proto_hysteria_render_inbound() {
    printf '%s' '[base_inbound + {type:"hysteria",up_mbps:1000,down_mbps:1000,users:[{name:.id,auth_str:.password}],
      tls:({enabled:true,server_name:.sni,alpn:["hysteria"]} + tls_files)}]'
}
proto_hysteria_share_uri() {
    printf '%s' '"hysteria://\(uri_host):\(.port)?protocol=udp&auth=\(.password|@uri)&peer=\(.sni|@uri)&upmbps=30&downmbps=100&alpn=hysteria\(if pinned then "&insecure=1" else "" end)#\(.name|@uri)"'
}
proto_hysteria_client_outbound() {
    printf '%s' 'base_outbound + {type:"hysteria",up_mbps:30,down_mbps:100,auth_str:.password,tls:(tls_client + {alpn:["hysteria"]})}'
}
proto_hysteria_clash() {
    printf '%s' 'clash_base + {type:"hysteria","auth-str":.password,up:"30 Mbps",down:"100 Mbps",protocol:"udp",sni:.sni,alpn:["hysteria"]} + clash_pin'
}
proto_hysteria_secrets() { printf '%s' '.password'; }
proto_hysteria_prompt() { tls_prompt selfsigned; }
proto_hysteria_create() { tls_create && with_password; }
proto_hysteria_rotate() { REPLY=''; with_password; }

proto_register vless
proto_register anytls
proto_register hysteria2
proto_register shadowsocks
proto_register tuic
proto_register vlesstls
proto_register trojan
proto_register vmess
proto_register naive
proto_register hysteria
