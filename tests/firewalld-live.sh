#!/usr/bin/env bash
# Run only in disposable CI with firewalld installed but stopped, inside a separate
# mount namespace: uninstalling while firewalld is stopped removes srm's permanent
# rules with the real firewall-offline-cmd and keeps the existing ones.
set -Eeuo pipefail
source "$(dirname -- "$0")/support/guard.sh"
need_ci_root
command -v firewall-offline-cmd >/dev/null || skip_or_fail "${0##*/}：需要先装 firewalld（不启动）"
[[ $(readlink /proc/self/ns/mnt) != "$(readlink /proc/1/ns/mnt)" ]] || exit 1
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
mount --make-rprivate /
cp -a /etc/firewalld "$work/etc-firewalld"
mount --bind "$work/etc-firewalld" /etc/firewalld
trap 'umount /etc/firewalld; rm -rf "$work"' EXIT
rc=0
firewall-cmd --state >/dev/null 2>&1 || rc=$?
[[ $rc == 252 ]] || { echo "FAIL firewalld is not stopped (firewall-cmd --state exited $rc)"; exit 1; }
zone=$(firewall-offline-cmd --get-default-zone)
firewall-offline-cmd --zone="$zone" --add-port=23999/tcp >/dev/null
firewall-offline-cmd --zone="$zone" --add-port=24000/udp >/dev/null
SRM_ROOT=$work/root
DATA=$work/data
mkdir -p "$SRM_ROOT" "$DATA/firewall"
touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
# srm opened 24000/udp (both scopes) and only the runtime 23999/tcp (the permanent one was there).
for scope in runtime permanent; do
    printf 'firewalld\t%s\t%s\t24000\tudp\n' "$zone" "$scope" > "$DATA/firewall/firewalld-$zone-$scope-24000-udp"
done
printf 'firewalld\t%s\truntime\t23999\ttcp\n' "$zone" > "$DATA/firewall/firewalld-$zone-runtime-23999-tcp"
firewall_clear || { echo 'FAIL uninstalling failed while firewalld was stopped'; exit 1; }
[[ -z $(ls "$DATA/firewall") ]] || { echo 'FAIL records left'; exit 1; }
rc=0
output=$(firewall-offline-cmd --zone="$zone" --query-port=24000/udp) || rc=$?
[[ $rc == 1 && $output == no ]] || { echo "FAIL srm's permanent rule is still there ($rc $output)"; exit 1; }
[[ $(firewall-offline-cmd --zone="$zone" --query-port=23999/tcp) == yes ]] || { echo 'FAIL the existing permanent rule was removed'; exit 1; }
echo 'PASS real firewall-offline-cmd: uninstalling while firewalld is stopped removes only the permanent rules srm opened'
