#!/usr/bin/env bash
# Version check and manual updates of sing-box, snell-server and the script.
# Downloads come from local fixtures (fetch is replaced), systemctl only records,
# so this runs anywhere without root or network.
# Assertions use `|| fail` because `! cmd` never trips set -e, and bash 3.2
# (macOS) also ignores a failing [[ ]].
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL %s\n' "$*"; exit 1; }
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/current/state.json
CORE=$SRM_ROOT/core/sing-box
mkdir -p "$SRM_ROOT/core" "$SRM_ROOT/snell/v6" "$SRM_ROOT/snell/v5" "$DATA/current" "$work/rel"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
arch=$(core_arch)
case $arch in amd64) snell_arch=amd64;; *) snell_arch=aarch64;; esac

# Fake programs: a core that prints its version and accepts (0) or rejects (1) any
# configuration, and a snell-server that prints the version it was given.
make_core() { printf '#!/usr/bin/env bash\ncase $1 in version) echo "sing-box version %s";; check) exit %s;; esac\n' "$1" "$2" > "$3"; chmod 755 "$3"; }
make_snell() { printf '#!/bin/sh\necho "snell-server v%s (test)"\n' "$1" > "$2"; chmod 755 "$2"; }
# Release API answer for VERSION: [check result of its core] [prerelease] [digest].
make_release() {
    local v=$1 dir=sing-box-$1-linux-$arch digest
    mkdir -p "$work/rel/$dir"
    make_core "$v" "${2:-0}" "$work/rel/$dir/sing-box"
    tar -czf "$work/$dir.tar.gz" -C "$work/rel" "$dir"
    digest=${4:-$(sha256 "$work/$dir.tar.gz")}
    jq -n --arg v "$v" --arg arch "$arch" --arg d "sha256:$digest" --argjson pre "${3:-false}" \
        '{tag_name:"v\($v)",draft:false,prerelease:$pre,assets:[
          {name:"sing-box-\($v)-linux-\($arch).tar.gz",digest:$d},{name:"sing-box-\($v)-linux-386.tar.gz",digest:"sha256:00"}]}' > "$work/release.json"
}
# Official zip of VERSION whose snell-server reports PRINTED.
make_snell_zip() {
    make_snell "$2" "$work/snell-server"
    python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").write(sys.argv[2], "snell-server")' \
        "$work/snell-server-v$1-linux-$snell_arch.zip" "$work/snell-server"
}
# Release notes listing these builds the way kb.nssurge.com links them.
make_notes() {
    local v
    for v in "$@"; do printf '<a href="https://dl.nssurge.com/snell/snell-server-v%s-linux-%s.zip">%s</a>\n' "$v" "$snell_arch" "$v"; done > "$work/notes.html"
}
fetch() {
    printf '%s\n' "$1" >> "$work/fetches"
    case $1 in
      https://api.github.com/repos/SagerNet/sing-box/releases/latest) cp "$work/release.json" "$2";;
      https://github.com/SagerNet/sing-box/releases/download/v*|https://dl.nssurge.com/snell/*) cp "$work/${1##*/}" "$2";;
      "$SNELL_NOTES") cp "$work/notes.html" "$2";;
      *) return 1;;
    esac
}
systemctl() {
    printf '%s\n' "$*" >> "$work/systemctl"
    case $1 in
      is-active) [[ ! -e $work/stopped ]];;
      is-enabled) [[ -e $work/timer-enabled ]];;
      enable) touch "$work/timer-enabled";;
      disable) rm -f "$work/timer-enabled";;
    esac
}
service_healthy() { [[ ! -e $work/unhealthy ]]; }
require_linux() { return 0; }
with_lock() { printf '%s\n' "$*" >> "$work/locked"; "$@"; }
# Every file and link under the installation: path, inode and content (or target).
snapshot() {
    find "$SRM_ROOT" "$DATA" \( -type f -o -type l \) ! -name update-check.json | sort | while IFS= read -r f; do
        if [[ -L $f ]]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"
        else printf '%s %s %s\n' "$f" "$(ls -i "$f" | awk '{print $1}')" "$(sha256 "$f")"; fi
    done
}
reset_logs() { rm -f "$work/fetches" "$work/systemctl" "$work/locked" "$work/unhealthy"; }
core_version() { "$CORE" version | awk '{print $3}'; }

make_core 1.14.1 0 "$CORE"
make_snell 6.0.0 "$SRM_ROOT/snell/v6/snell-server"
printf '6.0.0rc2\n' > "$SRM_ROOT/snell/v6/version"
make_snell 5.0.1 "$SRM_ROOT/snell/v5/snell-server"
printf '{"outbounds":[{"type":"direct","tag":"direct"}]}\n' > "$DATA/current/config.json"
jq -n '{schema:2,policies:[],unlock_dns:null,egress:null,nodes:[
 {id:"1111111111111111",name:"r",type:"vless",enabled:true,host:"192.0.2.1",port:18101,sni:"www.python.org",uuid:"0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a5b",private_key:"private",public_key:"public",short_id:"0123456789abcdef"},
 {id:"5000000000000001",name:"s6",type:"snell",enabled:true,host:"192.0.2.1",port:18102,sni:"www.python.org",snell_version:6,snell_mode:"default",psk:"p",shadowtls_password:"w",local_port:20001},
 {id:"5000000000000002",name:"s5",type:"snell",enabled:false,host:"192.0.2.1",port:18103,sni:"www.python.org",snell_version:5,psk:"p",shadowtls_password:"w",local_port:20002}]}' > "$STATE"
touch "$work/timer-enabled"

# --- the daily check ----------------------------------------------------------
make_release 1.14.9
make_notes 5.0.0 5.0.1 6.0.0rc 6.0.0rc2 6.0.0rc3
reset_logs
before=$(snapshot)
main update-check run > "$work/out" 2>&1 || { cat "$work/out"; fail 'check run'; }
[[ $(snapshot) == "$before" ]] || fail 'the check changed or replaced a file'
[[ ! -e $work/systemctl ]] || { cat "$work/systemctl"; fail 'the check called systemctl'; }
[[ ! -e $work/locked ]] || fail 'the check took the lock (which may resume an interrupted change)'
[[ $(sort "$work/fetches" | tr '\n' ' ') == "https://api.github.com/repos/SagerNet/sing-box/releases/latest $SNELL_NOTES " ]] || { cat "$work/fetches"; fail 'the check downloaded more than version information'; }
echo 'PASS the timer check only looks up versions: no download, no systemctl call (no restart), no file replaced, no lock'
jq -e '.items == [
  {name:"sing-box",current:"1.14.1",latest:"1.14.9",newer:true},
  {name:"Snell v5",current:"5.0.1",latest:"5.0.1",newer:false},
  {name:"Snell v6",current:"6.0.0rc2",latest:"6.0.0rc3",newer:true}] and .errors == [] and (.checked_at|length) > 0' "$DATA/update-check.json" >/dev/null || { cat "$DATA/update-check.json"; fail 'cache contents'; }
echo 'PASS the check records sing-box and the Snell major versions in use; v6 without a release follows the newest RC'
[[ $(update_hint) == 'sing-box 1.14.1 → 1.14.9，Snell v6 6.0.0rc2 → 6.0.0rc3' ]] || fail "hint: $(update_hint)"
main status > "$work/out" 2>&1 || true
grep -q '可更新：sing-box 1.14.1 → 1.14.9' "$work/out" || fail 'srm status shows the hint'
echo 'PASS the hint comes from the cache, also in srm status'

# Once v6 has a release, only releases count: 6.0.1rc1 is newer but skipped.
make_notes 5.0.1 6.0.0rc2 6.0.0rc3 6.0.0 6.0.1rc1 6.1.0b1
[[ $(snell_pick 6 < "$work/notes.html") == 6.0.0 && $(snell_pick 5 < "$work/notes.html") == 5.0.1 ]] || fail 'release over RC'
main update-check run > /dev/null 2>&1 || fail 'check run with a v6 release'
jq -e '.items[]|select(.name == "Snell v6")|.latest == "6.0.0" and .newer' "$DATA/update-check.json" >/dev/null || fail 'v6 release recorded'
if snell_pick 4 < "$work/notes.html"; then fail 'a major version without builds picked something'; fi
echo 'PASS Snell v6 takes the release once there is one, and no RC after it'

# sing-box pre-releases are never offered, even one not flagged as such.
cp "$work/release.json" "$work/release.stable"
for flags in 'true v' 'false -beta.1'; do
    pre=${flags% *}; suffix=${flags#* }; suffix=${suffix#v}
    jq --argjson pre "$pre" --arg s "$suffix" '.prerelease = $pre | .tag_name = "v1.15.0-alpha.1" | if $s != "" then .tag_name = "v1.15.0\($s)" else . end' "$work/release.stable" > "$work/release.json"
    reset_logs
    if main update-check run > "$work/out" 2>&1; then fail "check accepted pre-release ($flags)"; fi
    jq -e '(.items[0]|.name == "sing-box" and .latest == null and .newer == false) and (.errors|length) == 1' "$DATA/update-check.json" >/dev/null || fail "pre-release cached ($flags)"
    before=$(snapshot)
    if update_core > "$work/out" 2>&1; then fail "update took a pre-release ($flags)"; fi
    [[ $(snapshot) == "$before" ]] && ! grep -q releases/download "$work/fetches" || fail "pre-release downloaded ($flags)"
done
cp "$work/release.stable" "$work/release.json"
main update-check run > /dev/null 2>&1 || fail 'check run after pre-release'
echo 'PASS sing-box pre-releases are skipped: not offered, not downloaded'

# --- manual updates, only through menu choices ----------------------------------
# Main menu 5 (update) → 2 (only sing-box) → Enter: the default is "back".
reset_logs
before=$(snapshot)
main menu <<< $'5\n2\n\n0' > "$work/out" 2>&1 || fail 'menu back'
grep -q '更新需要重启服务，所有连接会断开几秒' "$work/out" && grep -q '已返回，没有更新' "$work/out" || { cat "$work/out"; fail 'confirmation prompt'; }
[[ $(snapshot) == "$before" && ! -e $work/fetches && ! -e $work/locked ]] || fail 'declining changed something'
echo 'PASS updating first warns that connections drop; Enter goes back without updating'

grep -q '可更新：sing-box 1.14.1 → 1.14.9' "$work/out" || fail 'menu header hint'
reset_logs
main menu <<< $'5\n2\n1\n0' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu core update'; }
grep -q 'sing-box 已从 1.14.1 更新到 1.14.9' "$work/out" || { cat "$work/out"; fail 'core update message'; }
[[ $(core_version) == 1.14.9 && $("$CORE.previous" version) == 'sing-box version 1.14.1' ]] || fail 'core replaced'
grep -qx 'restart srm.service' "$work/systemctl" && grep -qx update_core "$work/locked" || fail 'restart under the lock'
[[ $(update_hint) == 'Snell v6 6.0.0rc2 → 6.0.0' ]] || fail "hint after update: $(update_hint)"
if compgen -G "$SRM_ROOT/core/.candidate.*" > /dev/null; then fail 'candidate left behind'; fi
echo 'PASS menu 5 → 2 → confirm: new sing-box → digest verified → replaced → restarted → healthy; hint cleared'

reset_logs
main update core --yes > "$work/out" 2>&1 || fail 'up-to-date core'
grep -q 'sing-box 已是最新版本 1.14.9，不需要重启' "$work/out" || fail 'up-to-date message'
[[ ! -e $work/systemctl ]] && ! grep -q releases/download "$work/fetches" || fail 'up-to-date core restarted or downloaded'
echo 'PASS sing-box already up to date: nothing downloaded, nothing restarted'

good=$(sha256 "$CORE")
make_release 1.14.10 0 false 0000000000000000000000000000000000000000000000000000000000000000
reset_logs
if update_core > "$work/out" 2>&1; then fail 'digest mismatch accepted'; fi
grep -q 'SHA256 校验失败' "$work/out" || fail 'digest message'
[[ $(sha256 "$CORE") == "$good" && ! -e $work/systemctl ]] || fail 'digest mismatch replaced or restarted'
if compgen -G "$SRM_ROOT/core/.candidate.*" > /dev/null; then fail 'candidate left after a bad digest'; fi
echo 'PASS a download that does not match the Release digest replaces nothing'

make_release 1.14.11 1
reset_logs
if update_core > "$work/out" 2>&1; then fail 'core rejecting the configuration accepted'; fi
grep -q '不接受当前配置' "$work/out" && [[ $(sha256 "$CORE") == "$good" && ! -e $work/systemctl ]] || fail 'sing-box check gate'
echo 'PASS a new sing-box that fails `sing-box check` on the current configuration replaces nothing'

make_release 1.14.12
reset_logs; touch "$work/unhealthy"
if update_core > "$work/out" 2>&1; then fail 'unhealthy core accepted'; fi
grep -q '健康检查失败，已恢复 1.14.9' "$work/out" || fail 'rollback message'
[[ $(sha256 "$CORE") == "$good" && $(grep -cx 'restart srm.service' "$work/systemctl") == 2 ]] || fail 'core rolled back and restarted'
echo 'PASS a failed health check after the restart puts the previous sing-box back'

# Snell: menu 5 → 3 (only Snell) → confirm. The disabled v5 node's service stays as is.
make_snell_zip 6.0.0 6.0.0
reset_logs
main menu <<< $'5\n3\n1\n0' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu snell update'; }
grep -q 'Snell v6 已从 6.0.0rc2 更新到 6.0.0' "$work/out" && grep -q 'Snell v5 已是最新版本 5.0.1' "$work/out" || { cat "$work/out"; fail 'snell messages'; }
[[ $(cat "$SRM_ROOT/snell/v6/version") == 6.0.0 ]] || fail 'snell version file'
[[ $(grep '^restart ' "$work/systemctl") == 'restart srm-snell@5000000000000001.service' ]] || { cat "$work/systemctl"; fail 'only the v6 node service restarts'; }
grep -q 'snell-server-v6.0.0-linux-' "$work/fetches" && ! grep -q 'snell-server-v5' "$work/fetches" || fail 'only v6 downloaded'
[[ -z $(update_hint) ]] || fail 'hint after snell update'
echo 'PASS menu 5 → 3 → confirm: Snell v6 downloads, runs and reports its version, then replaces and restarts only v6 nodes'

snell6=$(sha256 "$SRM_ROOT/snell/v6/snell-server")
make_notes 5.0.1 6.0.0 6.0.1
make_snell_zip 6.0.1 6.0.1
reset_logs; touch "$work/unhealthy"
if update_programs > "$work/out" 2>&1; then fail 'unhealthy snell accepted'; fi
[[ $(sha256 "$SRM_ROOT/snell/v6/snell-server") == "$snell6" && $(cat "$SRM_ROOT/snell/v6/version") == 6.0.0 ]] || fail 'snell rollback'
[[ $(grep -cx 'restart srm-snell@5000000000000001.service' "$work/systemctl") == 2 ]] || fail 'snell restarted again after rollback'
echo 'PASS a failed health check after the Snell restart puts the previous snell-server back'

make_snell_zip 6.0.1 5.0.0
reset_logs
if update_programs > "$work/out" 2>&1; then fail 'snell reporting another version accepted'; fi
[[ $(sha256 "$SRM_ROOT/snell/v6/snell-server") == "$snell6" && ! -e $work/systemctl ]] || fail 'version check gate'
make_notes 5.0.1 6.0.0
reset_logs
main update snell --yes > "$work/out" 2>&1 || fail 'up-to-date snell'
[[ ! -e $work/systemctl ]] && grep -q 'Snell v6 已是最新版本 6.0.0' "$work/out" || fail 'up-to-date snell restarted'
echo 'PASS a snell-server that reports another version is not installed; up to date means no restart'

# With sing-box stopped the nodes are down: the build is swapped, nothing restarts.
make_notes 5.0.1 6.0.1
make_snell_zip 6.0.1 6.0.1
reset_logs; touch "$work/stopped"
update_programs > "$work/out" 2>&1 || { cat "$work/out"; fail 'snell update with the service stopped'; }
[[ $(cat "$SRM_ROOT/snell/v6/version") == 6.0.1 ]] && grep -q '不需要重启' "$work/out" || fail 'stopped: swapped'
if grep -q '^restart ' "$work/systemctl"; then fail 'stopped service restarted by the update'; fi
rm -f "$work/stopped"
echo 'PASS updating Snell while the service is stopped replaces it without starting anything'

# A major version missing from the notes fails alone: v6 is still checked and updated.
make_notes 6.0.2
make_snell_zip 6.0.2 6.0.2
reset_logs
if main update-check run > "$work/out" 2>&1; then fail 'check without v5 succeeded'; fi
jq -e '(.items[]|select(.name == "Snell v6")|.latest == "6.0.2") and (.errors == ["Snell v5：没有查到最新版本"])' "$DATA/update-check.json" >/dev/null || fail 'v6 checked without v5'
if update_programs > "$work/out" 2>&1; then fail 'update without v5 succeeded'; fi
[[ $(cat "$SRM_ROOT/snell/v6/version") == 6.0.2 ]] || fail 'v6 updated without v5'
echo 'PASS a major version missing from the release notes does not block the others'

# A damaged cache: the header shows nothing, the update page says so.
printf '{"items":[{"name":' > "$DATA/update-check.json"
[[ -z $(update_hint) ]] || fail 'hint from a damaged cache'
main update-check status > "$work/out" 2>&1 || fail 'status with a damaged cache'
grep -q '检查记录无法读取' "$work/out" && ! grep -q 'jq:' "$work/out" || fail 'damaged cache message'
echo 'PASS a damaged cache shows no hint and no jq error'

# Daily check off and on again, from the menu (5 → 6).
update_check_install() { touch "$work/units-written"; }
make_notes 5.0.1 6.0.2
main update-check run > /dev/null 2>&1 || fail 'check before toggling'
reset_logs
main menu <<< $'5\n6\n0' > "$work/out" 2>&1 || fail 'menu check off'
grep -q '每日检查已关闭' "$work/out" && grep -qx "disable --now $CHECK_UNIT.timer" "$work/systemctl" || { cat "$work/out"; fail 'timer off'; }
[[ -e $DATA/update-check.off && ! -e $DATA/update-check.json && -z $(update_hint) ]] || fail 'off leaves a marker and no stale hint'
main update-check status > "$work/out" 2>&1
grep -q '每日检查：已关闭' "$work/out" || fail 'status off'
main menu <<< $'5\n6\n0' > "$work/out" 2>&1 || fail 'menu check on'
grep -q '每日检查已开启' "$work/out" && grep -qx "enable --now $CHECK_UNIT.timer" "$work/systemctl" && [[ -e $work/units-written && ! -e $DATA/update-check.off ]] || fail 'timer on'
echo 'PASS the daily check turns off and on from the update menu'

# --- script and "all" -------------------------------------------------------------
printf 'original-manager\n' > "$SRM_ROOT/manager.sh"
update_latest() { printf 'update_core() { return 0; }\n' > "$SRM_ROOT/manager.sh"; }
if update_all 2> "$work/err"; then fail 'a new manager that does not load accepted'; fi
[[ $(cat "$SRM_ROOT/manager.sh") == original-manager ]] && grep -q '新脚本无法加载' "$work/err" || fail 'manager restored'
update_latest() { printf 'update_core() { return 1; }\nupdate_programs() { return 0; }\n' > "$SRM_ROOT/manager.sh"; }
if update_all 2> "$work/err"; then fail 'failed sing-box update reported as success'; fi
grep -q 'update_core() { return 1; }' "$SRM_ROOT/manager.sh" && grep -q '没更新的部分保持原版本' "$work/err" || fail 'new manager kept'
if compgen -G "$SRM_ROOT/.update-before.*" > /dev/null; then fail 'manager backup left behind'; fi
echo 'PASS update all reverts only a new script that does not load; a failed sing-box update keeps the new script and fails'
update_latest() { printf 'update_core() { echo core-ran; }\nupdate_programs() { echo programs-ran; }\n' > "$SRM_ROOT/manager.sh"; }
reset_logs
main menu <<< $'5\n1\n1\n0' > "$work/out" 2>&1 || { cat "$work/out"; fail 'menu update all'; }
grep -q core-ran "$work/out" && grep -q programs-ran "$work/out" && grep -qx update_all "$work/locked" || fail 'all runs the new manager updaters'
echo 'PASS menu 5 → 1 → confirm updates the script, then runs the new script'"'"'s sing-box and Snell updaters'
reset_logs
main menu <<< $'5\n4\n0' > "$work/out" 2>&1 || fail 'menu script only'
grep -qx update_latest "$work/locked" && ! grep -q '更新需要重启服务' "$work/out" || fail 'script only needs no confirmation'
echo 'PASS menu 5 → 4 updates only the script, without the restart warning'
