# Nodes using a domain certificate (Let's Encrypt or imported); self-signed nodes
# keep their own ten-year certificate, pinned by clients, and are never renewed.
CERT_NODES='.cert_dir != null and .cert_sha256 == null'
ensure_acme() {
    [[ -x $ACME ]] && return 0
    local tmp
    tmp=$(mktemp -d) || return 1
    if ! fetch https://codeload.github.com/acmesh-official/acme.sh/tar.gz/refs/tags/3.1.5 "$tmp/acme.tar.gz" ||
       [[ $(sha256 "$tmp/acme.tar.gz") != a5e5b61bf98464fd7bf9925951b97e9ed8c127e041d3b8e9703d2360cd6e19b6 ]] ||
       ! tar -xzf "$tmp/acme.tar.gz" -C "$tmp"; then rm -rf "$tmp"; err 'ACME 下载或校验失败。'; return 1; fi
    install -d -m 700 "$SRM_ROOT/acme" "$SRM_ROOT/acme-accounts" || return 1
    cp -R "$tmp/acme.sh-3.1.5/." "$SRM_ROOT/acme/" && chmod 700 "$ACME"
    local rc=$?
    rm -rf "$tmp"
    return "$rc"
}
cert_valid() {
    local cert=$1 key=$2 domain=$3 a b
    openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 &&
        openssl verify -partial_chain -trusted "$cert" -verify_hostname "$domain" "$cert" >/dev/null 2>&1 || return 1
    a=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null) || return 1
    b=$(openssl pkey -in "$key" -pubout 2>/dev/null) || return 1
    [[ -n $a && $a == "$b" ]]
}
activate_cert() {
    local domain=$1 source=$2 origin=${3:-import} dir gen old='' active=0
    case $origin in acme|import) ;; *) return 1;; esac
    valid_domain "$domain" && cert_valid "$source/fullchain.pem" "$source/key.pem" "$domain" || { err '证书校验失败。'; return 1; }
    dir=$DATA/certs/$domain
    install -d -m 750 -o root -g srm "$dir" || return 1
    if [[ -f $dir/active/fullchain.pem && -f $dir/active/renewal-source ]] &&
       [[ $(cat "$dir/active/renewal-source") == "$origin" ]] &&
       cmp -s "$source/fullchain.pem" "$dir/active/fullchain.pem"; then return 0; fi
    gen=$(mktemp -d "$dir/c.XXXXXXXX") || return 1
    chmod 750 "$gen" && chgrp srm "$gen" &&
        install -m 640 -g srm "$source/fullchain.pem" "$gen/fullchain.pem" &&
        install -m 640 -g srm "$source/key.pem" "$gen/key.pem" &&
        printf '%s\n' "$origin" > "$gen/renewal-source" && chmod 600 "$gen/renewal-source" || return 1
    [[ ! -L $dir/active ]] || old=$(readlink "$dir/active")
    ln -s "$gen" "$dir/.next" && mv -Tf "$dir/.next" "$dir/active" || return 1
    systemctl is-active --quiet "$SERVICE" && active=1
    if [[ ! -f $STATE ]] || { "$CORE" check -c "$DATA/current/config.json" && { [[ $active == 0 ]] || { restart_unit "$SERVICE" && service_healthy "$STATE"; }; }; }; then return 0; fi
    if [[ -n $old ]]; then
        ln -s "$old" "$dir/.next" && mv -Tf "$dir/.next" "$dir/active"
        [[ $active == 0 ]] || restart_unit "$SERVICE"
    else rm -f "$dir/active"; fi
    err '证书应用失败，已恢复原证书。'; return 1
}
acme_call() {
    local domain=$1; shift
    "$ACME" --home "$SRM_ROOT/acme" --config-home "$SRM_ROOT/acme-accounts/$domain" "$@"
}
copy_acme_cert() {
    local domain=$1 tmp rc=0
    tmp=$SRM_ROOT/acme-accounts/$domain/export
    install -d -m 700 "$tmp" || return 1
    acme_call "$domain" --install-cert -d "$domain" --ecc --key-file "$tmp/key.pem" --fullchain-file "$tmp/fullchain.pem" > "$SRM_ROOT/acme-accounts/$domain/install.log" 2>&1 &&
        activate_cert "$domain" "$tmp" acme || rc=1
    return "$rc"
}
issue_certificate() (
    local domain=$1 mode=$2 email=${3:-} webroot=${4:-} rc=0 probe
    valid_domain "$domain" || exit 1
    if [[ -f $DATA/certs/$domain/active/fullchain.pem ]] && cert_valid "$DATA/certs/$domain/active/fullchain.pem" "$DATA/certs/$domain/active/key.pem" "$domain"; then
        msg '复用有效证书。'; exit 0
    fi
    if [[ $mode == auto ]]; then
        mode=$(cert_auto_mode) || { err '80 和 443 已被占用（或留给正在部署的节点），请选择现有网站目录验证。'; exit 1; }
        msg "自动选择证书验证方式：$mode"
    fi
    local challenge_port=80
    case $mode in alpn) challenge_port=443;; http|webroot) ;; *) err '未知证书验证方式。'; exit 1;; esac
    trap 'firewall_sync "$STATE" || err "证书临时端口清理失败，请在菜单「4. 运行状态」里选「重新同步防火墙端口规则」重试。"' EXIT
    trap 'exit 130' INT TERM HUP
    firewall_sync "$STATE" "$challenge_port" || exit 1
    if [[ $mode == alpn ]]; then
        [[ -z $(ss -H -ltn 'sport = :443') ]] || { err '443 端口被占用，原服务未改动。'; exit 1; }
    elif [[ $mode == http ]]; then
        [[ -z $(ss -H -ltn 'sport = :80') ]] || { err '80 端口已占用，请使用现有网站目录验证，不会停止已有服务。'; exit 1; }
    elif [[ $mode == webroot ]]; then
        [[ $webroot == /* && -d $webroot ]] || { err '网站目录必须是存在的绝对路径。'; exit 1; }
        probe=$(random_hex 16) || exit 1
        [[ -d $webroot/.well-known ]] || mkdir -m 755 "$webroot/.well-known" || exit 1
        [[ -d $webroot/.well-known/acme-challenge ]] || mkdir -m 755 "$webroot/.well-known/acme-challenge" || exit 1
        # Validation tokens are public; other web files are never changed.
        # Existing directory permissions remain unchanged.
        printf '%s' "$probe" > "$webroot/.well-known/acme-challenge/srm-$probe" || exit 1
        chmod 644 "$webroot/.well-known/acme-challenge/srm-$probe"
        local response
        response=$(curl -fsSL --connect-timeout 10 --max-time 20 "http://$domain/.well-known/acme-challenge/srm-$probe") || rc=1
        rm -f "$webroot/.well-known/acme-challenge/srm-$probe"
        [[ $rc == 0 && $response == "$probe" ]] || { err '验证文件外网访问检查失败。没有修改网站配置，请检查域名解析/网站目录。'; exit 1; }
    else err '未知证书验证方式。'; exit 1; fi
    ensure_acme || exit 1
    install -d -m 700 "$SRM_ROOT/acme-accounts/$domain" || exit 1
    printf '%s\n' "$challenge_port" > "$SRM_ROOT/acme-accounts/$domain/challenge-port" || exit 1
    if [[ $mode == http || $mode == alpn ]]; then
        command -v socat >/dev/null || DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends socat || exit 1
        local challenge=--standalone
        [[ $mode != alpn ]] || challenge=--alpn
        acme_call "$domain" --issue "$challenge" -d "$domain" --keylength ec-256 --server letsencrypt --accountemail "$email" > "$SRM_ROOT/acme-accounts/$domain/issue.log" 2>&1 || rc=$?
    else
        acme_call "$domain" --issue --webroot "$webroot" -d "$domain" --keylength ec-256 --server letsencrypt --accountemail "$email" > "$SRM_ROOT/acme-accounts/$domain/issue.log" 2>&1 || rc=$?
    fi
    if [[ $rc != 0 && $rc != 2 ]]; then err "证书申请失败。日志：$SRM_ROOT/acme-accounts/$domain/issue.log（分享前请检查敏感信息）。"; exit 1; fi
    copy_acme_cert "$domain" && install_renew_timer
)
# Automatic validation listens on 80 (http) or 443 (alpn). A port is not free if
# anything listens on it, a TCP node owns it (even a stopped one), or it is
# cert_avoid_port, set by node_add for the TCP node being deployed.
cert_auto_mode() {
    local taken=" ${cert_avoid_port:-} "
    if [[ -f $STATE ]]; then
        taken+=$(jq -r "[.nodes[]|select(any(($(proto_jq_transports))[]; . == \"tcp\"))|.port|tostring]|join(\" \")" "$STATE") || return 1
        taken+=' '
    fi
    if [[ $taken != *' 80 '* && -z $(ss -H -ltn 'sport = :80') ]]; then printf 'http\n'
    elif [[ $taken != *' 443 '* && -z $(ss -H -ltn 'sport = :443') ]]; then printf 'alpn\n'
    else return 1; fi
}
# TCP port that renewing DOMAIN needs: the recorded one, else what acme.sh saved.
cert_challenge_port() {
    local domain=$1 port=80 account=$SRM_ROOT/acme-accounts/$1
    if [[ -f $account/challenge-port ]]; then
        read -r port < "$account/challenge-port" || return 1
    elif grep -q "^Le_Webroot='alpn'" "$account/${domain}_ecc/$domain.conf" 2>/dev/null; then port=443; fi
    printf '%s\n' "$port"
}
# A TCP node must not take the port a renewed certificate validates on, or every
# renewal fails until the certificate expires. Checks the certificates of current
# nodes plus an optional DOMAIN about to be used.
cert_port_ok() {
    local port=$1 transport=$2 domain
    [[ " $transport " == *" tcp "* ]] || return 0
    while IFS= read -r domain; do
        [[ -n $domain && $(certificate_source "$domain") == acme ]] || continue
        if [[ $(cert_challenge_port "$domain") == "$port" ]]; then
            err "TCP $port 要留给证书 $domain 自动续期验证，节点不能占用；请换一个端口。"; return 1
        fi
    done < <({ [[ ! -f $STATE ]] || jq -r ".nodes[]|select($CERT_NODES)|.sni" "$STATE"; printf '%s\n' "${3:-}"; } | sort -u)
}
install_renew_timer() {
    cat > /etc/systemd/system/srm-renew.service <<UNIT
[Unit]
Description=srm certificate renewal
[Service]
Type=oneshot
UMask=0077
ExecStart=/usr/local/sbin/srm renew
UNIT
    cat > /etc/systemd/system/srm-renew.timer <<'UNIT'
[Unit]
Description=srm daily certificate check
[Timer]
OnCalendar=daily
RandomizedDelaySec=3600
Persistent=true
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload && systemctl enable --now srm-renew.timer
}
renew_certificates() {
    owned_root || return 1
    [[ -f $STATE ]] || return 0
    local domain rc failures=0
    while IFS= read -r domain; do
        [[ $(certificate_source "$domain") == acme ]] || continue
        # Record a verified legacy association before acme.sh replaces its export.
        # Otherwise a failed activation makes the still-active old cert look imported.
        if ! certificate_preserve_source "$domain"; then failures=$((failures+1)); continue; fi
        rc=0
        firewall_renew "$domain" > "$SRM_ROOT/acme-accounts/$domain/renew.log" 2>&1 || rc=$?
        if [[ $rc == 0 || $rc == 2 ]]; then
            if ! copy_acme_cert "$domain"; then
                err "新证书未能应用：${domain}；保留当前证书，下次续期检查会重试应用。"
                failures=$((failures+1))
            fi
        else err "证书续期失败：${domain}；保留原证书。日志：$SRM_ROOT/acme-accounts/$domain/renew.log"; failures=$((failures+1)); fi
    done < <(jq -r ".nodes[]|select($CERT_NODES)|.sni" "$STATE" | sort -u)
    [[ $failures == 0 ]]
}
certificate_preserve_source() {
    local domain=$1 active=$DATA/certs/$1/active tmp
    [[ ! -f $active/renewal-source ]] || return 0
    [[ $(certificate_source "$domain") == acme ]] || return 1
    tmp=$(mktemp "$active/.renewal-source.XXXXXXXX") || return 1
    if printf 'acme\n' > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$active/renewal-source"; then return 0; fi
    rm -f "$tmp"; return 1
}
certificate_source() {
    local domain=$1 active=$DATA/certs/$1/active account=$SRM_ROOT/acme-accounts/$1 value
    if [[ -f $active/renewal-source ]]; then
        value=$(cat "$active/renewal-source") || return 1
        case $value in acme|import) printf '%s\n' "$value";; *) printf 'unknown\n';; esac
    elif [[ -f $account/${domain}_ecc/$domain.conf && -f $account/export/fullchain.pem ]] &&
         cmp -s "$account/export/fullchain.pem" "$active/fullchain.pem"; then
        # Legacy releases had no origin marker. An account directory alone is not proof.
        printf 'acme\n'
    else printf 'import\n'; fi
}
certificate_status() {
    local domain cert count source health expiry issuer enabled running
    msg $'\n证书管理（只显示本脚本节点使用的证书）\nReality 无需自行申请证书；使用 TLS 证书的节点在这里查看到期时间和续期状态。'
    if [[ -f $STATE ]]; then
        count=$(jq '[.nodes[]|select(.cert_sha256 != null)]|length' "$STATE") || return 1
        [[ $count == 0 ]] || msg "另有 $count 个节点使用自签证书：有效期十年，客户端按证书指纹校验，不需要续期。"
    fi
    if [[ ! -f $STATE ]] || ! jq -e "any(.nodes[]; $CERT_NODES)" "$STATE" >/dev/null; then
        msg '目前没有使用 TLS 证书的节点。'; return 0
    fi
    enabled=$(systemctl is-enabled srm-renew.timer 2>/dev/null) || enabled='未启用'
    running=$(systemctl is-active srm-renew.timer 2>/dev/null) || running='未运行'
    printf '自动续期定时任务：%s / %s（每日检查，仅管理本脚本签发的证书）\n' "$enabled" "$running"
    systemctl list-timers --all srm-renew.timer --no-pager 2>/dev/null || true
    while IFS= read -r domain; do
        cert=$DATA/certs/$domain/active/fullchain.pem
        count=$(jq --arg d "$domain" "[.nodes[]|select($CERT_NODES and .sni==\$d)]|length" "$STATE") || return 1
        source=$(certificate_source "$domain") || return 1
        case $source in
          acme) source="Let's Encrypt 自动续期";;
          import) source='外部导入：由原工具续期后重新导入';;
          *) source='来源标记异常：暂不自动续期';;
        esac
        printf '\n域名：%s（%s 个节点共用）\n来源：%s\n' "$domain" "$count" "$source"
        if ! expiry=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null); then
            msg '状态：证书缺失或无法读取'; continue
        fi
        issuer=$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null) || issuer='issuer=未知'
        if ! openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then health='已到期'
        elif ! openssl x509 -in "$cert" -noout -checkend 2592000 >/dev/null 2>&1; then health='30 天内到期'
        else health='有效'; fi
        printf '到期时间：%s\n签发者：%s\n状态：%s\n' "${expiry#notAfter=}" "${issuer#issuer=}" "$health"
    done < <(jq -r ".nodes[]|select($CERT_NODES)|.sni" "$STATE" | sort -u)
}
certificate_renew_now() {
    msg '检查本脚本签发的证书：达到续期条件时才申请，未到期不会强制重签。'
    renew_certificates || return 1
    msg '检查完成；外部导入证书不参与自动续期。'
    certificate_status
}
certificate_menu() {
    while :; do
        certificate_status || return 1
        [[ -f $STATE ]] || return 0
        msg $'\n1. 刷新证书状态\n2. 立即检查续期（成功更换证书后可能短暂重启本脚本节点）\n0. 返回'
        ask '操作' || return 0
        case $REPLY in
          1) ;;
          2) with_lock certificate_renew_now || return 1;;
          *) err '无效选项。';;
        esac
    done
}
