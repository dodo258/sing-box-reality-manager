#!/usr/bin/env bash
# Command line: --help lists every subcommand main() dispatches, unknown
# commands fail, and the bundle behaves like the development loader.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
help=$(bash srm.sh --help) || fail 'srm --help exit code'
# Top-level case labels in main() are indented six spaces; nested ones more.
commands=$(awk '/^main\(\) \{/,/^}/' lib/main.sh | grep -E '^      [a-z][a-z|-]*\)' | sed -E 's/^ +//; s/\).*//' | tr '|' '\n' | grep -v '^-')
(( $(printf '%s\n' "$commands" | wc -l) >= 25 )) || fail "too few commands parsed: $commands"
for command in $commands; do
    grep -qE "^  srm $command( |$)" <<< "$help" || fail "help does not list: srm $command"
done
echo "PASS srm --help lists all $(printf '%s\n' "$commands" | wc -l | tr -d ' ') subcommands"
[[ $(bash srm.sh help) == "$help" && $(bash srm.sh add --help) == "$help" && $(bash srm.sh node x -h) == "$help" ]] || fail 'help variants'
[[ $(bash dist/srm --help) == "$help" ]] || fail 'bundle help differs; run ./build.sh'
grep -q 'vless anytls hysteria2' <<< "$help" || fail 'help lists registry protocols'
if grep -q $'\033' <<< "$help"; then fail 'color codes in redirected output'; fi
echo 'PASS help, -h and the bundle agree; no color codes when not a terminal'
if bash srm.sh no-such-command > /dev/null 2> "$(mktemp)"; then fail 'unknown command exit 0'; fi
if bash srm.sh render > /dev/null 2>&1; then fail 'render without file exit 0'; fi
if bash srm.sh certs nonsense > /dev/null 2>&1; then fail 'bad certs argument exit 0'; fi
if bash srm.sh uninstall now > /dev/null 2>&1; then fail 'bad uninstall argument exit 0'; fi
if bash srm.sh node > /dev/null 2>&1; then fail 'node without ID exit 0'; fi
echo 'PASS unknown commands and bad arguments exit non-zero'
source lib/common.sh
[[ $(bash dist/srm version) == "srm $SRM_VERSION / tested core $CORE_VERSION" ]] || fail version
[[ $(bash srm.sh protocols | cut -f1,3 | tr '\t\n' ': ') == 'vless:tcp anytls:tcp hysteria2:udp ' ]] || fail protocols
echo 'PASS version and protocol list'
# main() passes the remaining arguments to each handler unchanged.
(
    source ./srm.sh
    with_lock() { printf '%s\n' "$*"; }
    require_root() { return 0; }
    [[ $(main routing dns 192.0.2.1) == 'routing_change dns 192.0.2.1' ]] || fail 'routing dispatch'
    [[ $(main routing add N dns 'a.com b.com') == 'routing_change add N dns a.com b.com' ]] || fail 'routing add dispatch'
    [[ $(main add vless --name x --yes) == "node_add $SRM_SELF vless --name x --yes" ]] || fail 'add dispatch'
    [[ $(main node 1111111111111111 port 20000) == 'node_change 1111111111111111 port 20000' ]] || fail 'node dispatch'
    [[ $(main uninstall --yes) == uninstall ]] || fail 'uninstall dispatch'
    [[ $(main bbr on) == bbr_enable && $(main auto-update off) == auto_update_off ]] || fail 'subcommand dispatch'
) || exit 1
echo 'PASS subcommands pass their arguments to the right handler'
