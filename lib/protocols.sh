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
# note (jq string shown with the client snippets), retarget_label / retarget_select /
# retarget (change a TLS handshake target), and the sidecar pair for a protocol served
# by its own program next to sing-box: sidecar (jq string: systemd unit of the node,
# which listens on 127.0.0.1:.local_port) and sidecar_render NODE DIR (writes the
# node's files into the generation, so switching generations switches them too).
# A protocol whose server program srm downloads adds the program group, used by the
# version check and manual updates: program_label (name shown to users), program_key
# (jq string: the program variant a node runs, e.g. "v6"), program_path KEY,
# program_current KEY (installed version), program_latest KEY… (one network lookup;
# prints KEY<TAB>VERSION lines) and program_fetch KEY VERSION TARGET (download and verify).
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
    optional=0
    for hook in sidecar sidecar_render; do declare -F "proto_${type}_$hook" >/dev/null && optional=$((optional+1)); done
    (( optional == 0 || optional == 2 )) || { err "协议 $type 的 sidecar 钩子不完整，未注册。"; return 1; }
    optional=0
    for hook in program_label program_key program_path program_current program_latest program_fetch; do declare -F "proto_${type}_$hook" >/dev/null && optional=$((optional+1)); done
    (( optional == 0 || optional == 6 )) || { err "协议 $type 的 program 钩子不完整，未注册。"; return 1; }
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
proto_vless_prompt() { handshake_target_prompt; }
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
proto_vless_retarget() { handshake_retarget "$@"; }
# Reality and ShadowTLS borrow the TLS 1.3 handshake of the same vetted sites.
handshake_target_prompt() {
    if [[ -n ${opt_sni:-} ]]; then
        reality_target_allowed "$opt_sni" || return 1
        sni=$opt_sni
    elif [[ ${assume_yes:-0} == 1 ]]; then sni=${REALITY_TARGETS%% *}
    else reality_target_select || return 1; sni=$REPLY; fi
}
handshake_retarget() {
    local node=$1 target=$2
    reality_target_allowed "$target" || return 1
    if [[ $(printf '%s' "$node" | jq -r .sni) == "$target" ]]; then
        msg '当前已经使用此目标，无需修改。'; REPLY=''; return 0
    fi
    reality_target_check "$target" || return 1
    REPLY=$(jq -nc --arg sni "$target" '{sni:$sni}')
}
reality_target_allowed() {
    [[ " $REALITY_TARGETS " == *" $1 "* ]] || { err "握手目标只能选择：$REALITY_TARGETS"; return 1; }
}
reality_target_select() {
    msg $'握手目标（无需拥有该域名或申请证书）：\n1. 携程：www.ctrip.com\n2. 西瓜视频：www.ixigua.com'
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
    msg "检查握手目标 ${domain} 的 TLS 1.3、证书和 HTTP/2…"
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

# --- Snell v6 / v5 + ShadowTLS v3 --------------------------------------------
# The official snell-server runs as its own service srm-snell@<node id> and listens
# only on 127.0.0.1:.local_port. Clients reach it through sing-box: the shadowtls
# inbound answers on the node port and hands the stream (detour) to a direct inbound
# whose override_address/override_port point at snell-server, so the front end goes
# through sing-box check, the generation switch and rollback like any other node.
# Routing rules do not apply: snell-server makes its own outbound connections.
# Deploying installs a pinned build, checked against the SHA-256 of the official zip
# (the vendor publishes no checksums): https://dl.nssurge.com/snell/snell-server-v<version>-linux-<arch>.zip,
# versions from kb.nssurge.com/surge-knowledge-base/release-notes/snell (2026-10-10:
# v6.0.0rc2 is the newest v6, v5.0.1 the newest v5). Manual updates take the newest
# build of the node's major version listed there; a build without a pinned SHA-256
# relies on HTTPS from the vendor and must report its own version when run.
SNELL_V6=6.0.0rc2
SNELL_V5=5.0.1
SNELL_NOTES=https://kb.nssurge.com/surge-knowledge-base/release-notes/snell
snell_download() {
    local major=$1 target=$2 version=${3:-} arch hash='' tmp
    case $major in 6) version=${version:-$SNELL_V6};; 5) version=${version:-$SNELL_V5};; *) err 'Snell 版本只能是 6 或 5。'; return 1;; esac
    [[ $version =~ ^$major\.[0-9]+\.[0-9]+((b|beta|rc)[0-9]*)?$ ]] || { err "Snell 版本号不合法：$version"; return 1; }
    case $(uname -m) in x86_64) arch=amd64;; aarch64|arm64) arch=aarch64;; *) err 'Snell 只支持 amd64/arm64。'; return 1;; esac
    case $version-$arch in
      6.0.0rc2-amd64) hash=8a9c4463ca87cfa5eaa37c6af0d37ab93ea275aa12391985bb2a375ca3abd7f2;;
      6.0.0rc2-aarch64) hash=a0b2915cbc77dc3baf8fa069e741c20808d8a10c3a8a93e709a0a580645c3bd7;;
      5.0.1-amd64) hash=9bea1c2b9e35b73b31634856c04d18c393072b9e5dcde6a32781d8b8f908c539;;
      5.0.1-aarch64) hash=2f178bf5ac468ce1a130454efa40a0603fbbe4e47ecc4880a989f4abc7f824cf;;
    esac
    # `snell-server -v` prints "snell-server v6.0.0 (…)" for 6.0.0rc2, so the
    # version without its beta/RC suffix is compared; running it also proves the
    # binary loads here. As root it runs as the service user, like the service does,
    # from a directory under /tmp that user can enter.
    local run=()
    if [[ $EUID == 0 ]] && id srm >/dev/null 2>&1 && command -v runuser >/dev/null; then
        tmp=$(mktemp -d /tmp/srm-snell.XXXXXXXX) && chmod 755 "$tmp" || return 1
        run=(runuser -u srm --)
    else tmp=$(mktemp -d) || return 1; fi
    if fetch "https://dl.nssurge.com/snell/snell-server-v$version-linux-$arch.zip" "$tmp/snell.zip" &&
       [[ -z $hash || $(sha256 "$tmp/snell.zip") == "$hash" ]] &&
       unzip -p "$tmp/snell.zip" snell-server > "$tmp/snell-server" && chmod 755 "$tmp/snell-server" &&
       ${run[@]+"${run[@]}"} "$tmp/snell-server" -v 2>&1 | grep -qF "snell-server v${version%%[a-z]*}" &&
       install -m 755 "$tmp/snell-server" "$target"; then
        rm -rf "$tmp"; return 0
    fi
    rm -rf "$tmp"; err "Snell $version 下载、SHA256 校验或试运行失败。"; return 1
}
# Newest build of MAJOR in the release notes on stdin: the newest release, or the
# newest beta/RC while the major version has no release yet.
snell_pick() {
    local versions stable
    versions=$(grep -oE "snell-server-v$1\.[0-9]+\.[0-9]+((b|beta|rc)[0-9]*)?-linux-" | sed -E 's/^snell-server-v//; s/-linux-$//' | sort -u) || true
    stable=$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$versions") || true
    [[ -z $stable ]] || versions=$stable
    [[ -n $versions ]] || return 1
    # shellcheck disable=SC2086 # one version per word
    version_latest $versions
}
# Under the lock while deploying: the binary of this major version, and the unit.
# The unit starts whatever the current generation links for the node, so switching
# or rolling back a generation also switches the configuration and the version.
snell_install() {
    local major=$1 unit=/etc/systemd/system/srm-snell@.service tmp
    if [[ ! -x $SRM_ROOT/snell/v$major/snell-server ]]; then
        if ! command -v unzip >/dev/null; then
            msg '安装 Snell 需要的 unzip…'
            { apt-get update && DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends unzip; } || return 1
        fi
        install -d -m 755 "$SRM_ROOT/snell" "$SRM_ROOT/snell/v$major" && snell_download "$major" "$SRM_ROOT/snell/v$major/snell-server" || return 1
        if [[ $major == 6 ]]; then printf '%s\n' "$SNELL_V6"; else printf '%s\n' "$SNELL_V5"; fi > "$SRM_ROOT/snell/v$major/version" || return 1
    fi
    tmp=$(mktemp) || return 1
    cat > "$tmp" <<UNIT
[Unit]
Description=srm Snell server of node %i
After=network-online.target
Wants=network-online.target
[Service]
User=srm
Group=srm
ExecStart=$DATA/current/sidecar/%i/snell-server -c $DATA/current/sidecar/%i/snell.conf
Restart=on-failure
RestartSec=3
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
RestrictSUIDSGID=true
CapabilityBoundingSet=
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
UNIT
    if cmp -s "$tmp" "$unit"; then rm -f "$tmp"; return 0; fi
    install -m 644 "$tmp" "$unit" && rm -f "$tmp" && systemctl daemon-reload
}
proto_snell_label() { printf 'Snell + ShadowTLS（Surge）'; }
proto_snell_transport() { printf 'tcp'; }
proto_snell_validate() {
    printf '%s' '(.sni|text) and (.psk|test("^[a-f0-9]{32}$")) and (.shadowtls_password|test("^[a-f0-9]{32}$")) and
      (.local_port|type == "number" and floor == . and . >= 1 and . <= 65535) and
      ((.snell_version == 6 and (.snell_mode == "default" or .snell_mode == "unshaped")) or (.snell_version == 5 and .snell_mode == null))'
}
# sing-box docs: shadowtls inbound (version 3, users, handshake, strict_mode), listen
# field "detour", direct inbound override_address/override_port. The direct inbound
# always opens a listener of its own; it is pinned to loopback.
proto_snell_render_inbound() {
    printf '%s' '[base_inbound + {type:"shadowtls",version:3,users:[{name:.id,password:.shadowtls_password}],
        handshake:{server:.sni,server_port:443},strict_mode:true,detour:(.id+"-snell")},
      {type:"direct",tag:(.id+"-snell"),listen:"127.0.0.1",network:"tcp",override_address:"127.0.0.1",override_port:.local_port}]'
}
# Surge proxy line (manual.nssurge.com/policies/snell.html and tls.html#shadow-tls):
# version must be explicit (Surge assumes v1), mode is v6 only and must match the
# server, reuse applies to v4 and later; ShadowTLS defaults to version 2, so
# shadow-tls-version=3 and shadow-tls-sni are written out.
proto_snell_surge() {
    printf '%s' '"\(surge_head("snell")), psk=\(.psk), version=\(.snell_version)\(if .snell_version == 6 then ", mode=\(.snell_mode)" else "" end), reuse=true, shadow-tls-password=\(.shadowtls_password), shadow-tls-sni=\(.sni), shadow-tls-version=3"'
}
# Snell has no common share link; the Surge line is what its users paste.
proto_snell_share_uri() { proto_snell_surge; }
# sing-box 1.14 snell outbound speaks v4 and v6 (v5 is refused); a v5 server accepts
# v4 clients (kb.nssurge.com release notes). Two outbounds: snell dials through shadowtls.
proto_snell_client_outbound() {
    printf '%s' '[base_outbound + {type:"snell",version:(if .snell_version == 6 then 6 else 4 end),psk:.psk,reuse:true,detour:(.name+"-shadowtls")}
        + (if .snell_version == 6 then {mode:.snell_mode} else {} end),
      {type:"shadowtls",tag:(.name+"-shadowtls"),server:.host,server_port:.port,version:3,password:.shadowtls_password,tls:{enabled:true,server_name:.sni}}]'
}
# mihomo (wiki.metacubex.one/config/proxies/snell): versions 1–5, v5 is sent as v4,
# v6 is rejected (adapter/outbound/snell.go); ShadowTLS goes in obfs-opts, whose
# version defaults to 2.
proto_snell_clash() {
    printf '%s' 'if .snell_version == 5 then clash_base + {type:"snell",psk:.psk,version:5,udp:true,
      "obfs-opts":{mode:"shadow-tls",host:.sni,password:.shadowtls_password,version:3}} else empty end'
}
proto_snell_note() {
    printf '%s' '"Snell 没有通用的分享链接，「原始分享链接」和二维码给的是 Surge 配置行；Snell 流量由 snell-server 直接发出，不经过流媒体分流规则。"
      + (if .snell_version == 6 then "Clash Meta (mihomo) 不支持 Snell v6，要用 Clash Meta 请另部署一个 v5 节点。sing-box 客户端需要 1.14 及以上。"
         else "v5 的 QUIC 代理模式需要 UDP，经 ShadowTLS 只转发 TCP，QUIC 流量会回落到 TCP。" end)'
}
proto_snell_secrets() { printf '%s' '.psk,.shadowtls_password'; }
# Sets proto_version and proto_mode (locals of node_add) and the handshake target.
proto_snell_prompt() {
    [[ -n ${opt_proto_version:-} || ${assume_yes:-0} == 1 ]] ||
        msg 'Snell 版本：1.v6（推荐；Surge iOS 5.20 / Mac 6.7 起支持） 2.v5（客户端还不支持 v6 时选；Clash Meta 只能用 v5）'
    ask_opt "${opt_proto_version:-}" 'Snell 版本' 1 || return 1
    # Menu numbers count only in the menu; the command line takes 6 or 5.
    case ${opt_proto_version:+cli}$REPLY in 1|6|v6|cli6) proto_version=6;; 2|5|v5|cli5) proto_version=5;; *) err 'Snell 版本只能是 6 或 5。'; return 1;; esac
    proto_mode=''
    if [[ $proto_version == 6 ]]; then
        [[ -n ${opt_proto_mode:-} || ${assume_yes:-0} == 1 ]] ||
            msg 'Snell v6 模式（客户端要选同一个）：1.default（流量整形 + 加密，推荐） 2.unshaped（只加密，吞吐约高 10%）'
        ask_opt "${opt_proto_mode:-}" 'Snell 模式' 1 || return 1
        case ${opt_proto_mode:+cli}$REPLY in 1|default|clidefault) proto_mode=default;; 2|unshaped|cliunshaped) proto_mode=unshaped;; *) err 'Snell 模式只能是 default 或 unshaped。'; return 1;; esac
    elif [[ -n ${opt_proto_mode:-} ]]; then err '--proto-mode 只适用于 Snell v6。'; return 1; fi
    msg 'ShadowTLS 借用下面网站的 TLS 1.3 握手：'
    handshake_target_prompt
}
proto_snell_create() {
    local psk password local_port
    reality_target_check "$sni" && snell_install "$proto_version" || return 1
    psk=$(random_hex 16) && password=$(random_hex 16) || return 1
    # snell-server listens on its own loopback port, never the node port ($port of node_add),
    # and below Linux's default ephemeral range (32768–60999): a source port of a live
    # connection could otherwise block snell-server from binding it again on restart.
    local tries
    for ((tries=0; tries<100; tries++)); do
        local_port=$(choose_port) || return 1
        (( local_port < 32768 )) && [[ $local_port != "$port" ]] && break
    done
    (( tries < 100 )) || { err '未找到空闲的本机端口。'; return 1; }
    REPLY=$(jq -nc --argjson v "$proto_version" --arg m "$proto_mode" --arg psk "$psk" --arg pw "$password" --argjson lp "$local_port" \
        '{snell_version:$v} + (if $v == 6 then {snell_mode:$m} else {} end) + {psk:$psk,shadowtls_password:$pw,local_port:$lp}')
}
proto_snell_rotate() {
    local psk password
    psk=$(random_hex 16) && password=$(random_hex 16) || return 1
    REPLY=$(jq -nc --arg psk "$psk" --arg pw "$password" '{psk:$psk,shadowtls_password:$pw}')
}
proto_snell_retarget_label() { printf '切换 ShadowTLS 握手目标（携程 / 西瓜视频）'; }
proto_snell_retarget_select() { reality_target_select; }
proto_snell_retarget() { handshake_retarget "$@"; }
proto_snell_sidecar() { printf '%s' '"srm-snell@\(.id).service"'; }
proto_snell_program_label() { printf 'Snell'; }
proto_snell_program_key() { printf '%s' '"v\(.snell_version)"'; }
proto_snell_program_path() { printf '%s\n' "$SRM_ROOT/snell/$1/snell-server"; }
# Installations before version files existed run the pinned build.
proto_snell_program_current() {
    if [[ -f $SRM_ROOT/snell/$1/version ]]; then cat "$SRM_ROOT/snell/$1/version"
    elif [[ $1 == v6 ]]; then printf '%s\n' "$SNELL_V6"; else printf '%s\n' "$SNELL_V5"; fi
}
proto_snell_program_latest() {
    local tmp key version rc=0
    tmp=$(mktemp) || return 1
    if ! fetch "$SNELL_NOTES" "$tmp"; then rm -f "$tmp"; err '无法读取 Snell 官方发布说明。'; return 1; fi
    for key in "$@"; do
        if version=$(snell_pick "${key#v}" < "$tmp"); then printf '%s\t%s\n' "$key" "$version"
        else err "Snell 发布说明里没有找到 $key 的版本。"; rc=1; fi
    done
    rm -f "$tmp"
    return "$rc"
}
proto_snell_program_fetch() { snell_download "${1#v}" "$3" "$2"; }
# Server configuration as written by `snell-server --wizard` of each version, with
# listen moved to loopback (v6 `--help` lists listen, psk, mode, dns,
# dns-ip-preference, ipv6 (deprecated) and egress-interface; the v5 wizard writes
# listen, psk and ipv6 = false).
proto_snell_sidecar_render() {
    local node=$1 dir=$2 major
    major=$(jq -r .snell_version <<< "$node") || return 1
    [[ -x $SRM_ROOT/snell/v$major/snell-server ]] || { err "缺少 Snell v$major 服务端程序，请删除此节点后重新部署。"; return 1; }
    ln -s "$SRM_ROOT/snell/v$major/snell-server" "$dir/snell-server" &&
    jq -r '"[snell-server]", "listen = 127.0.0.1:\(.local_port)", "psk = \(.psk)",
      if .snell_version == 6 then "mode = \(.snell_mode)", "dns-ip-preference = default" else "ipv6 = false" end' <<< "$node" > "$dir/snell.conf"
}

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
proto_register snell
proto_register shadowsocks
proto_register tuic
proto_register vlesstls
proto_register trojan
proto_register vmess
proto_register naive
proto_register hysteria
