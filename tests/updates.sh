#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
source tests/support/guard.sh
need_core
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
SRM_ROOT=$work/root
DATA=$work/data
CORE=$SRM_ROOT/core/sing-box
mkdir -p "$SRM_ROOT/core" "$DATA/current"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
printf '#!/usr/bin/env bash\necho "sing-box version 0.0.0"\n' > "$CORE"
chmod 755 "$CORE"
old_hash=$(sha256 "$CORE")
core_download() { cp "${TEST_CORE:?}" "$1" && chmod 755 "$1"; }
systemctl() { [[ $1 != is-active ]]; }
printf 'invalid config\n' > "$DATA/current/config.json"
if update_core; then echo 'FAIL invalid configuration accepted'; exit 1; fi
[[ $(sha256 "$CORE") == "$old_hash" ]] || exit 1
echo 'PASS invalid configuration leaves original core intact'
printf '{"outbounds":[{"type":"direct","tag":"direct"}]}\n' > "$DATA/current/config.json"
systemctl() { return 0; }
service_healthy() { return 1; }
if update_core; then echo 'FAIL unhealthy core accepted'; exit 1; fi
[[ $(sha256 "$CORE") == "$old_hash" ]] || exit 1
echo 'PASS unhealthy service restores old core'
systemctl() { [[ $1 != is-active ]]; }
update_core
[[ $(sha256 "$CORE") == "$(sha256 "$TEST_CORE")" ]] || exit 1
echo 'PASS stopped service can update without being started'

printf 'original-manager\n' > "$SRM_ROOT/manager.sh"
update_latest() { printf 'update_core() { return 1; }\n' > "$SRM_ROOT/manager.sh"; }
if update_all; then echo 'FAIL failed combined update accepted'; exit 1; fi
[[ $(cat "$SRM_ROOT/manager.sh") == original-manager ]] || exit 1
echo 'PASS combined update restores manager when new core update fails'
update_latest() { printf 'update_core() { return 0; }\n' > "$SRM_ROOT/manager.sh"; }
update_all
grep -q 'return 0' "$SRM_ROOT/manager.sh"
echo 'PASS combined update runs the new manager core updater'
