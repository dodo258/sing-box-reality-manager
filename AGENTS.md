# sing-box-reality-manager（srm）

## 项目是什么
公开的 Linux 节点管理脚本（GitHub 10 星，有外部用户在用）：在 VPS 上部署和管理 sing-box 节点。正在从 v3（单文件 14851 行的 `install.sh`，mack-a/v2ray-agent 魔改）重写为 v4，方案见 `docs/specs/2026-10-10-v4-rewrite.md`。

## 技术栈与目录
- Bash + jq，目标系统 Debian / Ubuntu + systemd；只用 sing-box 一个核心。
- `install.sh`：**v3 旧脚本，现网用户的安装和更新入口**。在待办「切换发布」之前不要修改。
- v4 的代码（按方案逐步建）：`lib/*.sh` 模块，`build.sh` 打包成 `dist/srm`，`srm.sh` 开发入口，`tests/*.sh` 测试。
- 参考实现：`~/projects/dodo-sbox-next`（主人的私有项目 dodo-sbox）。可以照抄架构、函数和测试写法，**只读，不要改它**。
- `documents/`、`fodder/`：v3 的文档和网站模板，在「切换发布」时清理。

## 常用命令
- 语法检查：`bash -n lib/*.sh build.sh srm.sh install.sh`
- 构建：`./build.sh`，构建后 `git diff --exit-code dist/` 必须无差异（dist 要提交）。
- 测试：`for t in tests/*.sh; do bash "$t" || exit 1; done`。需要 root、联网或 systemd 的测试只在 CI（GitHub Actions，ubuntu-latest）跑，本机会打印 SKIP 并退出 0；设置 `TEST_CORE=<sing-box 1.14.1 路径>`（和 macOS 上的 `TEST_OPENSSL=<openssl 3 路径>`）可在本机跑真实核心测试；`tests/snell-traffic.sh` 还要 `TEST_SNELL_V6`、`TEST_SNELL_V5`（snell-server 只有 Linux 版，CI 用 `snell_download` 下载）。
- shellcheck：`shellcheck -S warning -s bash dist/srm build.sh srm.sh`（模块之间共用变量，按打包后的整体检查），本机没装就以 CI 为准。

## 约定
- 公开仓库：不提交任何真实服务器 IP、UUID、密钥、域名，测试样本一律脱敏。
- 不碰用户已有的服务、防火墙规则和 `/etc/v2ray-agent`。迁移只读旧目录，旧服务停之前要能恢复。
- 打开菜单和查看节点时不联网；所有 curl 和 wget 都要设超时。
- 改配置一律走「state → 生成配置 → `sing-box check` → 原子切换 → 健康检查 → 失败回滚」，不能直接改线上配置。
- 新手只用菜单选数字，不用敲命令：每个功能都必须有菜单项；界面提示和报错写「在菜单里选 X」，不写「运行 srm xxx」；能给选项和默认值的就不让用户填。命令行子命令只给进阶用户和自动化（见方案「交互原则」）。
- 失败时退出码非 0；输出不是终端或设置了 `NO_COLOR` 时不带颜色。
- 发正式 release、打 tag、改根目录 `install.sh` 的行为都要等主人确认。
- 协议相关的逻辑只写在 `lib/protocols.sh` 的注册表里，其他模块通过 `proto_call`、`proto_jq` 分派；`tests/protocols.sh` 会检查别处不出现协议类型名。
- 改菜单或快速部署的文字时同步 `docs/menu-preview.txt`（`tests/quick.sh` 会核对菜单行）。
- 测试断言写成 `cmd || fail`、`if cmd; then fail; fi` 或 `[[ … ]] || exit 1`：`! cmd` 失败时不会触发 `set -e`，macOS 自带的 bash 3.2 里失败的 `[[ ]]` 也不会。

## 进度与决定
- 当前进度见 PROGRESS.md，历史决定见 DECISIONS.md。
