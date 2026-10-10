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
for choice in 1 2; do
    reality_target_select <<< "$choice" > "$work/choice"
    case $choice in 1) [[ $REPLY == www.ctrip.com ]] || exit 1;; 2) [[ $REPLY == www.ixigua.com ]] || exit 1;; esac
done
! reality_target_select <<< 0 > /dev/null || exit 1
! reality_target_select <<< 3 > /dev/null 2>&1 || exit 1
! reality_target_select </dev/null > /dev/null 2>&1 || exit 1
echo 'PASS Reality target selection and cancellation'
# Model OpenSSL output and assert that all verification options are passed.
timeout() {
    [[ $* == *'-verify_hostname www.ctrip.com -verify_return_error'* ]] || return 1
    printf 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384\n'
    [[ $probe_mode == no_h2 ]] || printf 'ALPN protocol: h2\n'
    if [[ $probe_mode == bad_cert ]]; then printf 'Verify return code: 62 (hostname mismatch)\n'
    else printf 'Verify return code: 0 (ok)\n'; fi
    [[ $probe_mode != timeout ]] || return 124
}
probe_mode=ok; reality_target_check www.ctrip.com >/dev/null
for probe_mode in no_h2 bad_cert timeout; do ! reality_target_check www.ctrip.com >/dev/null 2>&1 || exit 1; done
echo 'PASS Reality preflight rejects missing HTTP/2, bad certificate and timeout'
certificate_status > "$work/status"
grep -q '目前没有' "$work/status"
jq -n '{nodes:[{type:"vless",sni:"www.ctrip.com"}]}' > "$STATE"
certificate_status > "$work/status"
grep -q '目前没有' "$work/status"
echo 'PASS no TLS certificate required for an empty installation or Reality-only nodes'
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$DATA/certs/test.example.com/active/key.pem" \
    -out "$DATA/certs/test.example.com/active/fullchain.pem" -days 2 \
    -subj /CN=test.example.com -addext subjectAltName=DNS:test.example.com >/dev/null 2>&1
jq -n '{nodes:[{type:"anytls",sni:"test.example.com",cert_dir:"/certs"},{type:"hysteria2",sni:"test.example.com",cert_dir:"/certs"},{type:"vless",sni:"www.ctrip.com"}]}' > "$STATE"
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
