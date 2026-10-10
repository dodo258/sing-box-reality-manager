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
    hop_sync || failures=1
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
        hop_sync "$state" || failures=1
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
# Port hopping (protocols with the port_hopping hook, node field hop {start, end}):
# clients rotate among the ports start–end, and UDP sent to them is redirected to the
# node port before the firewall filters it, so only the node port needs an allow rule.
# Only packets addressed to this server are redirected (never traffic it forwards,
# e.g. for containers). Rules carry the comment srm-hop: iptables / ip6tables nat
# PREROUTING when iptables exists (the same backend as the rest of the system),
# otherwise one nftables table inet srm_hop replaced atomically. Neither survives a
# reboot by itself: srm.service runs `srm hop-sync` before every start
# (the Port Hopping page of the official documentation, linked in lib/protocols.sh).
HOP_COMMENT=srm-hop
HOP_TABLE=srm_hop
hop_valid_range() {
    [[ $1 =~ ^[1-9][0-9]{3,4}$ && $2 =~ ^[1-9][0-9]{3,4}$ ]] && (( $1 >= 1024 && $1 < $2 && $2 <= 65535 ))
}
# "START-END" (also "START:END") → "START END"; fails for anything else.
hop_parse() {
    local range=${1//:/-} start end
    [[ $range =~ ^([0-9]+)-([0-9]+)$ ]] || return 1
    start=${BASH_REMATCH[1]} end=${BASH_REMATCH[2]}
    hop_valid_range "$start" "$end" || return 1
    printf '%s %s\n' "$start" "$end"
}
# The range START–END can be redirected for node EXCLUDE (its own range does not
# count) whose port is PORT: no node port, helper port or other range of STATE in
# it, not PORT, and no program listening on UDP in it. Prints the reason when not.
hop_range_free() {
    local start=$1 end=$2 exclude=${3:-} port=${4:-} output
    if [[ $port =~ ^[0-9]+$ ]] && (( start <= port && port <= end )); then
        printf '节点端口 %s 在这段范围里\n' "$port"; return 1
    fi
    if [[ -f $STATE ]]; then
        output=$(jq -r --arg id "$exclude" --argjson s "$start" --argjson e "$end" '
          [.nodes[]|select(.id != $id)|(.port, (.local_port // empty))|select($s <= . and . <= $e)] as $ports |
          [.nodes[]|select(.id != $id and .hop != null)|select(.hop.start <= $e and $s <= .hop.end)|.name] as $hops |
          if ($ports|length) > 0 then "已有节点使用端口 \($ports[0])"
          elif ($hops|length) > 0 then "和节点「\($hops[0])」的端口跳跃范围重叠" else empty end' "$STATE") || return 1
        [[ -z $output ]] || { printf '%s\n' "$output"; return 1; }
    fi
    output=$(ss -H -lun "sport >= :$start and sport <= :$end" 2>/dev/null) || output=''
    [[ -z $output ]] || { printf '有程序在这段范围里监听 UDP（%s）\n' "$(awk '{print $4}' <<< "$output" | head -n 1)"; return 1; }
}
# The default range: the first free block of 1000 ports from 20000 (below Linux's
# ephemeral ports 32768–60999); prints "START END".
hop_default() {
    local start
    for ((start=20000; start<=31000; start+=1000)); do
        hop_range_free "$start" "$((start + 999))" "${1:-}" "${2:-}" >/dev/null && { printf '%s %s\n' "$start" "$((start + 999))"; return 0; }
    done
    err '20000–31999 里没有空闲的 1000 个连续端口，请自己填端口范围。'; return 1
}
# Installs nftables when the system has neither iptables nor nft.
hop_tools_ready() {
    [[ -z $(hop_backend) ]] || return 0
    msg '端口跳跃需要 nftables，正在安装…'
    apt-get update && DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends nftables || return 1
    command -v nft >/dev/null
}
hop_ipt_spec() { printf '%s\n' -p udp -m addrtype --dst-type LOCAL -m udp --dport "$1:$2" -m comment --comment "$HOP_COMMENT" -j REDIRECT --to-ports "$3"; }
# Brings CMD's srm-hop rules to the "START END PORT" lines of DESIRED; nothing changes
# when they already match.
hop_ipt_apply() {
    local cmd=$1 desired=$2 current line start end port spec=() word
    current=$(LC_ALL=C "$cmd" -w 5 -t nat -S PREROUTING) || return 1
    current=$(grep -F -- "--comment $HOP_COMMENT " <<< "$current" || true)
    [[ $(sed -nE 's/.*--dport ([0-9]+):([0-9]+) .*--to-ports ([0-9]+).*/\1 \2 \3/p' <<< "$current" | sort) != "$(sort <<< "$desired")" ]] || return 0
    while IFS= read -r line; do
        [[ $line == '-A PREROUTING '* ]] || continue
        # The comment has no spaces, so the listed rule splits into its arguments.
        read -ra spec <<< "${line#-A PREROUTING }"
        "$cmd" -w 5 -t nat -D PREROUTING "${spec[@]}" || return 1
    done <<< "$current"
    while read -r start end port; do
        [[ -n $start ]] || continue
        spec=()
        while IFS= read -r word; do spec+=("$word"); done < <(hop_ipt_spec "$start" "$end" "$port")
        "$cmd" -w 5 -t nat -A PREROUTING "${spec[@]}" || return 1
    done <<< "$desired"
    # Saved with the other iptables rules only where they are saved anyway; the
    # service start restores them otherwise.
    if command -v netfilter-persistent >/dev/null; then FIREWALL_IPT_CHANGED=1; fi
}
hop_nft_apply() {
    local desired=$1 start end port rules=''
    if [[ -z $desired ]]; then
        nft list table inet "$HOP_TABLE" >/dev/null 2>&1 || return 0
        nft delete table inet "$HOP_TABLE"; return
    fi
    while read -r start end port; do
        rules+="    fib daddr type local udp dport $start-$end counter redirect to :$port comment \"$HOP_COMMENT\""$'\n'
    done <<< "$desired"
    # Created, deleted and created again in one transaction: old rules never mix in.
    nft -f - <<NFT
add table inet $HOP_TABLE
delete table inet $HOP_TABLE
table inet $HOP_TABLE {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
$rules  }
}
NFT
}
hop_backend() {
    if command -v iptables >/dev/null; then printf 'iptables\n'
    elif command -v nft >/dev/null; then printf 'nft\n'; fi
}
# Redirect rules for STATE's enabled nodes; without STATE every srm-hop rule goes.
# Systems that never had port hopping are not touched (no record). IPv6 is best
# effort: a failure there is reported and does not fail the sync.
# The service start (hop-sync) runs without srm's lock, maybe inside a locked
# transaction restarting the service, so the rules have a lock of their own, taken
# only around the change (no subshell: FIREWALL_IPT_CHANGED must reach the caller).
HOP_LOCK=/run/lock/srm-hop.lock
hop_sync() {
    local rc=0 wanted=0
    # Nothing to add and nothing recorded: done without the lock.
    if [[ ! -f $DATA/port-hopping ]]; then
        if [[ -n ${1:-} && -f $1 ]]; then wanted=$(jq '[.nodes[]|select(.enabled and .hop != null)]|length' "$1") || return 1; fi
        [[ $wanted != 0 ]] || return 0
    fi
    if [[ -d ${HOP_LOCK%/*} ]] && command -v flock >/dev/null; then
        exec 8>"$HOP_LOCK" || return 1
        flock -w 30 8 || { exec 8>&-; err '端口跳跃规则正被另一个操作修改，稍后重试。'; return 1; }
        hop_sync_locked "$@" || rc=$?
        exec 8>&-
        return "$rc"
    fi
    hop_sync_locked "$@"
}
hop_sync_locked() {
    local state=${1:-} desired='' backend='' previous=''
    if [[ -n $state && -f $state ]]; then
        desired=$(jq -r '.nodes[]|select(.enabled and .hop != null)|"\(.hop.start) \(.hop.end) \(.port)"' "$state") || return 1
    fi
    [[ -n $desired || -f $DATA/port-hopping ]] || return 0
    backend=$(hop_backend)
    [[ -n $backend || -z $desired ]] || { err '端口跳跃需要 iptables 或 nftables，系统里都没有。'; return 1; }
    [[ ! -f $DATA/port-hopping ]] || previous=$(head -n 1 "$DATA/port-hopping")
    # Rules left by the other backend (iptables installed or removed since) go first.
    if [[ -n $previous && $previous != "$backend" ]]; then
        # A backend that is gone took its runtime rules with it.
        case $previous in
          iptables)
            if command -v iptables >/dev/null; then hop_ipt_apply iptables '' || return 1; fi
            if command -v ip6tables >/dev/null; then hop_ipt_apply ip6tables '' 2>/dev/null || true; fi;;
          nft) hop_nft_apply '' || return 1;;
        esac
    fi
    case $backend in
      iptables)
        hop_ipt_apply iptables "$desired" || { err '端口跳跃的 iptables 转发规则没有改成功。'; return 1; }
        if command -v ip6tables >/dev/null && ! hop_ipt_apply ip6tables "$desired" 2>/dev/null && [[ -n $desired ]]; then
            msg '提示：IPv6 的端口跳跃转发没有加上（系统可能不支持 ip6tables nat），IPv4 不受影响。'
        fi;;
      nft) hop_nft_apply "$desired" || { err '端口跳跃的 nftables 转发规则没有改成功。'; return 1; };;
    esac
    if [[ -n $desired ]]; then printf '%s\n%s\n' "$backend" "$desired" > "$DATA/port-hopping" || return 1
    else rm -f "$DATA/port-hopping"; fi
}
