# Tests needing a sing-box core or root skip on a developer machine and fail in CI,
# so `for t in tests/*.sh` works locally while CI still runs everything.
skip_or_fail() {
    if [[ ${GITHUB_ACTIONS:-} == true ]]; then printf 'FAIL %s\n' "$*"; exit 1; fi
    printf 'SKIP %s\n' "$*"; exit 0
}
need_core() { [[ -n ${TEST_CORE:-} ]] || skip_or_fail "${0##*/}：需要 TEST_CORE 指向 sing-box 核心（CI 会下载）"; }
need_ci_root() { [[ ${GITHUB_ACTIONS:-} == true && $EUID == 0 && $(uname -s) == Linux ]] || skip_or_fail "${0##*/}：只在 CI 的一次性 Linux 环境以 root 运行"; }
# Private coexistence-server tests run only when explicitly pointed at a workspace.
need_workspace() { [[ -n ${TEST_WORKSPACE:-} ]] || { printf 'SKIP %s：需要 TEST_WORKSPACE（授权测试服务器）\n' "${0##*/}"; exit 0; }; }
