#!/usr/bin/env bash
# Opening the menu and viewing nodes must never reach the network.
# curl/wget are replaced by recorders; system commands by local fixtures.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
SRM_ROOT=$work/root
DATA=$work/data
STATE=$DATA/current/state.json
mkdir -p "$SRM_ROOT" "$DATA/current" "$work/bin"
for tool in curl wget; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/network-calls"\nexit 1\n' "$tool" "$work" > "$work/bin/$tool"
done
printf '#!/usr/bin/env bash\ncat > /dev/null\necho "[QR]"\n' > "$work/bin/qrencode"
chmod 755 "$work/bin/"*
export PATH="$work/bin:$PATH"
require_linux() { return 0; }
# The real lock needs flock and /run/lock; it performs no network access itself.
with_lock() { "$@"; }
systemctl() { case $1 in is-active|is-enabled) return 3;; *) printf 'systemctl %s\n' "$*";; esac; }
journalctl() { printf 'journal fixture\n'; }
sysctl() { printf 'net.ipv4.tcp_congestion_control = cubic\n'; }

# Not installed yet: the header and an empty node list still work offline.
main menu <<< $'2\n0' > "$work/fresh" 2>&1
grep -q '未部署' "$work/fresh"
grep -q '尚无节点' "$work/fresh"
[[ ! -e $work/network-calls ]] || { cat "$work/network-calls"; exit 1; }
echo 'PASS menu on a fresh machine opens without network access'

touch "$SRM_ROOT/.srm-owned" "$DATA/.srm-owned"
jq -n '{schema:1,nodes:[
 {id:"1111111111111111",name:"r",type:"vless",enabled:true,host:"192.0.2.1",port:18101,sni:"www.ctrip.com",uuid:"0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a5b",private_key:"private",public_key:"public",short_id:"0123456789abcdef"},
 {id:"2222222222222222",name:"a",type:"anytls",enabled:true,host:"192.0.2.1",port:18102,sni:"test.example.com",password:"password",cert_dir:"/nonexistent"},
 {id:"3333333333333333",name:"h",type:"hysteria2",enabled:false,host:"192.0.2.1",port:18103,sni:"test.example.com",password:"password",cert_dir:"/nonexistent"}
],policies:[{name:"N",mode:"dns",domains:["netflix.com"]}],unlock_dns:"192.0.2.53",egress:null}' > "$STATE"
# Every read-only page: node link, QR, details, client outbound, routing, status
# and logs, update page, BBR status, certificates; then exit.
input=$'2\n1\n2\n2\n1\n3\n2\n1\n1\n2\n2\n4\n3\n1\n4\ny\n5\n0\n6\nn\n8\n0\n0'
main <<< "$input" > "$work/menu" 2>&1
[[ ! -e $work/network-calls ]] || { cat "$work/network-calls"; exit 1; }
echo 'PASS opening the menu and every read-only page makes no curl or wget call'
[[ $(grep -c 'sing-box-reality-manager (srm)' "$work/menu") == 10 ]] || exit 1
grep -q 'VLESS Reality · AnyTLS · Hysteria2' "$work/menu"
grep -q '节点：2 / 3' "$work/menu"
echo 'PASS menu stays open and returns after each action until 0'
grep -q 'vless://0f2a6c1e-3b4d-4e5f-8a9b-0c1d2e3f4a5b@192.0.2.1:18101' "$work/menu"
grep -q '\[QR\]' "$work/menu"
grep -q '"type": "anytls"' "$work/menu"
grep -q 'journal fixture' "$work/menu"
grep -q '1 条平台规则' "$work/menu"
! grep -q '"private_key"' "$work/menu" || exit 1
! grep -q $'\033' "$work/menu" || exit 1
echo 'PASS pages render locally; details hide secrets; no color when not a terminal'
