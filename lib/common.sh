SRM_VERSION=4.0.0-dev
CORE_VERSION=1.14.1
SRM_REPO=dodo258/sing-box-reality-manager
SRM_ROOT=/opt/srm
DATA=/var/lib/srm
SERVICE=srm.service
# Daily version check (timer + oneshot service); never downloads or restarts.
CHECK_UNIT=srm-version-check
STATE=$DATA/current/state.json
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
    exec 9>/run/lock/srm.lock
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
# Newest stable sing-box (1.14 or later): "VERSION SHA256" of this machine's Linux
# archive, the SHA256 being the asset digest GitHub's Release API reports.
# /releases/latest skips drafts and pre-releases; a payload that is one is refused.
core_release() {
    local tmp arch out=''
    arch=$(core_arch) || return 1
    tmp=$(mktemp) || return 1
    if fetch https://api.github.com/repos/SagerNet/sing-box/releases/latest "$tmp"; then
        out=$(jq -r --arg arch "$arch" 'select(.draft == false and .prerelease == false and (.tag_name|test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))
          | (.tag_name|ltrimstr("v")) as $v | .assets[]? | select(.name == "sing-box-\($v)-linux-\($arch).tar.gz")
          | select(.digest|test("^sha256:[a-f0-9]{64}$")) | "\($v) \(.digest|ltrimstr("sha256:"))"' "$tmp" 2>/dev/null) || out=''
    fi
    rm -f "$tmp"
    [[ $out =~ ^[0-9]+\.[0-9]+\.[0-9]+\ [a-f0-9]{64}$ ]] || { err '没有查到 sing-box 的稳定版发布信息（或缺少 SHA256）。'; return 1; }
    ! version_newer 1.14.0 "${out%% *}" || { err "sing-box ${out%% *} 低于最低支持的 1.14。"; return 1; }
    printf '%s\n' "$out"
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
# Installation takes the newest stable release; without the Release API the tested one.
core_download() {
    local release
    if release=$(core_release); then core_fetch "$1" "${release% *}" "${release#* }"; return; fi
    msg "改为安装本脚本测试过的 sing-box $CORE_VERSION。"
    core_fetch "$1" "$CORE_VERSION" "$(core_pinned_hash)"
}
port_free() {
    local port=$1 exclude=${2:-} output
    valid_port "$port" || return 1
    if [[ -f $STATE ]]; then
        jq -e --arg id "$exclude" --argjson port "$port" 'any(.nodes[]; (.id!=$id and .port==$port) or .local_port==$port)' "$STATE" >/dev/null && return 1
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
