#!/usr/bin/env bash
# The repository is public: tracked files must not contain the IPv4 address of
# a real server (write servers by code name, e.g. "Lisa"). Every IPv4 address
# in tracked files has to be in a reserved or documentation range, or be one
# of the well-known public addresses below.
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

# Prints file:line:address for each address outside the allowed ranges;
# options go to git grep (none = the working tree of tracked files).
public_ipv4() {
    { git grep "$@" --no-color -I -n -o -E '[0-9]+(\.[0-9]+)+' || [[ $? == 1 ]]; } | KNOWN=$KNOWN awk -F: '
        BEGIN { n = split(ENVIRON["KNOWN"], k, " "); for (i = 1; i <= n; i++) allowed[k[i]] = 1 }
        {
            ip = $NF
            # Runs of more than four numbers are versions, not addresses.
            if (split(ip, o, ".") != 4 || o[1] + 0 > 255 || o[2] + 0 > 255 || o[3] + 0 > 255 || o[4] + 0 > 255) next
            a = o[1] + 0; b = o[2] + 0; c = o[3] + 0
            if (ip in allowed) next
            if (a == 0 || a == 10 || a == 127 || a >= 224) next          # this network, private, loopback, multicast/reserved
            if (a == 100 && b >= 64 && b <= 127) next                     # shared address space (CGNAT)
            if (a == 169 && b == 254) next                                # link-local
            if (a == 172 && b >= 16 && b <= 31) next                      # private
            if (a == 192 && (b == 168 || (b == 0 && (c == 0 || c == 2)))) next  # private, IETF, TEST-NET-1
            if (a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100))) next # benchmarking, TEST-NET-2
            if (a == 203 && b == 0 && c == 113) next                      # TEST-NET-3
            print
        }'
}

# The scan itself has to catch a public address (built at run time so this
# file stays clean) and let the allowed ones through.
public=$(printf '%d.%d.%d.%d' 45 76 18 9)
edge=$(printf '%d.%d.%d.%d' 172 32 0 1)
printf 'host %s ok\nlisten 0.0.0.0 127.0.0.1 10.1.2.3 172.31.255.1 192.168.1.1\n' "$public" > "$work/sample"
printf 'docs 192.0.2.1 198.51.100.7 203.0.113.5 dns 1.1.1.1 223.5.5.5 v1.2.3.4.5 99.%s\n%s/12\n' "$public" "$edge" >> "$work/sample"
found=$(cd "$work" && public_ipv4 --no-index)
[[ $found == "sample:1:$public"$'\n'"sample:4:$edge" ]] || fail "self-check found: $found"
echo 'PASS the scan reports public addresses and skips reserved, documentation and listed ones'

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail 'not a git work tree, cannot list tracked files'
found=$(public_ipv4)
[[ -z $found ]] || fail "tracked files contain public IPv4 addresses (write servers by code name, or add a well-known address to KNOWN in tests/no-real-ip.sh):
$found"
echo 'PASS tracked files contain no real server IPv4 address'
