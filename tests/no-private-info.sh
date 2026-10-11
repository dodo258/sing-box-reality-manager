#!/usr/bin/env bash
# The repository is public: tracked files must not contain anything that points at a
# real server or person. Write servers by code name (e.g. "Lisa"), examples with
# placeholders. Per kind, what passes:
#   ipv4    reserved and documentation ranges (192.0.2.0/24, 198.51.100.0/24,
#           203.0.113.0/24), KNOWN
#   ipv6    addresses that are not global unicast (first group below 2000 or
#           above 3fff); documentation ranges 2001:db8::/32 and 3fff::/20; KNOWN_IPV6
#   uuid    nil, max, and zeros apart from the version, variant and last four digits
#           (00000000-0000-4000-8000-000000000001)
#   key     43-character base64url values right after a private key name
#           (Reality / X25519) when one character repeated apart from the last
#           four (AAAA…AAAE); public keys are published in links and not checked
#   shortid Reality short_id values that are zeros or a prefix of 0123456789abcdef
#           apart from the last digit; KNOWN_SHORT_IDS
#   domain  example.com / .org / .net and their subdomains; reserved names
#           (*.example, *.test, *.invalid, *.localhost) are never reported;
#           KNOWN_DOMAINS and their subdomains
#   email   only at the placeholder domains above
#   path    /Users/<name> and /home/<name> only with the generic names in HOME_NAMES
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }

# Public DNS resolvers; the Cloudflare WARP endpoint (v3 install.sh);
# 128.0.0.0 of the 0.0.0.0/1 + 128.0.0.0/1 routes; input examples in v3
# install.sh and a test placeholder.
KNOWN='1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 9.9.9.9 149.112.112.112 223.5.5.5 223.6.6.6
119.29.29.29 114.114.114.114 1.12.12.12 120.53.53.53
162.159.192.1
128.0.0.0
1.1.1.0 1.1.2.2 2.2.2.2 1.2.3.4'

# Cloudflare DNS; the public NAT64 resolvers of nat64.net suggested by v3 install.sh
# to IPv6-only servers; the AliDNS prefix in an input example of v3 install.sh.
KNOWN_IPV6='2606:4700:4700::1111
2a00:1098:2b::1 2a00:1098:2c::1 2a01:4f8:c2c:123f::1 2a01:4f9:c010:3f02::1
2400:3200::'

# mack-a/v2ray-agent hard-codes this shortId, so it is the same on every v3 install;
# the migration samples copy it.
KNOWN_SHORT_IDS='6ba85179e30d4fc2'

# Public sites and services, each entry also covering its subdomains.
KNOWN_DOMAINS='
github.com githubusercontent.com ghcr.io githubstatus.com gh-proxy.com jsdelivr.net shields.io
sagernet.org metacubex.one nssurge.com shadowsocks.org nginx.org gnu.org fsf.org
cloudflare.com cloudflareclient.com cloudflarestatus.com alidns.com qrserver.com
hostmonit.com digitalocean.com sitemaps.org v2ex.com googletagmanager.com nat64.net
microsoft.com apple.com icloud.com google.com googleapis.com googleapis.cn gstatic.com
bing.com baidu.com qq.com
netflix.com nflxext.com nflximg.com nflximg.net nflxso.net nflxvideo.net
disneyplus.com disney-plus.net dssott.com bamgrid.com youtube.com googlevideo.com ytimg.com
hulu.com max.com
jetbrains.com mozilla.org mozilla.net python.org cisco.com mysql.com oracle.com adobe.com
mongodb.com toyota.com harvard.edu stanford.edu tesla.com sony.com seagate.com sennheiser.com
umich.edu ctrip.com ixigua.com
aniplex.co.jp asus.com atlassian.com autodesk.com awsstatic.com booking.com caltech.edu
century21.com columbia.edu dell.com epicgames.com ericsson.com gundam-official.com gundam.info
hilton.com hp.com hyatt.com ibm.com intel.com java.com kayak.com logitech.com marriott.com
media-amazon.com netgear.com nintendo.com nvidia.com nyu.edu ox.ac.uk playstation.com
postman.com princeton.edu qnap.com redis.io ritzcarlton.com salesforce.com samsung.com sap.com
sothebysrealty.com synology.com tp-link.com trip.com ucla.edu unrealengine.com visa.com.hk
vmware.com xbox.com zillow.com
xn--ngstr-lra8j.com
notexample.com
'
# Groups above: code hosting and downloads; protocol and client docs; network services
# srm or v3 install.sh query; big sites in v3 routing and IP checks; streaming
# routing rules (lib/routing.sh, tests); Reality / ShadowTLS targets in srm, the
# decisions about them and the v3 target lists (documents/*_target_domains.md);
# an internationalized name in a comment of v3 install.sh;
# a routing test input that must not match example.com by suffix.

# Generic names in home directory examples: GitHub Actions runner, cloud image users.
HOME_NAMES='user username you yourname name me runner ubuntu debian admin Shared'

# Top-level domains that count as a domain name. File extensions that are also
# top-level domains (.sh, .md, .py, …) are left out.
TLDS='com net org io dev app me co cn top xyz info cc vip tk uk jp hk sg tw kr de fr ru us
ca au nl eu cloud site online tech pro biz live link club store shop fun icu ltd work win best
moe edu gov im to ly gg ai tv ir'

read -r -d '' scan_awk <<'AWK' || true
BEGIN {
    split_set(ENVIRON["KNOWN_IPV4"], known4)
    split_set(tolower(ENVIRON["KNOWN_IPV6"]), known6)
    split_set(tolower(ENVIRON["KNOWN_SHORT_IDS"]), known_sid)
    split_set(tolower(ENVIRON["KNOWN_DOMAINS"]), known_domain)
    split_set(ENVIRON["HOME_NAMES"], home_name)
    split_set(ENVIRON["TLDS"], tld)
}
function split_set(s, set,    n, i, a) { n = split(s, a, /[ \t\n]+/); for (i = 1; i <= n; i++) if (a[i] != "") set[a[i]] = 1 }
function report(kind, value) { print file ":" lineno ": " kind " " value }
function hex(s,    i, v) { v = 0; s = tolower(s); for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1; return v }
function repeated(s,    i, c) { c = substr(s, 1, 1); for (i = 2; i <= length(s); i++) if (substr(s, i, 1) != c) return 0; return 1 }

# Cuts every match of re out of s, in order: tok[1..n], with the character just
# before (pre) and just after (post) each match.
function tokens(s, re,    n, last) {
    n = 0; last = ""
    while (match(s, re)) {
        n++
        tok[n] = substr(s, RSTART, RLENGTH)
        pre[n] = RSTART > 1 ? substr(s, RSTART - 1, 1) : last
        last = substr(tok[n], RLENGTH, 1)
        s = substr(s, RSTART + RLENGTH)
        post[n] = substr(s, 1, 1)
    }
    return n
}

function check_ipv4(s,    n, i, ip, o, a, b, c) {
    n = tokens(s, "[0-9]+([.][0-9]+)+")
    for (i = 1; i <= n; i++) {
        ip = tok[i]
        # Runs of more than four numbers are versions, not addresses.
        if (split(ip, o, ".") != 4 || o[1] + 0 > 255 || o[2] + 0 > 255 || o[3] + 0 > 255 || o[4] + 0 > 255) continue
        a = o[1] + 0; b = o[2] + 0; c = o[3] + 0
        if (ip in known4) continue
        if (a == 0 || a == 10 || a == 127 || a >= 224) continue           # this network, private, loopback, multicast/reserved
        if (a == 100 && b >= 64 && b <= 127) continue                      # shared address space (CGNAT)
        if (a == 169 && b == 254) continue                                 # link-local
        if (a == 172 && b >= 16 && b <= 31) continue                       # private
        if (a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)))) continue  # private, IETF, TEST-NET-1
        if (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) continue # benchmarking, TEST-NET-2
        if (a == 203 && b == 0 && c == 113) continue                       # TEST-NET-3
        report("ipv4", ip)
    }
}

# Whether t is a whole IPv6 address (no embedded IPv4); sets g1 and g2 to its
# first two groups.
function ipv6_parse(t,    halves, nh, left, right, nl, nr, l, r, i) {
    nh = split(t, halves, "::")
    if (nh > 2) return 0
    nl = halves[1] == "" ? 0 : split(halves[1], l, ":")
    nr = nh == 2 && halves[2] != "" ? split(halves[2], r, ":") : 0
    for (i = 1; i <= nl; i++) if (l[i] !~ /^[0-9a-f]+$/ || length(l[i]) > 4) return 0
    for (i = 1; i <= nr; i++) if (r[i] !~ /^[0-9a-f]+$/ || length(r[i]) > 4) return 0
    if (nh == 1 ? nl != 8 : nl + nr > 7) return 0
    g1 = nl >= 1 ? hex(l[1]) : 0
    g2 = nl >= 2 ? hex(l[2]) : 0
    return 1
}
function check_ipv6(s,    n, i, t, cut) {
    n = tokens(tolower(s), "[0-9a-f]*:[0-9a-f:]*")
    for (i = 1; i <= n; i++) {
        t = tok[i]
        # "IPv6:2001:…": the match starts inside a word, drop that part.
        if (pre[i] ~ /[0-9a-z_]/) { cut = index(t, ":"); t = substr(t, cut + 1) }
        if (t ~ /[^:]:$/) t = substr(t, 1, length(t) - 1)
        if (gsub(/:/, ":", t) < 2 || !ipv6_parse(t)) continue
        if (g1 < 8192 || g1 > 16383) continue                              # not global unicast
        if (g1 == 8193 && g2 == 3512) continue                             # 2001:db8::/32 documentation
        if (g1 == 16383 && g2 < 4096) continue                             # 3fff::/20 documentation
        if (t in known6) continue
        report("ipv6", t)
    }
}

function check_uuid(s,    n, i, p, np, j, u, h) {
    n = tokens(tolower(s), "[0-9a-f]+(-[0-9a-f]+)+")
    for (i = 1; i <= n; i++) {
        if (pre[i] ~ /[0-9a-z_]/ || post[i] ~ /[0-9a-z_]/) continue
        np = split(tok[i], p, "-")
        for (j = 1; j + 4 <= np; j++) {
            if (length(p[j]) != 8 || length(p[j+1]) != 4 || length(p[j+2]) != 4 || length(p[j+3]) != 4 || length(p[j+4]) != 12) continue
            u = p[j] "-" p[j+1] "-" p[j+2] "-" p[j+3] "-" p[j+4]
            h = p[j] p[j+1] p[j+2] p[j+3] p[j+4]
            if (h ~ /^f+$/) continue
            if ((substr(h, 1, 12) substr(h, 14, 3) substr(h, 18, 11)) ~ /^0+$/) continue
            report("uuid", u)
        }
    }
}

# "private_key": "…", privateKey=…, PrivateKey: … (sing-box generate reality-keypair)
function check_key(s,    n, i, v) {
    n = tokens(s, "[Pp]rivate[_-]?[Kk]ey[\"' ]*[:=][\"' ]*[A-Za-z0-9_-]+")
    for (i = 1; i <= n; i++) {
        match(tok[i], /[A-Za-z0-9_-]+$/); v = substr(tok[i], RSTART)
        if (length(v) != 43 || post[i] ~ /[+\/=]/ || repeated(substr(v, 1, 39))) continue
        report("key", v)
    }
}

function check_short_id(s,    n, i, v, head) {
    n = tokens(tolower(s), "(short[_-]?ids?|[?&]sid)[\"' ]*[:=][\"' []*[0-9a-f]+")
    for (i = 1; i <= n; i++) {
        if (post[i] ~ /[0-9a-z_]/) continue
        match(tok[i], /[0-9a-f]+$/); v = substr(tok[i], RSTART)
        if (length(v) > 16 || v in known_sid) continue
        head = substr(v, 1, length(v) - 1)
        if (head ~ /^0*$/ || index("0123456789abcdef", head) == 1) continue
        report("shortid", v)
    }
}

# The domain name at the end of t: the trailing run of valid labels, or "".
function domain_of(t,    n, l, i, d) {
    sub(/[.-]+$/, "", t)
    n = split(tolower(t), l, ".")
    if (n < 2 || !(l[n] in tld)) return ""
    d = l[n]
    for (i = n - 1; i >= 1 && l[i] ~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/; i--) d = l[i] "." d
    return index(d, ".") ? d : ""
}
function placeholder_domain(d) { return d ~ /(^|[.])example[.](com|org|net)$/ }
function known(d,    p) {
    for (p = d; index(p, "."); p = substr(p, index(p, ".") + 1)) if (p in known_domain) return 1
    return 0
}
function check_domain(s,    n, i, t, d) {
    n = tokens(s, "[A-Za-z0-9_.-]+")
    for (i = 1; i <= n; i++) {
        t = tok[i]
        if (!index(t, ".")) continue
        # Escapes and percent-encoding in front of a name: "\nwww.…", "%2Fvpn.…".
        if (pre[i] == "\\" && t ~ /^[nrt]/) t = substr(t, 2)
        if (pre[i] == "%" && t ~ /^[0-9A-Fa-f][0-9A-Fa-f]/) t = substr(t, 3)
        d = domain_of(t)
        if (d == "" || placeholder_domain(d) || known(d)) continue
        report("domain", d)
    }
}

function check_email(s,    n, i, d) {
    n = tokens(s, "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+")
    for (i = 1; i <= n; i++) {
        d = domain_of(substr(tok[i], index(tok[i], "@") + 1))
        if (d == "" || placeholder_domain(d)) continue
        report("email", tok[i])
    }
}

function check_path(s,    n, i, name) {
    n = tokens(s, "/(Users|home)/[A-Za-z0-9._-]+")
    for (i = 1; i <= n; i++) {
        if (pre[i] ~ /[A-Za-z0-9_.~-]/) continue
        name = substr(tok[i], index(substr(tok[i], 2), "/") + 2)
        if (name in home_name) continue
        report("path", tok[i])
    }
}

{
    # git grep -n: file:line:content
    file = $0; sub(/:.*/, "", file)
    rest = substr($0, length(file) + 2)
    lineno = rest; sub(/:.*/, "", lineno)
    s = substr(rest, length(lineno) + 2)
    check_ipv4(s); check_ipv6(s); check_uuid(s); check_key(s); check_short_id(s)
    check_domain(s); check_email(s); check_path(s)
}
AWK

# Prints "file:line: kind value" for each finding in the working tree of tracked
# files, or in the given file of the current directory.
private_info() {
    local args=(--no-color -I -n -E '.')
    [[ $# == 0 ]] || args=(--no-index "${args[@]}" -- "$1")
    { git grep "${args[@]}" || [[ $? == 1 ]]; } |
        KNOWN_IPV4=$KNOWN KNOWN_IPV6=$KNOWN_IPV6 KNOWN_SHORT_IDS=$KNOWN_SHORT_IDS \
        KNOWN_DOMAINS=$KNOWN_DOMAINS HOME_NAMES=$HOME_NAMES TLDS=$TLDS awk "$scan_awk"
}

# The scan itself has to catch one real-looking value of every kind and let the
# placeholders through. Real values are built at run time so this file stays clean.
d=$(printf 'real%s' 'host'); c=com
v4=$(printf '%d.%d.%d.%d' 45 76 18 9)
edge=$(printf '%d.%d.%d.%d' 172 32 0 1)
v6=$(printf '2a0%d:%d:%x::%d' 5 4 64206 9)
uuid=$(printf '%s-%s-%s-%s-%s' 3f2a9c1e 7b4d 4e5f 9a1b 0c7d2e8f4a6b)
key=$(printf '%s%s%s' kJ8vR2mQ7xN4pL6tW9yB3cF 5hD1gS0aZ8 eU4iO2qVtY)
sid=$(printf '%s%s' 7c2e 9a41)
cat > "$work/real" <<EOF
host $v4 ok
gateway [$v6]:443 IPv6:$v6
"uuid": "$uuid"
"private_key": "$key"
"short_id": ["$sid"]
https://vpn.$d.$c/sub
contact me@$d.$c
cd /home/$d
EOF
cat > "$work/placeholder" <<'EOF'
listen 0.0.0.0 127.0.0.1 10.1.2.3 172.31.255.1 192.168.1.1 [::1] fe80::1 fd00::1
docs 192.0.2.1 198.51.100.7 203.0.113.5 2001:db8::1 3fff:0:1::1 dns 2606:4700:4700::1111 v1.2.3.4.5
time 12:30:45 mac aa:bb:cc:dd:ee:ff bad 2001::1::2 2001:::1
"uuid": "00000000-0000-4000-8000-000000000001" nil 00000000-0000-0000-0000-000000000000 xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
"private_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE" PrivateKey: <私钥>
"public_key": "Qx1d9gj9YQVAo1mzznlkxp4vrQ-yRiFS7lMURE4wogs"
"short_id": "0123456789abcdef" short-id: "0000000000000001" sid=01 short_id and .short_id[0]
https://vpn.example.com/ a.example b.test c.invalid "\nwww.example.org" %2Fhy.example.net
https://github.com/SagerNet/sing-box sing-box@1.service config.json README.md install.sh
username@example.com pw@test.example.com
cd /home/runner /Users/<名字> /home/$USER https://example.com/home/page
EOF
printf 'dns %s\n' "$(printf '%d.%d.%d.%d' 1 1 1 1)" >> "$work/placeholder"
found=$(cd "$work" && private_info placeholder)
[[ -z $found ]] || fail "self-check reported placeholders: $found"
found=$(cd "$work" && private_info real)
expected="real:1: ipv4 $v4
real:2: ipv6 $v6
real:2: ipv6 $v6
real:3: uuid $uuid
real:4: key $key
real:5: shortid $sid
real:6: domain vpn.$d.$c
real:7: domain $d.$c
real:7: email me@$d.$c
real:8: path /home/$d"
[[ $found == "$expected" ]] || fail "self-check found:
$found"
printf '%s\n' "$edge/12" > "$work/edge"
[[ $(cd "$work" && private_info edge) == "edge:1: ipv4 $edge" ]] || fail 'self-check: the address just above 172.16.0.0/12 is public'
echo 'PASS the scan reports a real IPv4, IPv6, UUID, private key, short_id, domain, email and home path, and skips placeholders'

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail 'not a git work tree, cannot list tracked files'
found=$(private_info)
[[ -z $found ]] || fail "tracked files contain private-looking values (use a placeholder, or add a well-known public value with its reason to KNOWN or KNOWN_* in tests/no-private-info.sh):
$found"
echo 'PASS tracked files contain no real address, UUID, key, domain, email or home path'
