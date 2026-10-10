# Whole client configurations (profiles) that apps import as they are, and a temporary
# download link for them; v4 keeps no subscription service running. Node entries come
# from the registry hooks (client_outbound, clash, surge); clients that do not support
# a node's protocol leave it out.
#   clash     Clash Verge / Clash Meta for Android (mihomo), YAML
#   sing-box  the official sing-box apps (SFI / SFA / SFM), JSON
#   surge     Surge, profile text
# Basic routing in all three: private addresses, mainland China domains and IPs direct,
# everything else through the group 「节点选择」.
PROFILE_CLIENTS='clash sing-box surge'
PROFILE_GROUP=节点选择
profile_client_label() {
    case $1 in
      clash) printf 'Clash Verge / Clash Meta for Android（mihomo）';;
      sing-box) printf 'sing-box 官方 App（iOS / Android / macOS）';;
      surge) printf 'Surge';;
      *) return 1;;
    esac
}
profile_file() { case $1 in clash) printf 'srm.yaml';; sing-box) printf 'srm.json';; surge) printf 'srm.conf';; *) return 1;; esac; }
profile_content_type() {
    case $1 in clash) printf 'text/yaml; charset=utf-8';; sing-box) printf 'application/json';; *) printf 'text/plain; charset=utf-8';; esac
}
# Enabled nodes of STATE as a JSON array, all of them or the one with ID; names made
# unique (and different from group and built-in policy names) by adding " (2)", " (3)"…
profile_nodes() {
    local state=$1 id=${2:-} nodes
    [[ -f $state ]] || { err '尚无节点，请先部署。'; return 1; }
    if [[ -n $id ]]; then
        node_json "$state" "$id" >/dev/null || { err '节点不存在。'; return 1; }
        jq -e --arg id "$id" 'any(.nodes[]; .id == $id and .enabled)' "$state" >/dev/null || { err '这个节点已停用，先在节点管理里启用。'; return 1; }
    fi
    nodes=$(jq -c --arg id "$id" --arg group "$PROFILE_GROUP" '
      [.nodes[]|select(.enabled and ($id == "" or .id == $id))] |
      # Compared without case: built-in policies of mihomo, Surge and sing-box.
      reduce .[] as $n ({out:[],seen:["direct","reject","reject-drop","reject-tinygif","reject-no-drop","pass","compatible","global",$group]};
        .seen as $s |
        ([range(1; 1000)|(if . == 1 then $n.name else "\($n.name) (\(.))" end) as $c|select(any($s[]; . == ($c|ascii_downcase))|not)|$c][0]) as $name |
        .out += [$n + {name:$name}] | .seen += [$name|ascii_downcase]) | .out' "$state") || return 1
    [[ $(jq length <<< "$nodes") -gt 0 ]] || { err '没有启用的节点。'; return 1; }
    printf '%s\n' "$nodes"
}
# Names of the nodes in NODES (JSON array) that CLIENT leaves out, one per line.
profile_skipped() {
    local client=$1 nodes=$2
    case $client in
      clash|surge) jq -r "$PROTO_JQ_DEFS .[]|select([$(proto_jq "$client" empty)]|length == 0)|.name" <<< "$nodes";;
    esac
}
# profile_render CLIENT STATE [ID]: the whole configuration on stdout; nodes the client
# cannot use are listed on stderr. Fails when none is left.
profile_render() {
    local client=$1 nodes skipped
    profile_client_label "$client" >/dev/null || { err "客户端只能是：$PROFILE_CLIENTS"; return 1; }
    nodes=$(profile_nodes "$2" "${3:-}") || return 1
    skipped=$(profile_skipped "$client" "$nodes") || return 1
    if [[ -n $skipped ]]; then
        [[ $(wc -l <<< "$skipped") -lt $(jq length <<< "$nodes") ]] ||
            { err "所选节点的协议 $(profile_client_label "$client") 都不支持，换一个 App 或节点。"; return 1; }
        msg "$(profile_client_label "$client") 不支持这些节点的协议，没有放进配置：$(awk 'NR > 1 {printf "、"} {printf "%s", $0}' <<< "$skipped")" >&2
    fi
    "profile_render_${client//-/_}" <<< "$nodes"
}
# mihomo (wiki.metacubex.one/config/): proxies and the group in YAML flow style (JSON is
# valid YAML), fake-ip DNS with mainland DoH servers; GEOSITE / GEOIP use the geo data
# the apps ship with.
profile_render_clash() {
    jq -r --arg group "$PROFILE_GROUP" "$PROTO_JQ_DEFS"'
      [.[]|('"$(proto_jq clash empty)"')] as $proxies |
      "# srm 生成的完整配置：\($proxies|length) 个节点；局域网和国内网站直连，其余走「\($group)」",
      "mixed-port: 7890", "allow-lan: false", "mode: rule", "log-level: info",
      "dns:", "  enable: true", "  enhanced-mode: fake-ip", "  fake-ip-range: 198.18.0.1/16",
      "  fake-ip-filter: [\"+.lan\", \"+.local\"]",
      "  default-nameserver: [223.5.5.5, 119.29.29.29]",
      "  nameserver: [\"https://dns.alidns.com/dns-query\", \"https://doh.pub/dns-query\"]",
      "  proxy-server-nameserver: [\"https://dns.alidns.com/dns-query\", \"https://doh.pub/dns-query\"]",
      "proxies:", ($proxies[]|"  - \(tojson)"),
      "proxy-groups:", "  - \({name:$group,type:"select",proxies:([$proxies[].name] + ["DIRECT"])}|tojson)",
      "rules:",
      (["DOMAIN-SUFFIX,lan,DIRECT","DOMAIN-SUFFIX,local,DIRECT",
        "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve","IP-CIDR,10.0.0.0/8,DIRECT,no-resolve","IP-CIDR,172.16.0.0/12,DIRECT,no-resolve",
        "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve","IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
        "IP-CIDR6,fc00::/7,DIRECT,no-resolve","IP-CIDR6,fe80::/10,DIRECT,no-resolve",
        "GEOSITE,cn,DIRECT","GEOIP,CN,DIRECT","MATCH,\($group)"][]|"  - \(tojson)")'
}
# sing-box client (sing-box.sagernet.org/configuration/): the tun inbound the apps run
# on, DoH for mainland domains direct and for the rest through the group, and the
# official geosite-cn / geoip-cn rule sets, downloaded through the group and cached.
profile_render_sing_box() {
    jq --arg group "$PROFILE_GROUP" "$PROTO_JQ_DEFS"'
      def rule_set($tag; $repo): {type:"remote",tag:$tag,format:"binary",
        url:"https://raw.githubusercontent.com/SagerNet/\($repo)/rule-set/\($tag).srs",download_detour:$group};
      # A node may need helper outbounds after its own (one dialing through another).
      [.[]|('"$(proto_jq client_outbound 'error("不支持的协议：\(.type)")')"')|if type == "array" then . else [.] end] as $nodes |
      # A helper named like another node gets " (2)"; its node dials the new name.
      [$nodes[][0].tag] as $mains |
      [$nodes[]|. as $o|reduce ([$o[1:][].tag|select(. as $t|any($mains[]; . == $t))][]) as $t ($o;
        [range(0; length) as $i|.[$i]|(if $i > 0 and .tag == $t then .tag = "\($t) (2)" else . end)
          |(if .detour == $t then .detour = "\($t) (2)" else . end)])] as $outs |
      {
        log: {level:"warn",timestamp:true},
        dns: {
          servers: [{type:"https",tag:"remote",server:"1.1.1.1",detour:$group},{type:"https",tag:"local",server:"223.5.5.5"}],
          rules: [{rule_set:"geosite-cn",action:"route",server:"local"}],
          final: "remote"
        },
        inbounds: [{type:"tun",tag:"tun-in",address:["172.19.0.1/30","fdfe:dcba:9876::1/126"],auto_route:true,strict_route:true}],
        outbounds: ([{type:"selector",tag:$group,outbounds:[$outs[][0].tag]}] + [$outs[][]] + [{type:"direct",tag:"direct"}]),
        route: {
          rules: [{action:"sniff"},{protocol:"dns",action:"hijack-dns"},{ip_is_private:true,outbound:"direct"},
            {rule_set:["geosite-cn","geoip-cn"],outbound:"direct"}],
          rule_set: [rule_set("geosite-cn"; "sing-geosite"), rule_set("geoip-cn"; "sing-geoip")],
          final: $group, auto_detect_interface: true, default_domain_resolver: "local"
        },
        experimental: {cache_file:{enabled:true}}
      }'
}
# Surge (manual.nssurge.com: profile/format, profile/general, policy-groups/select,
# rules/ruleset for the built-in LAN set, rules/final). Group members are the names
# as the proxy lines write them.
profile_render_surge() {
    jq -r --arg group "$PROFILE_GROUP" "$PROTO_JQ_DEFS"'
      [.[]|('"$(proto_jq surge empty)"')] as $lines |
      "# srm 生成的完整配置：\($lines|length) 个节点；局域网和国内网站直连，其余走「\($group)」",
      "[General]", "loglevel = notify", "dns-server = 223.5.5.5, 119.29.29.29",
      "skip-proxy = 127.0.0.1, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 100.64.0.0/10, localhost, *.local",
      "", "[Proxy]", $lines[],
      "", "[Proxy Group]", "\($group) = select, \([$lines[]|capture("^(?<n>.*?) = ").n]|join(", ")), DIRECT",
      "", "[Rule]", "RULE-SET,LAN,DIRECT", "DOMAIN-SUFFIX,cn,DIRECT", "GEOIP,CN,DIRECT", "FINAL,\($group),dns-failed"'
}
# One-tap import of a profile URL, each in the app's own documented or implemented form:
#   sing-box  sing-box://import-remote-profile?url=<URL>#<name>
#             (sing-box.sagernet.org/clients/general/, libbox remote_profile.go)
#   clash     clash://install-config?name=<name>&url=<URL>: no documentation page; the
#             official clients implement it: Clash Verge Rev src-tauri/src/utils/resolve/
#             scheme.rs (takes everything after "url=" as the URL, so name goes first) and
#             Clash Meta for Android AndroidManifest.xml / ExternalControlActivity.kt
#   surge     surge:///install-config?url=<URL> (manual.nssurge.com/tools/url-scheme.html)
# URL and name are percent-encoded.
profile_import_link() {
    local client=$1 url name
    url=$(jq -rn --arg v "$2" '$v|@uri') && name=$(jq -rn --arg v "$3" '$v|@uri') || return 1
    case $client in
      sing-box) printf 'sing-box://import-remote-profile?url=%s#%s\n' "$url" "$name";;
      clash) printf 'clash://install-config?name=%s&url=%s\n' "$name" "$url";;
      surge) printf 'surge:///install-config?url=%s\n' "$url";;
      *) return 1;;
    esac
}
profile_import_hint() {
    case $1 in
      clash) msg 'Clash Verge（电脑）：复制下面的下载地址，在「订阅」页粘贴后点「导入」。Clash Meta for Android：扫码或点开一键导入链接。';;
      sing-box) msg 'sing-box App：手机扫码或点开一键导入链接，确认后创建配置；也可以在 App 里新建远程配置，粘贴下面的下载地址。';;
      surge) msg 'Surge：手机扫码或点开一键导入链接，按提示安装配置；也可以在 Surge 里从 URL 下载配置，粘贴下面的下载地址。';;
    esac
}
# Domain and directory of a CA-issued certificate on this server (not self-signed,
# valid for another day) whose domain points at HOST: the link can then use HTTPS.
profile_tls_domain() {
    local host=$1 domain dir
    while IFS=$'\t' read -r domain dir; do
        [[ -f $dir/fullchain.pem && -f $dir/key.pem ]] || continue
        openssl x509 -checkend 86400 -noout -in "$dir/fullchain.pem" >/dev/null 2>&1 || continue
        [[ $domain == "$host" ]] || resolve_domain "$domain" | grep -Fxq -- "$host" || continue
        printf '%s\t%s\n' "$domain" "$dir"; return 0
    done < <(jq -r '.nodes[]|select(.cert_dir and .sni and (.cert_sha256|not))|[.sni,.cert_dir]|@tsv' "$STATE" | sort -u)
    return 1
}
profile_python() {
    command -v python3 >/dev/null && return 0
    msg '安装临时下载服务需要的 python3…'
    { apt-get update && DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends python3; } || return 1
}
# The download service: serves FILE at exactly PATH once, then exits 0; exits 3 when
# nothing was downloaded within SECONDS. Other paths get 404 and do not count. With
# CERT and KEY it speaks HTTPS. Writes READY once listening.
# Arguments: PORT PATH FILE SECONDS CONTENT_TYPE READY [CERT KEY]
PROFILE_SERVER_PY='
import http.server, socket, ssl, sys, time
port, path, name, seconds, ctype, ready = int(sys.argv[1]), sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5], sys.argv[6]
context = None
if len(sys.argv) > 8:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(sys.argv[7], sys.argv[8])
body = open(name, "rb").read()
done = False
class Handler(http.server.BaseHTTPRequestHandler):
    timeout = 10
    def version_string(self): return ""
    def log_message(self, *args): pass
    def head(self):
        if self.path != path:
            self.send_error(404)
            return False
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Content-Disposition", "attachment; filename=\"%s\"" % path.rsplit("/", 1)[-1])
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        return True
    def do_HEAD(self): self.head()
    def do_GET(self):
        global done
        if self.head():
            self.wfile.write(body)
            self.wfile.flush()
            done = True
class Server(http.server.HTTPServer):
    address_family = socket.AF_INET6
    def server_bind(self):
        if self.address_family == socket.AF_INET6:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()
    def get_request(self):
        conn, address = self.socket.accept()
        conn.settimeout(10)
        if context:
            conn = context.wrap_socket(conn, server_side=True)
        return conn, address
    def handle_error(self, request, address): pass
try:
    server = Server(("::", port), Handler)
except OSError:
    Server.address_family = socket.AF_INET
    server = Server(("0.0.0.0", port), Handler)
open(ready, "w").close()
end = time.monotonic() + seconds
while not done:
    left = end - time.monotonic()
    if left <= 0:
        sys.exit(3)
    server.timeout = left
    server.handle_request()
'
# profile_link CLIENT [ID] [PORT] [SECONDS]: serves the profile at a random path on a
# temporary port until it is downloaded once or SECONDS (600) pass, then closes the
# port again, also on Ctrl+C or a dropped SSH session. Runs in the foreground, under
# the lock. A port left open by a killed run is removed by the next firewall sync.
profile_link() (
    client=$1 id=${2:-} port=${3:-} seconds=${4:-600} server='' dir='' tls='' scheme=http
    profile_client_label "$client" >/dev/null || { err "客户端只能是：$PROFILE_CLIENTS"; exit 1; }
    [[ $seconds =~ ^[1-9][0-9]*$ ]] || { err '时间必须是正整数。'; exit 1; }
    owned_root || exit 1
    nodes=$(profile_nodes "$STATE" "$id") || exit 1
    file=$(profile_file "$client")
    profile_python || { err '没有 python3，无法开启临时下载服务；可以改用「导出完整配置」复制文本。'; exit 1; }
    dir=$(mktemp -d) || exit 1
    trap 'trap "" INT TERM HUP; [[ -z $server ]] || kill "$server" 2>/dev/null; firewall_sync "$STATE" > /dev/null || err "临时端口没有撤掉，请在菜单「4. 运行状态」里选「重新同步防火墙端口规则」。"; rm -rf "$dir"' EXIT
    trap 'exit 130' INT TERM HUP
    profile_render "$client" "$STATE" "$id" > "$dir/$file" || exit 1
    if [[ -z $port ]]; then port=$(choose_port) || exit 1
    else port_free "$port" || { err '端口无效或被占用。'; exit 1; }; fi
    host=$(jq -r '.[0].host' <<< "$nodes")
    if tls=$(profile_tls_domain "$host"); then scheme=https; host=${tls%%$'\t'*}
    elif [[ $host == *:* ]]; then host="[$host]"; fi
    token=$(random_hex 16) || exit 1
    url="$scheme://$host:$port/$token/$file"
    firewall_sync "$STATE" "$port" > /dev/null || { err "无法放行临时端口 $port。"; exit 1; }
    printf '%s' "$PROFILE_SERVER_PY" > "$dir/server.py"
    args=("$port" "/$token/$file" "$dir/$file" "$seconds" "$(profile_content_type "$client")" "$dir/ready")
    [[ -z $tls ]] || args+=("${tls#*$'\t'}/fullchain.pem" "${tls#*$'\t'}/key.pem")
    python3 -I "$dir/server.py" "${args[@]}" > "$dir/server.log" 2>&1 &
    server=$!
    for _ in $(seq 50); do [[ ! -e $dir/ready ]] && kill -0 "$server" 2>/dev/null || break; sleep 0.1; done
    [[ -e $dir/ready ]] || { err "临时下载服务没有启动：$(tail -n 1 "$dir/server.log")"; exit 1; }
    # Profile name in the app: the node's name, or the server address for several nodes.
    link=$(profile_import_link "$client" "$url" "srm-$(jq -r 'if length == 1 then .[0].name else .[0].host end' <<< "$nodes")") || exit 1
    msg ''
    msg "━━━━━━━━ 临时导入链接：$(profile_client_label "$client") ━━━━━━━━"
    profile_import_hint "$client"
    msg $'\n── 一键导入链接（手机扫码，或在装了 App 的设备上点开）──'
    msg "$link"
    if command -v qrencode >/dev/null; then
        if use_color; then qrencode -t ANSIUTF8 <<< "$link"; else qrencode -t UTF8 <<< "$link"; fi
    else msg '（未安装 qrencode，没有二维码。）'; fi
    msg $'\n── 下载地址 ──'
    msg "$url"
    msg ''
    [[ $scheme == https ]] || msg '注意：没有域名证书，只能用 HTTP 传输：链接里带节点密码，用完即关。'
    msg "下载一次或 $(( (seconds + 59) / 60 )) 分钟后自动关闭，并撤掉防火墙放行。导入失败时到云服务器安全组放行入站 TCP $port，或在菜单里选「导出完整配置」复制文本。"
    msg '等待下载…（按 Ctrl+C 提前关闭）'
    rc=0; wait "$server" || rc=$?; server=''
    case $rc in
      0) msg '已下载一次，临时链接已关闭。';;
      3) msg "$(( (seconds + 59) / 60 )) 分钟内没有下载，临时链接已关闭。";;
      *) err "临时下载服务异常退出：$(tail -n 1 "$dir/server.log")"; exit 1;;
    esac
)
# Menu: REPLY = node ID ("" = all enabled nodes), failure = back.
profile_pick_nodes() {
    local ids names name count i
    ids=$(jq -r '.nodes[]|select(.enabled)|.id' "$STATE") || return 1
    names=$(jq -r '.nodes[]|select(.enabled)|.name' "$STATE") || return 1
    count=$(grep -c . <<< "$ids") || { err '没有启用的节点。'; return 1; }
    msg '包含哪些节点：'
    msg "  1. 全部启用的节点（$count 个）"
    i=1
    while IFS= read -r name; do i=$((i+1)); msg "  $i. $name"; done <<< "$names"
    msg '  0. 返回'
    while :; do
        ask '请选择' 1 || return 1
        if [[ $REPLY == 1 ]]; then REPLY=''; return 0; fi
        if [[ $REPLY =~ ^[1-9][0-9]*$ ]] && (( REPLY <= count + 1 )); then REPLY=$(sed -n "$((REPLY-1))p" <<< "$ids"); return 0; fi
        err "请选择 0–$((count+1))。"
    done
}
# Menu: REPLY = client, failure = back.
profile_pick_client() {
    local client i=0
    msg '导入到哪个 App：'
    for client in $PROFILE_CLIENTS; do i=$((i+1)); msg "  $i. $(profile_client_label "$client")"; done
    msg '  0. 返回'
    while :; do
        ask '请选择' 1 || return 1
        # shellcheck disable=SC2086 # one client per word
        if client=$(nth_word "$REPLY" $PROFILE_CLIENTS); then REPLY=$client; return 0; fi
        err "请选择 0–$i。"
    done
}
# 「导出完整配置」 (export) and 「临时导入链接」 (link) of the node management menu.
profile_menu() {
    local mode=$1 id client port
    profile_pick_nodes || return 0
    id=$REPLY
    profile_pick_client || return 0
    client=$REPLY
    if [[ $mode == export ]]; then
        msg $'\n'"━━━━━━━━ 完整配置：$(profile_client_label "$client") ━━━━━━━━"
        profile_render "$client" "$STATE" "$id" || return 1
        msg '━━━━━━━━'
        msg "把上面的内容保存为 $(profile_file "$client")，在 App 里从文件导入。更省事的是在「2. 节点管理」里选「临时导入链接」，扫码一键导入。"
        return 0
    fi
    while :; do
        ask '临时端口（回车随机选一个空闲端口）' 随机 || return 0
        if [[ $REPLY == 随机 ]]; then port=''; break; fi
        if valid_port "$REPLY" && port_free "$REPLY"; then port=$REPLY; break; fi
        err '端口要在 1–65535 之间，并且没有被占用。'
    done
    with_lock profile_link "$client" "$id" "$port"
}
