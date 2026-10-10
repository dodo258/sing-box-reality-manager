# UFW application profiles distinguish our rules from existing port allows.
# firewalld entries record only runtime/permanent ports that were absent before.
firewall_detect() {
    local ufw_active=0 firewalld_active=0 output
    if command -v ufw >/dev/null; then
        output=$(LC_ALL=C ufw status) || { err '无法读取 UFW 状态。'; return 1; }
        [[ $output != 'Status: active'* ]] || ufw_active=1
    fi
    if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then firewalld_active=1; fi
    if (( ufw_active && firewalld_active )); then err 'UFW 与 firewalld 同时运行，请先确认防火墙管理方式。'; return 1; fi
    if (( ufw_active )); then printf 'ufw\n'
    elif (( firewalld_active )); then printf 'firewalld\n'
    else printf 'none\n'; fi
}
firewall_profile() {
    printf '[srm-%s-%s]\ntitle=srm managed port\ndescription=Managed by srm; do not edit\nports=%s/%s\n' "$1" "$2" "$1" "$2"
}
firewall_fields_valid() {
    [[ $1 == ufw || $1 == firewalld ]] && [[ $2 =~ ^[a-zA-Z0-9_-]+$ ]] &&
        [[ $3 == both || $3 == runtime || $3 == permanent ]] &&
        valid_port "$4" && [[ $5 == tcp || $5 == udp ]]
}
firewall_add() {
    local backend=$1 zone=$2 scope=$3 port=$4 proto=$5 file app profile output rc
    firewall_fields_valid "$@" || return 1
    file=$DATA/firewall/$backend-$zone-$scope-$port-$proto
    if [[ $backend == ufw ]]; then
        app=srm-$port-$proto
        profile=/etc/ufw/applications.d/$app
        if [[ -e $profile || -L $profile ]]; then
            [[ ! -L $profile ]] && firewall_profile "$port" "$proto" | cmp -s - "$profile" || { err "UFW 应用文件冲突：$profile"; return 1; }
            [[ -f $file ]] || { err "UFW 应用名已存在：$app"; return 1; }
        else
            # Record intent first so interrupted profile creation can be cleaned.
            printf '%s\t%s\t%s\t%s\t%s\n' "$@" > "$file" || return 1
            firewall_profile "$port" "$proto" > "$profile" || return 1
            chmod 644 "$profile" || return 1
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$@" > "$file" || return 1
        # Prepend only this node's exact application rule; never reset policy.
        LC_ALL=C ufw prepend allow in "$app" comment 'srm managed' || return 1
    else
        local args=(--zone="$zone")
        [[ $scope != permanent ]] || args+=(--permanent)
        rc=0
        output=$(firewall-cmd "${args[@]}" --query-port="$port/$proto" 2>&1) || rc=$?
        if [[ $rc == 0 && $output == yes ]]; then return 0; fi
        [[ $rc == 1 && $output == no ]] || { err "无法查询 firewalld $zone $port/${proto}：$output"; return 1; }
        printf '%s\t%s\t%s\t%s\t%s\n' "$@" > "$file" || return 1
        firewall-cmd "${args[@]}" --add-port="$port/$proto" || return 1
    fi
}
firewall_remove() {
    local file=$1 backend zone scope port proto app profile output rc
    IFS=$'\t' read -r backend zone scope port proto < "$file" || return 1
    firewall_fields_valid "$backend" "$zone" "$scope" "$port" "$proto" || { err '防火墙所有权记录异常。'; return 1; }
    if [[ $backend == ufw ]]; then
        app=srm-$port-$proto
        profile=/etc/ufw/applications.d/$app
        if [[ -e $profile || -L $profile ]]; then
            [[ ! -L $profile ]] && firewall_profile "$port" "$proto" | cmp -s - "$profile" || { err "UFW 应用文件已被修改，保留：$profile"; return 1; }
        else
            # Reconstruct only a missing owned profile; never overwrite edits.
            firewall_profile "$port" "$proto" > "$profile" && chmod 644 "$profile" || return 1
        fi
        output=$(LC_ALL=C ufw show added) || return 1
        if printf '%s\n' "$output" | grep -Fq "$app"; then
            LC_ALL=C ufw --force delete allow in "$app" || return 1
        fi
        output=$(LC_ALL=C ufw show added) || return 1
        if printf '%s\n' "$output" | grep -Fq "$app"; then err "仍有规则引用 ${app}，保留应用文件。"; return 1; fi
        rm -f "$profile" || return 1
    else
        local args=(--zone="$zone")
        [[ $scope != permanent ]] || args+=(--permanent)
        rc=0
        output=$(firewall-cmd "${args[@]}" --query-port="$port/$proto" 2>&1) || rc=$?
        if [[ $rc == 0 && $output == yes ]]; then
            firewall-cmd "${args[@]}" --remove-port="$port/$proto" || return 1
        elif [[ $rc != 1 || $output != no ]]; then err "无法清理 firewalld $zone $port/${proto}，保留记录。"; return 1; fi
    fi
    rm -f "$file"
}
firewall_clear() {
    local file failures=0
    for file in "$DATA"/firewall/*; do
        [[ -f $file ]] || continue
        firewall_remove "$file" || failures=1
    done
    return "$failures"
}
firewall_sync() {
    local state=${1:-} backend ports zones='' port proto zone scope file key desired failures=0
    owned_root || return 1
    backend=$(firewall_detect) || return 1
    install -d -m 700 "$DATA/firewall" || return 1
    desired=$(mktemp) || return 1
    ports=$(mktemp) || { rm -f "$desired"; return 1; }
    if [[ -n $state && -f $state ]]; then
        jq -r ".nodes[]|select(.enabled)|[.port,($(proto_jq_transport))]|@tsv" "$state" > "$ports" || { rm -f "$ports" "$desired"; return 1; }
    fi
    if [[ -n ${2:-} ]]; then
        [[ $2 == 80 || $2 == 443 ]] || { rm -f "$ports" "$desired"; return 1; }
        printf '%s\ttcp\n' "$2" >> "$ports"
    fi
    # A node may itself use the certificate challenge port.
    sort -u -o "$ports" "$ports" || { rm -f "$ports" "$desired"; return 1; }
    if [[ $backend == firewalld ]]; then
        zones=$(firewall-cmd --get-active-zones) || { rm -f "$ports" "$desired"; return 1; }
        zones=$(printf '%s\n' "$zones" | awk '/^[^[:space:]]/{print $1}')
        [[ -n $zones ]] || zones=$(firewall-cmd --get-default-zone) || { rm -f "$ports" "$desired"; return 1; }
    fi
    while IFS=$'\t' read -r port proto; do
        [[ -n $port ]] || continue
        if [[ $backend == ufw ]]; then
            printf 'ufw-global-both-%s-%s\n' "$port" "$proto" >> "$desired"
            firewall_add ufw global both "$port" "$proto" || { failures=1; break; }
        elif [[ $backend == firewalld ]]; then
            while IFS= read -r zone; do
                for scope in runtime permanent; do
                    printf 'firewalld-%s-%s-%s-%s\n' "$zone" "$scope" "$port" "$proto" >> "$desired"
                    firewall_add firewalld "$zone" "$scope" "$port" "$proto" || { failures=1; break 2; }
                done
            done <<< "$zones"
            (( failures == 0 )) || break
        fi
    done < "$ports"
    # Cleanup is deferred if additions fail, so existing nodes retain their rules.
    if (( failures == 0 )); then
        for file in "$DATA"/firewall/*; do
            [[ -f $file ]] || continue
            key=${file##*/}
            grep -Fxq "$key" "$desired" || firewall_remove "$file" || failures=1
        done
    fi
    if [[ -s $ports ]]; then
        if [[ $backend == none ]]; then msg '未检测到活动的 UFW/firewalld，未更改防火墙。若使用自定义 nftables/iptables，仍需检查其规则。'
        elif (( failures == 0 )); then msg "已自动配置 $backend 节点端口；云安全组和外部连通仍需检查。"; fi
    fi
    rm -f "$ports" "$desired"
    return "$failures"
}
firewall_renew() (
    local domain=$1 port=80 account=$SRM_ROOT/acme-accounts/$1
    if [[ -f $account/challenge-port ]]; then
        read -r port < "$account/challenge-port" || exit 1
    elif grep -q "^Le_Webroot='alpn'" "$account/${domain}_ecc/$domain.conf" 2>/dev/null; then port=443; fi
    [[ $port == 80 || $port == 443 ]] || { err '证书验证端口记录异常。'; exit 1; }
    trap 'firewall_sync "$STATE" || err "证书临时端口清理失败，请在菜单「4. 运行状态」里选「重新同步防火墙端口规则」重试。"' EXIT
    trap 'exit 130' INT TERM HUP
    firewall_sync "$STATE" "$port" || exit 1
    acme_call "$domain" --renew -d "$domain" --ecc
)
