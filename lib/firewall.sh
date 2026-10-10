# UFW application profiles distinguish our rules from existing port allows.
# firewalld entries record only runtime/permanent ports that were absent before.
# iptables (no UFW/firewalld, e.g. Oracle images rejecting all other input) gets
# ACCEPT rules commented "srm" right before the catch-all REJECT/DROP, per family.
firewall_ipt_cmd() { if [[ $1 == ipv4 ]]; then printf 'iptables\n'; else printf 'ip6tables\n'; fi; }
# Prints where an accept rule goes: the index of the first catch-all REJECT/DROP
# in INPUT, or "end" when only the policy drops. Fails when the family blocks nothing.
firewall_ipt_spot() {
    local cmd rules line n=0
    cmd=$(firewall_ipt_cmd "$1")
    command -v "$cmd" >/dev/null || return 1
    rules=$(LC_ALL=C "$cmd" -w 5 -S INPUT 2>/dev/null) || return 1
    while IFS= read -r line; do
        [[ $line == '-A INPUT '* ]] || continue
        n=$((n + 1))
        if [[ $line =~ ^-A\ INPUT(\ -p\ (tcp|udp|all)(\ -m\ (tcp|udp))?)?\ -j\ (REJECT|DROP)($|\ ) ]]; then printf '%s\n' "$n"; return 0; fi
    done <<< "$rules"
    if printf '%s\n' "$rules" | grep -Eq '^-P INPUT (DROP|REJECT)$'; then printf 'end\n'; return 0; fi
    return 1
}
firewall_ipt_rule() { printf '%s\n' -p "$2" -m "$2" --dport "$1" -m comment --comment srm -j ACCEPT; }
# Set when an iptables rule changed, so the caller saves once at the end.
FIREWALL_IPT_CHANGED=0
firewall_ipt_save() {
    (( FIREWALL_IPT_CHANGED )) || return 0
    FIREWALL_IPT_CHANGED=0
    if command -v netfilter-persistent >/dev/null; then
        netfilter-persistent save >/dev/null 2>&1 || err 'iptables 规则已生效，但 netfilter-persistent 保存失败，服务器重启后可能失效。'
    else
        msg 'iptables 规则已生效，但系统没有 netfilter-persistent，服务器重启后会失效；安装 iptables-persistent 时选「是」保存当前规则即可。'
    fi
}
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
    elif firewall_ipt_spot ipv4 >/dev/null || firewall_ipt_spot ipv6 >/dev/null; then printf 'iptables\n'
    else printf 'none\n'; fi
}
firewall_profile() {
    printf '[srm-%s-%s]\ntitle=srm managed port\ndescription=Managed by srm; do not edit\nports=%s/%s\n' "$1" "$2" "$1" "$2"
}
firewall_fields_valid() {
    [[ $1 == ufw || $1 == firewalld || $1 == iptables ]] && [[ $2 =~ ^[a-zA-Z0-9_-]+$ ]] &&
        [[ $1 != iptables || $2 == ipv4 || $2 == ipv6 ]] &&
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
    elif [[ $backend == iptables ]]; then
        local cmd spot rule=()
        cmd=$(firewall_ipt_cmd "$zone")
        while IFS= read -r output; do rule+=("$output"); done < <(firewall_ipt_rule "$port" "$proto")
        rc=0
        output=$(LC_ALL=C "$cmd" -w 5 -C INPUT "${rule[@]}" 2>&1) || rc=$?
        # Recorded only once the query works, so a failing system leaves nothing to clean.
        [[ $rc == 0 || $rc == 1 ]] || { err "无法查询 $cmd $port/${proto}（系统可能缺少 iptables comment 模块，可改用 UFW）：$output"; return 1; }
        printf '%s\t%s\t%s\t%s\t%s\n' "$@" > "$file" || return 1
        [[ $rc == 1 ]] || return 0
        spot=$(firewall_ipt_spot "$zone") || spot=end
        if [[ $spot == end ]]; then "$cmd" -w 5 -A INPUT "${rule[@]}" || return 1
        else "$cmd" -w 5 -I INPUT "$spot" "${rule[@]}" || return 1; fi
        FIREWALL_IPT_CHANGED=1
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
    elif [[ $backend == iptables ]]; then
        local cmd rule=()
        cmd=$(firewall_ipt_cmd "$zone")
        while IFS= read -r output; do rule+=("$output"); done < <(firewall_ipt_rule "$port" "$proto")
        # A family that is gone (IPv6 disabled, iptables removed) holds no rules;
        # exit code 4 (lock timeout, no permission) is temporary, so the record stays.
        rc=0
        command -v "$cmd" >/dev/null && LC_ALL=C "$cmd" -w 5 -S INPUT >/dev/null 2>&1 || rc=$?
        [[ $rc != 4 ]] || { err "$cmd 暂时无法读取，保留记录。"; return 1; }
        if [[ $rc != 0 ]]; then rm -f "$file"; return 0; fi
        # Deletes only rules matching this exact spec, including the srm comment.
        while :; do
            rc=0
            LC_ALL=C "$cmd" -w 5 -C INPUT "${rule[@]}" 2>/dev/null || rc=$?
            [[ $rc == 0 ]] || break
            "$cmd" -w 5 -D INPUT "${rule[@]}" || return 1
            FIREWALL_IPT_CHANGED=1
        done
        [[ $rc == 1 ]] || { err "无法清理 $cmd $port/${proto}，保留记录。"; return 1; }
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
    firewall_ipt_save
    return "$failures"
}
firewall_sync() {
    local state=${1:-} backend ports zones='' families='' family port proto zone scope file key desired failures=0
    owned_root || return 1
    backend=$(firewall_detect) || return 1
    install -d -m 700 "$DATA/firewall" || return 1
    desired=$(mktemp) || return 1
    ports=$(mktemp) || { rm -f "$desired"; return 1; }
    if [[ -n $state && -f $state ]]; then
        jq -r ".nodes[]|select(.enabled)|.port as \$p|($(proto_jq_transports))[]|[\$p,.]|@tsv" "$state" > "$ports" || { rm -f "$ports" "$desired"; return 1; }
    fi
    # A temporary TCP port: certificate validation (80 / 443) or a profile download link.
    if [[ -n ${2:-} ]]; then
        valid_port "$2" || { rm -f "$ports" "$desired"; return 1; }
        printf '%s\ttcp\n' "$2" >> "$ports"
    fi
    # A node may itself use the certificate challenge port.
    sort -u -o "$ports" "$ports" || { rm -f "$ports" "$desired"; return 1; }
    if [[ $backend == firewalld ]]; then
        zones=$(firewall-cmd --get-active-zones) || { rm -f "$ports" "$desired"; return 1; }
        zones=$(printf '%s\n' "$zones" | awk '/^[^[:space:]]/{print $1}')
        [[ -n $zones ]] || zones=$(firewall-cmd --get-default-zone) || { rm -f "$ports" "$desired"; return 1; }
    elif [[ $backend == iptables ]]; then
        for family in ipv4 ipv6; do
            ! firewall_ipt_spot "$family" >/dev/null || families+=" $family"
        done
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
        elif [[ $backend == iptables ]]; then
            for family in $families; do
                printf 'iptables-%s-both-%s-%s\n' "$family" "$port" "$proto" >> "$desired"
                firewall_add iptables "$family" both "$port" "$proto" || { failures=1; break; }
            done
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
    firewall_ipt_save
    if [[ -s $ports ]]; then
        if [[ $backend == none ]]; then msg '未检测到活动的 UFW/firewalld，也没有拦截入站的 iptables 规则，未更改防火墙。若使用自定义 nftables 规则，仍需检查。'
        elif [[ $backend == iptables ]] && (( failures == 0 )); then msg '已在 iptables 拦截规则之前放行节点端口（规则注释 srm）；云安全组和外部连通仍需检查。'
        elif (( failures == 0 )); then msg "已自动配置 $backend 节点端口；云安全组和外部连通仍需检查。"; fi
    fi
    rm -f "$ports" "$desired"
    return "$failures"
}
firewall_renew() (
    local domain=$1 port
    port=$(cert_challenge_port "$domain") || exit 1
    [[ $port == 80 || $port == 443 ]] || { err '证书验证端口记录异常。'; exit 1; }
    trap 'firewall_sync "$STATE" || err "证书临时端口清理失败，请在菜单「4. 运行状态」里选「重新同步防火墙端口规则」重试。"' EXIT
    trap 'exit 130' INT TERM HUP
    firewall_sync "$STATE" "$port" || exit 1
    acme_call "$domain" --renew -d "$domain" --ecc
)
