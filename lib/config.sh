# Configuration is generated from one root-owned state file, never edited in-place.
# Protocol-specific fields are validated and rendered through lib/protocols.sh.
STATE_SCHEMA=2
empty_state() { printf '%s\n' '{"schema":2,"nodes":[],"policies":[],"unlock_dns":null,"egress":null}'; }
# Older state is upgraded one schema at a time whenever it is about to change;
# the result goes to stdout and the input file is left untouched.
#   1 → 2: policies may carry "inbounds" (node ids); nodes stay exactly the same.
state_migrate_1() { jq '.schema = 2'; }
state_upgrade() {
    local json schema
    json=$(jq -c . "$1") && schema=$(jq -r '.schema|tojson' <<< "$json") || { err '节点数据无法读取，未改动。'; return 1; }
    while [[ $schema != "$STATE_SCHEMA" ]]; do
        [[ $schema =~ ^[1-9][0-9]*$ ]] && (( schema < STATE_SCHEMA )) && declare -F "state_migrate_$schema" >/dev/null ||
            { err "节点数据版本 $schema 不受支持（可能来自更新版本的脚本），未改动。"; return 1; }
        json=$("state_migrate_$schema" <<< "$json") && schema=$(jq -r '.schema|tojson' <<< "$json") || return 1
    done
    printf '%s\n' "$json"
}
valid_port() { [[ $1 =~ ^[1-9][0-9]{0,4}$ ]] && (( $1 <= 65535 )); }
valid_domain() {
    [[ ${#1} -le 253 && $1 == *.* && $1 != *..* && $1 =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || return 1
    local label
    local IFS=.
    for label in $1; do
        [[ ${#label} -le 63 && $label != -* && $label != *- ]] || return 1
    done
}
valid_ip() {
    local address=$1 part compressed=0 count=0 rest
    if [[ $address =~ ^[0-9.]+$ ]]; then
        [[ $address != .* && $address != *. && $address != *..* ]] || return 1
        local IFS=.
        for part in $address; do
            [[ $part =~ ^[0-9]{1,3}$ ]] && ((10#$part <= 255)) || return 1
            count=$((count+1))
        done
        [[ $count == 4 ]]; return
    fi
    [[ $address == *:* && $address =~ ^[0-9a-fA-F:]+$ && $address != *:::* ]] || return 1
    if [[ $address == *::* ]]; then compressed=1; rest=${address#*::}; [[ $rest != *::* ]] || return 1
    else [[ $address != :* && $address != *: ]] || return 1; fi
    local IFS=:
    for part in $address; do
        [[ -n $part ]] || continue
        [[ ${#part} -le 4 ]] || return 1
        count=$((count+1))
    done
    if [[ $compressed == 1 ]]; then ((count<8)); else ((count==8)); fi
}
valid_host() {
    if [[ $1 =~ ^[0-9.]+$ || $1 == *:* ]]; then valid_ip "$1"; else valid_domain "$1"; fi
}
validate_state() {
    jq -e "$PROTO_JQ_DEFS"'
      def text: type == "string" and length > 0 and (test("[\\x00-\\x1f\\x7f]")|not);
      [.nodes[]?.id] as $ids |
      .schema == 2 and (.nodes|type == "array") and (.policies|type == "array") and
      ([.policies[].name]|length == (unique|length)) and
      ([.nodes[].id]|length == (unique|length)) and
      # Node ports and the loopback ports of helper services never overlap.
      ([.nodes[]|.port, (.local_port // empty)]|length == (unique|length)) and
      all(.nodes[];
        (.id|test("^[a-f0-9]{16}$")) and (.name|text) and
        (.host|text) and (.sni == null or (.sni|text)) and ((.listen // "::") == "::" or .listen == "0.0.0.0") and (.enabled|type == "boolean") and
        (.port|type == "number" and floor == . and . >= 1 and . <= 65535) and
        ('"$(proto_jq validate false)"')) and
      all(.policies[];
        (.name|text) and (.mode == "dns" or .mode == "proxy") and
        (.domains|type == "array" and length > 0) and
        all(.domains[]; text and test("^[a-z0-9][a-z0-9.-]*[a-z0-9]$")) and
        # Optional: limit the rule to these nodes; absent means every node.
        (.inbounds == null or (.inbounds|type == "array" and length > 0 and length == (unique|length) and
          all(.[]; . as $i | any($ids[]; . == $i))))) and
      ((any(.policies[]; .mode == "dns")|not) or (.unlock_dns|type == "string" and length > 0)) and
      ((any(.policies[]; .mode == "proxy")|not) or (.egress|type == "object")) and
      (.egress == null or (.egress.type == "socks" and .egress.version == "5" and
        (.egress.server|text) and (.egress.server_port|type == "number" and floor == . and . > 0 and . <= 65535)))
    ' "$1" >/dev/null || { err '节点数据格式不合法，未应用。'; return 1; }
    local h
    h=$(jq -r '.unlock_dns // empty' "$1")
    [[ -z $h ]] || valid_ip "$h" || { err '解锁 DNS IP 无效。'; return 1; }
    while IFS= read -r h; do valid_host "$h" || { err "地址不合法：$h"; return 1; }; done < <(jq -r '.nodes[].host, (.egress.server // empty)' "$1")
    while IFS= read -r h; do valid_domain "$h" || { err "域名不合法：$h"; return 1; }; done < <(jq -r '.nodes[].sni // empty, .policies[].domains[]' "$1")
}
render_config() {
    validate_state "$1" || return 1
    jq "$PROTO_JQ_DEFS"'
      # A policy limited to some nodes matches only traffic entering through their inbounds.
      def scope: if .inbounds then {inbound:.inbounds} else {} end;
      . as $s |
      [.policies[]|select(.mode=="dns")] as $dns |
      [.policies[]|select(.mode=="proxy")] as $proxy |
      {
        log: {level:"warn",timestamp:true},
        dns: {
          servers: ([{type:"local",tag:"local"}]
            + (if ($dns|length)>0 then [{type:"udp",tag:"unlock",server:$s.unlock_dns,server_port:53}] else [] end)
            + (if ($proxy|length)>0 then [{type:"https",tag:"remote-dns",server:"1.1.1.1",detour:"media-proxy"}] else [] end)),
          rules: ([$proxy[]|scope + {domain_suffix:.domains,action:"route",server:"remote-dns"}]
            + [$dns[]|scope + {domain_suffix:.domains,action:"route",server:"unlock"}]),
          final:"local"
        },
        inbounds: [$s.nodes[]|select(.enabled)|('"$(proto_jq render_inbound '[]')"')[]],
        outbounds: ([{type:"direct",tag:"direct"}]
          + (if ($proxy|length)>0 then [$s.egress + {tag:"media-proxy",domain_resolver:"local"}] else [] end)),
        route: {default_domain_resolver:"local",final:"direct",rules: (
          [{action:"sniff",timeout:"300ms"},{protocol:"dns",action:"hijack-dns"}]
          + [$proxy[]|scope + {domain_suffix:.domains,action:"route",outbound:"media-proxy"}]
          + [$dns[]|(scope + {domain_suffix:.domains,action:"resolve",server:"unlock",strategy:"ipv4_only"}),
                    (scope + {domain_suffix:.domains,action:"route",outbound:"direct"})])
        }
      }
    ' "$1"
}
node_json() { jq -e --arg id "$2" '.nodes[]|select(.id==$id)' "$1"; }
client_outbound() { jq "$PROTO_JQ_DEFS $(proto_jq client_outbound 'error("不支持的协议：\(.type)")')"; }
share_uri() { jq -r "$PROTO_JQ_DEFS $(proto_jq share_uri 'error("不支持的协议：\(.type)")')"; }
# Client snippets; empty output when the client has no support for the protocol.
clash_proxy() { jq -r "$PROTO_JQ_DEFS $(proto_jq clash empty)|\"- \(tojson)\""; }
surge_proxy() { jq -r "$PROTO_JQ_DEFS $(proto_jq surge empty)"; }
# The Surge line on stdin as the fields of Surge's new-proxy form, one per line.
surge_form() { jq -Rr "$SURGE_FORM_JQ"; }
client_note() { jq -r "$PROTO_JQ_DEFS $(proto_jq note empty)"; }
