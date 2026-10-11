SRM_VERSION=4.0.0-dev
CORE_VERSION=1.14.1
# The sing-box series srm has verified (1.14): installation and updates stay in it;
# a later series is installed only after the user confirms it in the update menu.
CORE_SERIES=${CORE_VERSION%.*}
SRM_REPO=dodo258/sing-box-reality-manager
SRM_ROOT=/opt/srm
DATA=/var/lib/srm
SERVICE=srm.service
# Daily version check (timer + oneshot service); never downloads or restarts.
CHECK_UNIT=srm-version-check
STATE=$DATA/current/state.json
# Held by every changing operation (with_lock).
SRM_LOCK=/run/lock/srm.lock
CORE=$SRM_ROOT/core/sing-box
ACME=$SRM_ROOT/acme/acme.sh
# Color only for an interactive terminal; NO_COLOR or redirected output disables it.
use_color() { [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; }
err() { printf '错误：%s\n' "$*" >&2; }
msg() { printf '%s\n' "$*"; }
ask() {
    local prompt=$1 default=${2:-} answer
    printf '%s%s：' "$prompt" "${default:+ [$default]}" >&2
    IFS= read -r answer || return 1
    [[ $answer != 0 ]] || return 1
    REPLY=${answer:-$default}
}
# Non-interactive values come from command-line options; --yes accepts defaults.
# Callers set assume_yes; optional=1 allows an empty default without asking.
ask_opt() {
    local value=$1 prompt=$2 default=${3:-} optional=${4:-0}
    if [[ -n $value ]]; then REPLY=$value; return 0; fi
    if [[ ${assume_yes:-0} == 1 ]]; then
        [[ -n $default || $optional == 1 ]] || { err "非交互模式缺少参数：$prompt"; return 1; }
        REPLY=$default; return 0
    fi
    ask "$prompt" "$default"
}
# Reads one hidden line into REPLY; a last line without newline still counts.
read_secret() {
    local rc=0
    printf '%s：' "$1" >&2
    IFS= read -rs REPLY || [[ -n $REPLY ]] || rc=1
    printf '\n' >&2
    return "$rc"
}
yesno() { local answer; printf '%s [y/N]：' "$1" >&2; IFS= read -r answer && [[ $answer == y || $answer == Y ]]; }
random_hex() { openssl rand -hex "$1"; }
fetch() { curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error --retry 2 --connect-timeout 15 --max-time 180 "$1" -o "$2"; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
require_root() { [[ $EUID == 0 ]] || { err '请以 root 运行。'; return 1; }; }
require_linux() {
    [[ $(uname -s) == Linux && $EUID == 0 ]] || { err '安装和管理需在 Linux 上以 root 运行。'; return 1; }
    [[ -d /run/systemd/system ]] || { err '需要 systemd。'; return 1; }
    [[ -r /etc/os-release ]] || return 1
    local ID
    . /etc/os-release
    case $ID in debian|ubuntu) ;; *) err '只支持 Debian/Ubuntu。'; return 1;; esac
}
with_lock() (
    require_linux || exit 1
    command -v flock >/dev/null || { err '缺少 flock（util-linux）。'; exit 1; }
    exec 9>"$SRM_LOCK"
    flock -n 9 || { err '另一项操作尚未结束，请稍后重试。'; exit 1; }
    recover_pending || exit 1
    "$@"
)
ensure_dependencies() {
    local pkg missing=()
    for pkg in ca-certificates curl jq openssl qrencode iproute2 util-linux tar; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q '^install ok installed$' || missing+=("$pkg")
    done
    if (( ${#missing[@]} )); then
        msg "安装缺失依赖：${missing[*]}"
        apt-get update && DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get install -y --no-install-recommends "${missing[@]}" || return 1
    fi
    for pkg in curl jq openssl qrencode ss flock tar; do command -v "$pkg" >/dev/null || return 1; done
}
core_arch() {
    case $(uname -m) in x86_64) printf 'amd64\n';; aarch64|arm64) printf 'arm64\n';; *) err '只支持 amd64/arm64。'; return 1;; esac
}
# Version order for sing-box and the Snell server: 1.14.1 < 1.14.3; pre-releases (alpha,
# b/beta, rc; a bare "rc" counts as rc1) sort before their release.
version_latest() {
    printf '%s\n' "$@" | awk '{
        base = $0; stage = 3; num = 0
        if (match($0, /-?(alpha|beta|b|rc)\.?[0-9]*$/)) {
            suf = substr($0, RSTART); base = substr($0, 1, RSTART - 1)
            sub(/^-/, "", suf); sub(/\./, "", suf)
            if (suf ~ /^alpha/) stage = 0; else if (suf ~ /^b/) stage = 1; else stage = 2
            sub(/^[a-z]+/, "", suf); num = (suf == "" ? 1 : suf + 0)
        }
        split(base, p, ".")
        printf "%09d %09d %09d %d %09d %s\n", p[1], p[2], p[3], stage, num, $0
    }' | sort | tail -n 1 | awk '{print $NF}'
}
# True when NEW is a later version than OLD; an unreadable OLD counts as older.
version_newer() {
    local new=$1 old=$2 pattern='^[0-9]+\.[0-9]+\.[0-9]+'
    [[ $new =~ $pattern ]] || return 1
    [[ $old =~ $pattern ]] || return 0
    [[ $new != "$old" && $(version_latest "$new" "$old") == "$new" ]]
}
# "VERSION SHA256" of a Release API answer (FILE) that is a stable release carrying
# this machine's Linux archive, the SHA256 being the asset digest GitHub reports.
# Drafts, pre-releases and tags with a suffix are refused.
core_release_line() {
    local arch
    arch=$(core_arch) || return 1
    jq -r --arg arch "$arch" 'select(.draft == false and .prerelease == false and (.tag_name|test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))
      | (.tag_name|ltrimstr("v")) as $v | .assets[]? | select(.name == "sing-box-\($v)-linux-\($arch).tar.gz")
      | select(.digest|test("^sha256:[a-f0-9]{64}$")) | "\($v) \(.digest|ltrimstr("sha256:"))"' "$1" 2>/dev/null |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+ [a-f0-9]{64}$' | head -n 1
}
# Stable sing-box releases, one per line:
#   verified VERSION SHA256  the newest of CORE_SERIES, the series srm is tested with;
#   newer VERSION SHA256     the newest of all, when it is of a later series (srm has
#                            not verified it: a new series may change the config format).
# /releases/latest skips drafts and pre-releases. When it is of a later series, the
# series' stable tags (git matching-refs returns every tag starting with the prefix,
# https://docs.github.com/en/rest/git/refs#list-matching-references) are tried newest
# first against their own Release. Fails when no verified release was found.
core_releases() {
    local tmp latest='' line='' tag tags series=${CORE_SERIES//./\\.}
    tmp=$(mktemp) || return 1
    # No answer at all (offline, rate limited): the other lookups would only wait too.
    if ! fetch https://api.github.com/repos/SagerNet/sing-box/releases/latest "$tmp"; then
        rm -f "$tmp"; err '没有查到 sing-box 的稳定版发布信息。'; return 1
    fi
    latest=$(core_release_line "$tmp") || latest=''
    if [[ $latest == "$CORE_SERIES".* ]]; then
        line=$latest
    else
        [[ -z $latest ]] || ! version_newer "${latest%.*}.0" "$CORE_SERIES.0" || printf 'newer %s\n' "$latest"
        if fetch "https://api.github.com/repos/SagerNet/sing-box/git/matching-refs/tags/v$CORE_SERIES." "$tmp"; then
            tags=$(jq -r '.[]?.ref|ltrimstr("refs/tags/v")' "$tmp" 2>/dev/null | grep -E "^$series\.[0-9]+$" | sort -t . -k 3,3nr | head -n 3) || tags=''
            for tag in $tags; do
                fetch "https://api.github.com/repos/SagerNet/sing-box/releases/tags/v$tag" "$tmp" && line=$(core_release_line "$tmp") || line=''
                [[ ${line%% *} != "$tag" ]] || break
                line=''
            done
        fi
    fi
    rm -f "$tmp"
    [[ -n $line ]] || { err "没有查到 sing-box $CORE_SERIES 系列的稳定版发布信息（或缺少 SHA256）。"; return 1; }
    printf 'verified %s\n' "$line"
}
# "VERSION SHA256" of the newest stable release of CORE_SERIES.
core_release() {
    local out
    out=$(core_releases) || return 1
    awk '$1 == "verified" {print $2, $3}' <<< "$out"
}
# The release this script was tested with, pinned by archive SHA256.
core_pinned_hash() {
    case $(core_arch) in
      amd64) printf '12cb2816b52febb356f6a885b740cc8758c3f30b8ae0ca8edba80f0d2d35343f\n';;
      arm64) printf '6060b42fa84c5dcaeae1799af7f61b0f1ae4855d9d5ddc9e02baba17154b3ae2\n';;
      *) return 1;;
    esac
}
core_fetch() {
    local target=$1 version=$2 hash=$3 arch asset tmp
    arch=$(core_arch) || return 1
    asset=sing-box-$version-linux-$arch
    tmp=$(mktemp -d) || return 1
    if [[ $hash =~ ^[a-f0-9]{64}$ ]] &&
       fetch "https://github.com/SagerNet/sing-box/releases/download/v$version/$asset.tar.gz" "$tmp/core.tar.gz" &&
       [[ $(sha256 "$tmp/core.tar.gz") == "$hash" ]] &&
       tar -xzf "$tmp/core.tar.gz" -C "$tmp" "$asset/sing-box" &&
       install -m 755 "$tmp/$asset/sing-box" "$target"; then
        rm -rf "$tmp"; return 0
    fi
    rm -rf "$tmp"; err "sing-box $version 下载或 SHA256 校验失败。"; return 1
}
# Installation takes the newest stable release of CORE_SERIES (never a later series);
# without the Release API the tested one.
core_download() {
    local release
    if release=$(core_release); then core_fetch "$1" "${release% *}" "${release#* }"; return; fi
    msg "改为安装本脚本测试过的 sing-box $CORE_VERSION。"
    core_fetch "$1" "$CORE_VERSION" "$(core_pinned_hash)"
}
# Public address of this server as the internet sees it (IPv4 first) and its country
# code, looked up once when deploying; viewing nodes never needs it again.
PUBLIC_IP=''
PUBLIC_LOC=''
detect_public_ip() {
    [[ -z $PUBLIC_IP ]] || return 0
    local family out ip
    for family in 4 6; do
        out=$(curl "-$family" --proto '=https' --fail --silent --connect-timeout 5 --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null) || continue
        ip=$(sed -n 's/^ip=//p' <<< "$out" | head -n 1)
        valid_ip "$ip" || continue
        PUBLIC_IP=$ip
        PUBLIC_LOC=$(sed -n 's/^loc=//p' <<< "$out" | head -n 1)
        # XX: unknown, T1: Tor.
        [[ $PUBLIC_LOC =~ ^[A-Z]{2}$ && $PUBLIC_LOC != XX && $PUBLIC_LOC != T1 ]] || PUBLIC_LOC=''
        return 0
    done
    return 1
}
resolve_domain() { getent ahosts "$1" 2>/dev/null | awk '{print $1}' | sort -u; }
# Checked before any certificate request, so a wrong DNS record is reported at once
# instead of as a failed Let's Encrypt validation. HOST is the node's address.
domain_resolves_here() {
    local domain=$1 host=$2 addresses mine address
    msg "检查域名 $domain 的解析…"
    addresses=$(resolve_domain "$domain") || addresses=''
    if [[ ! $host =~ ^[0-9.]+$ && $host != *:* ]]; then
        # A domain as the node address and no public IP to compare with (NAT, no
        # route to the lookup): nothing to check against, so it is not blocked.
        if ! detect_public_ip; then msg '没有查到本机公网 IP，无法确认域名解析，跳过检查。'; return 0; fi
        host=$PUBLIC_IP
    fi
    if [[ -z $addresses ]]; then
        err "域名 $domain 还没有解析记录：请在域名服务商添加 A 记录指向本机 $host，生效后再试。"; return 1
    fi
    mine=$(printf '%s\n' "$host" "$PUBLIC_IP"; ip -o addr show 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4}')
    while IFS= read -r address; do
        grep -Fxq -- "$address" <<< "$mine" && return 0
    done <<< "$addresses"
    err "域名 $domain 解析到 $(paste -sd ' ' - <<< "$addresses")，不是本机 $host：请把 A 记录改成本机 IP（Cloudflare 要关掉代理，设为「仅 DNS」），生效后再试。"
    return 1
}
port_free() {
    local port=$1 exclude=${2:-} output
    valid_port "$port" || return 1
    if [[ -f $STATE ]]; then
        jq -e --arg id "$exclude" --argjson port "$port" 'any(.nodes[]; (.id!=$id and .port==$port) or .local_port==$port or
          (.hop != null and .hop.start <= $port and $port <= .hop.end))' "$STATE" >/dev/null && return 1
    fi
    # The port hopping range of the node being deployed ("START END", a local of node_deploy).
    if [[ -n ${hop_range:-} ]]; then
        local start end
        read -r start end <<< "$hop_range"
        (( port < start || port > end )) || return 1
    fi
    output=$(ss -H -lntu "sport = :$port") || return 1
    [[ -z $output ]]
}
choose_port() {
    local candidate i
    for ((i=0; i<100; i++)); do
        candidate=$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')
        candidate=$((candidate % 40001 + 10000))
        if port_free "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done
    err '未找到空闲端口。'; return 1
}
