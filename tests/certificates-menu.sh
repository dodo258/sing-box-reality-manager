#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
source ./srm.sh
TEST_OPENSSL=${TEST_OPENSSL:-$(command -v openssl)}
openssl() { "$TEST_OPENSSL" "$@"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
SRM_ROOT=$work/root
DATA=$work/data
STATE=$work/state.json
mkdir -p "$SRM_ROOT" "$DATA/certs/test.example.com/active"
systemctl() {
    case $1 in is-enabled) echo enabled;; is-active) echo active;; list-timers) echo 'next daily certificate check';; *) return 1;; esac
}
# Model OpenSSL and curl for every built-in candidate and assert that all
# verification options are passed. Per domain: the OpenSSL result (ok, no_h2,
# bad_cert, timeout), whether /cdn-cgi/trace answers (Cloudflare) and the seconds
# curl reports until the TLS handshake finished.
probe_mode() { case $1 in www.python.org) echo bad_cert;; www.cisco.com) echo no_h2;; www.mysql.com) echo timeout;; *) echo ok;; esac; }
timeout() {
    local args="$*" domain
    domain=${args##*-verify_hostname }; domain=${domain%% *}
    [[ $1 == 10 && $args == *"-connect $domain:443 -servername $domain -tls1_3 -alpn h2 -verify_hostname $domain -verify_return_error"* ]] || return 1
    printf 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384\n'
    [[ $(probe_mode "$domain") == no_h2 ]] || printf 'ALPN protocol: h2\n'
    if [[ $(probe_mode "$domain") == bad_cert ]]; then printf 'Verify return code: 62 (hostname mismatch)\n'
    else printf 'Verify return code: 0 (ok)\n'; fi
    [[ $(probe_mode "$domain") != timeout ]] || return 124
}
curl() {
    local url=${*: -1} args="$*" domain
    domain=${url#https://}; domain=${domain%%/*}
    [[ $url == "https://$domain/cdn-cgi/trace" && $args == *"--proto =https"* && $args == *'--max-time '* ]] || return 1
    case $domain in
      www.jetbrains.com) printf 'fl=1\nh=%s\nvisit_scheme=https\ntls=TLSv1.3\n\n0.020000' "$domain";;
      www.oracle.com) printf '<html>not found</html>\n0.031000';;
      www.adobe.com) printf '\n0.000000'; return 28;;
      www.mozilla.org) printf 'not found\n0.090500';;
      *) printf 'not found\n0.250000';;
    esac
}
REPLY=''; reality_target_check www.oracle.com > /dev/null && [[ $REPLY == 31 ]] || exit 1
for domain in www.python.org www.cisco.com www.mysql.com www.adobe.com; do
    if reality_target_check "$domain" > /dev/null 2>&1; then echo "FAIL $domain passed the check"; exit 1; fi
done
rc=0; reality_target_check www.jetbrains.com > /dev/null || rc=$?; [[ $rc == 2 ]] || exit 1
echo 'PASS target check: TLS 1.3, HTTP/2, a valid certificate and an HTTPS answer; handshake time from curl; Cloudflare is reported apart'
# Failed candidates and the one behind Cloudflare are left out; the fastest comes first.
reality_targets_rank > "$work/ranked" 2>/dev/null
[[ $(head -n 3 "$work/ranked" | tr '\n' '|') == '31 www.oracle.com|90 www.mozilla.org|250 addons.mozilla.org|' ]] || { cat "$work/ranked"; exit 1; }
[[ $(wc -l < "$work/ranked" | tr -d ' ') == $(( $(wc -w <<< "$REALITY_TARGETS") - 5 )) ]] || exit 1
if grep -qE 'www\.(jetbrains|python|cisco|mysql|adobe)\.com' "$work/ranked"; then exit 1; fi
sni=''; handshake_target_ready > "$work/out" 2>&1 && [[ $sni == www.oracle.com ]] || { cat "$work/out"; exit 1; }
grep -q '伪装目标：自动选用 www.oracle.com（握手 31 ms' "$work/out" || exit 1
echo 'PASS candidates that fail the check or answer /cdn-cgi/trace (Cloudflare) are never picked; the fastest is'
# The menu: Enter takes the fastest, a number another one, or a typed domain.
reality_target_select www.mysql.com <<< '' > "$work/choice" 2>&1 && [[ $REPLY == www.oracle.com ]] || { cat "$work/choice"; exit 1; }
grep -q '当前：www.mysql.com' "$work/choice" && grep -q '  1. www.oracle.com         握手 31 ms（最快）' "$work/choice" || { cat "$work/choice"; exit 1; }
if grep -qE 'jetbrains|python|cisco' "$work/choice"; then exit 1; fi
reality_target_select <<< 2 > /dev/null 2>&1 && [[ $REPLY == www.mozilla.org ]] || exit 1
custom=$(( $(wc -l < "$work/ranked") + 1 ))
reality_target_select <<< "$custom"$'\n1.2.3.4\nWWW.Example.ORG' > /dev/null 2>&1 && [[ $REPLY == www.example.org ]] || exit 1
if reality_target_select <<< 0 > /dev/null 2>&1; then exit 1; fi
if reality_target_select <<< $'99\n0' > /dev/null 2>&1; then exit 1; fi
if reality_target_select <<< "$custom"$'\n0' > /dev/null 2>&1; then exit 1; fi
if reality_target_select </dev/null > /dev/null 2>&1; then exit 1; fi
echo 'PASS target menu: Enter takes the fastest, a number another, or a typed domain; 0 and EOF go back'
# None passes: the typed domain is the default.
probe_mode() { echo timeout; }
reality_targets_rank > "$work/ranked" 2>/dev/null; [[ ! -s $work/ranked ]] || exit 1
if handshake_target_ready > /dev/null 2>&1; then exit 1; fi
reality_target_select <<< $'\nwww.example.org' > "$work/choice" 2>&1 && [[ $REPLY == www.example.org ]] || exit 1
grep -q '都没有通过检测' "$work/choice" && grep -q '请选择 \[1\]' "$work/choice" || { cat "$work/choice"; exit 1; }
echo 'PASS no candidate passes: deploy stops; the menu offers only a typed domain'
unset -f timeout curl probe_mode
certificate_status > "$work/status"
grep -q '目前没有' "$work/status"
jq -n '{nodes:[{type:"vless",sni:"www.python.org"}]}' > "$STATE"
certificate_status > "$work/status"
grep -q '目前没有' "$work/status"
echo 'PASS no TLS certificate required for an empty installation or Reality-only nodes'
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$DATA/certs/test.example.com/active/key.pem" \
    -out "$DATA/certs/test.example.com/active/fullchain.pem" -days 2 \
    -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com >/dev/null 2>&1
jq -n '{nodes:[{type:"anytls",sni:"test.example.com",cert_dir:"/certs"},{type:"hysteria2",sni:"test.example.com",cert_dir:"/certs"},{type:"vless",sni:"www.python.org"}]}' > "$STATE"
certificate_status > "$work/status"
[[ $(grep -c '^域名：' "$work/status") == 1 ]] || exit 1
grep -q '2 个节点共用' "$work/status"
grep -q '30 天内到期' "$work/status"
grep -q '外部导入' "$work/status"
! grep -q 'PRIVATE KEY' "$work/status" || exit 1
echo 'PASS deduplicated certificate expiry and source display without private keys'
account=$SRM_ROOT/acme-accounts/test.example.com
mkdir -p "$account/test.example.com_ecc" "$account/export"
[[ $(certificate_source test.example.com) == import ]] || exit 1
touch "$account/test.example.com_ecc/test.example.com.conf"
cp "$DATA/certs/test.example.com/active/fullchain.pem" "$account/export/fullchain.pem"
[[ $(certificate_source test.example.com) == acme ]] || exit 1
printf 'import\n' > "$DATA/certs/test.example.com/active/renewal-source"
[[ $(certificate_source test.example.com) == import ]] || exit 1
owned_root() { return 0; }
firewall_renew() { printf 'called\n' >> "$work/renew-called"; return "${renew_rc:-2}"; }
copy_acme_cert() { printf 'copied\n' >> "$work/copy-called"; }
renew_certificates
[[ ! -f $work/renew-called ]] || exit 1
printf 'acme\n' > "$DATA/certs/test.example.com/active/renewal-source"
renew_certificates
[[ $(wc -l < "$work/renew-called" | tr -d ' ') == 1 ]] || exit 1
[[ -f $work/copy-called ]] || exit 1
renew_rc=1
! renew_certificates 2>/dev/null || exit 1
[[ $(wc -l < "$work/copy-called" | tr -d ' ') == 1 ]] || exit 1
echo 'PASS legacy ACME recognition, imported-certificate exclusion and failed renewal preservation'
# An older ACME cert has no marker. Renewal updates the export before activation;
# if activation fails, the old active cert must remain eligible for retry.
mv "$DATA/certs/test.example.com/active/renewal-source" "$work/previous-source"
renew_rc=0
firewall_renew() { printf 'new issued certificate fixture\n' > "$account/export/fullchain.pem"; }
copy_acme_cert() { return 1; }
before_cert=$(sha256 "$DATA/certs/test.example.com/active/fullchain.pem")
! renew_certificates 2>/dev/null || exit 1
[[ $(certificate_source test.example.com) == acme ]] || exit 1
[[ $(sha256 "$DATA/certs/test.example.com/active/fullchain.pem") == "$before_cert" ]] || exit 1
copy_acme_cert() { printf 'retried\n' > "$work/activation-retried"; }
renew_certificates
[[ -f $work/activation-retried ]] || exit 1
echo 'PASS failed activation after legacy renewal remains eligible for the next retry'
mv "$DATA/certs/test.example.com/active/fullchain.pem" "$work/saved.pem"
certificate_status > "$work/status"
grep -q '证书缺失或无法读取' "$work/status"
echo 'PASS missing certificate is visible without crashing the management page'
