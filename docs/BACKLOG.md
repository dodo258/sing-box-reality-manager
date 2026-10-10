# 待办

主人用一句话派活，agent 记到这里，再由后台调度器 agentq 按 `agent-task` 技能做完、测试通过后合并。每条写清：要什么、怎样算做完（验收标准）、涉及哪些页面或文件（知道的话）。

## 待做

从上往下做。正在做的条目后面标「（进行中：分支名 时间）」。

- [ ] v4 Snell v6（可选 v5）+ ShadowTLS v3 —— 属于 `docs/specs/2026-10-10-v4-rewrite.md`「Snell + ShadowTLS」一节：官方 `snell-server` 默认 v6（当前官方最新是 v6.0.0rc2，没有正式版）、可选 v5，v6 的 `mode` 默认 `default`、可选 `unshaped`；v6 的服务端配置项和 Surge 配置行参数用下载到的二进制和 Surge 官方文档实测确认，不凭猜，出处写进代码注释。作为独立服务 `srm-snell@<节点id>`，只监听 127.0.0.1；sing-box 的 shadowtls inbound `detour` 到 direct inbound，用 `override_address`/`override_port` 转发到 snell。先实测这条链路，跑不通就改用独立的 shadow-tls 二进制，并把原因写进 DECISIONS。输出能直接粘进 Surge 的配置行，另附 mihomo 写法。卸载、状态、日志、健康检查、防火墙同步都要覆盖 snell 服务。验收：CI 集成测试里 snell-server 起得来，ShadowTLS 端口握手成功（用 sing-box 的 shadowtls 客户端，或 mihomo 的 snell+shadow-tls 客户端端到端连通，择可行者）；v5、v6 两种 Surge 配置行格式都有单元测试；CI 全绿。
- [ ] v4 核心更新：后台只检查、菜单提示、手动更新 —— 属于 `docs/specs/2026-10-10-v4-rewrite.md`「更新」一节。主人定：更新要重启会断网，不自动更新。每日 systemd timer 只查 sing-box（GitHub Release 最新稳定版）和 snell-server（跟随节点的大版本，默认 v6；无正式版时跟最新 beta/RC，有正式版后只跟正式版；从官方发布说明解析）的版本号，写进 `/var/lib/srm/update-check.json`，不下载不重启；菜单状态栏读这个文件（不联网）提示可更新；在菜单「更新」里选「全部 / 只 sing-box / 只 Snell / 只脚本」手动更新，也能在这里关掉每日检查，先提示「会断开几秒」再选确认（命令行对应 `srm update [core|snell|script] [--yes]`、`srm update-check on/off/status`），sing-box 用附件 digest 校验、新二进制先 `sing-box check`，snell 下载后运行核对版本，重启后健康检查失败自动回滚。验收：测试证明更新和检查开关都能只靠菜单选择完成；测试证明 timer 的检查路径不调用 systemctl restart、不替换任何文件；覆盖「有新版 → 校验 → 替换 → 健康」「校验失败不替换」「健康检查失败回滚」「已是最新不重启」「sing-box 跳过 pre-release」「snell v6 无正式版时取最新 RC、有正式版后不再取 RC」「菜单提示只读缓存不联网」；timer 在 CI 的真实 systemd 里注册成功；CI 全绿。
- [ ] v4 快速部署流程与客户端配置片段 —— 属于 `docs/specs/2026-10-10-v4-rewrite.md`「部署流程」一节：按方案「交互原则」：安装完成后直接进入菜单，没有节点时直接进快速部署（VLESS Reality 推荐首选，回车即部署；Hysteria2；Snell+ShadowTLS；AnyTLS；更多协议），每个协议最多问 2 个带默认值的问题；只有需要证书的协议才问域名，并先检查域名是否解析到本机；部署完一屏给出链接、本地二维码、安全组放行提示，以及按客户端分好的配置片段（Surge / Clash Meta / sing-box / Shadowrocket / v2rayN，只给该协议支持的）。`srm add <协议> [--port] [--domain] [--name] [--yes] [--json]` 输出同样的内容。整个部署过程只用数字选择和回车，唯一手填的是域名，且可以选「没有域名，换一个协议」；界面文案不出现「运行 srm xxx」。验收：测试证明全程回车能部署出 Reality 节点；`grep` 证明 lib/ 里面向用户的提示没有「运行 srm」「执行 srm」这类说法；域名没解析到本机时在申请证书前就提示；`--json` 输出可被 jq 解析；`docs/menu-preview.txt` 更新为新菜单；CI 全绿。
- [ ] v4 旧版迁移（菜单引导，命令行 srm migrate）—— 属于 `docs/specs/2026-10-10-v4-rewrite.md`「迁移」一节：从 `/etc/v2ray-agent` 读取 v3 的 sing-box 节点（包括 `30_`–`33_` 多实例文件、密钥、证书）和 `snell-shadowtls/nodes/*.env`，v4 支持的协议都迁过来，生成 schema 2 的 state；检测到 `/etc/v2ray-agent` 时，打开菜单第一屏就提示「发现旧版节点，要迁移过来吗？」，选是先展示能迁和不能迁的内容，再「确认 / 返回」（默认返回）；命令行 `srm migrate` 默认 dry-run，列出能迁移和不能迁移的内容（Xray 核心的节点、网站、订阅）；`--apply` 时停旧服务，由新服务接管原端口，健康检查失败就恢复旧服务；旧 crontab 行注释掉不删；`/etc/v2ray-agent` 一个字节都不改。验收：测试证明只靠菜单选择就能完成迁移；`tests/fixtures/v3/` 放至少 4 份脱敏的 v3 配置样本（单 Reality、Reality+AnyTLS+Hy2、多实例、Snell+ShadowTLS），断言迁移结果；测试证明 `--apply` 失败时旧服务被恢复；CI 全绿。

## 等主人拍板

- [ ] v4 切换发布 —— 前面 7 条合并、主人验收后才做。内容：
  - 根目录 `install.sh` 换成 v4 引导：从 Release 下载 `srm` 和 `SHA256SUMS`，校验后安装；收到 v3 定时任务参数 `RenewTLS`、`UpdateGeo`、`WebsitePublish` 时输出一行迁移提示并退出 0。
  - v3 脚本冻结到 `legacy/v3` 分支，加 tag `v3.8.4`。
  - 删除 `fodder/` 和过时的 documents。
  - 重写中英文 README，写明功能变化、迁移方法和旧版安装命令。
  - `create_release.yml` 改成按 tag 触发、上传 dist 附件，并去掉删除旧 release 的逻辑。
  - 发布 v4.0.0。

  需要主人决定：是否发布。推荐：前面 7 条验收通过后发布。注意：这会改变 main 分支 `install.sh` 的行为，影响所有新安装的人，必须等主人确认。

## 以后再说

## 已完成

- [x] v4 补齐 sing-box 其余服务端协议 —— 2026-10-10 合并，提交 95e8a03（PR #5）。注册表新增 Shadowsocks 2022、TUIC v5、VLESS TLS（tcp Vision / ws / grpc / httpupgrade）、Trojan、VMess（TLS+ws）、Naive、Hysteria v1；每种有校验、服务端配置、分享链接、sing-box / Clash Meta / Surge 片段（客户端支持的才给）和防火墙传输层（SS 同端口 TCP+UDP）。TUIC、Hysteria v1、Hysteria2 没有域名时默认自签证书，客户端按指纹校验。验收：在 GitHub 打开 PR #5 看 CI「srm checks」全绿，日志里 tests/traffic.sh 有每个协议「sing-box client fetches the local HTTP page through …」和 mihomo 的 PASS（Naive 也是真实 sing-box 客户端走通）；本机 `bash tests/clients.sh` 15 项 PASS。菜单里试：「1. 部署节点」能看到 10 种协议；「2. 节点管理 → 选节点 → 4. 客户端配置」一屏给出 sing-box / Clash Meta / Surge 写法。没做：Surge 行只有格式测试（没有 Linux 客户端）；各协议的 UDP 转发没单独测；部署菜单还没按「需要域名」分组（属于「快速部署」那条）。
- [x] v4 多节点与节点级分流 —— 2026-10-10 合并，提交 8fb22c4（PR #4）。state schema 2（schema 1 在第一次修改或应用配置时自动迁移，节点不变）；分流规则可限定到指定节点；同一协议可部署多个节点（默认名自动编号）；端口 1–65535（随机仍 10000–50000），TCP 节点不能占用证书续期验证端口。验收：在 GitHub 打开 PR #4 看 CI「srm checks」全绿；本机 `bash tests/state.sh` 全部 PASS；装了 sing-box 1.14.1 的话用 `TEST_CORE=<路径> bash tests/local.sh`，能看到「three nodes of each protocol…」「a rule limited to one node…」两条 PASS。菜单里试：「3. 流媒体分流 → 4. 添加/替换平台规则」，有 2 个以上节点时会列出节点让你按序号选（回车 = 全部）。没做：DNS 规则限定节点的真实 DNS 流量测试（只验了生成结果和 `sing-box check`）；方案里的节点 `transport` 字段放到「补齐其余协议」那条。
- [x] v4 骨架：搬入 dodo-sbox 架构和协议注册表 —— 2026-10-10 合并，提交 e843254（PR #3）。验收：在 GitHub 打开 PR #3 看 CI「srm checks」全绿（65 项 PASS）；本机 `bash srm.sh --help` 列出全部子命令，`bash tests/menu.sh`、`bash tests/protocols.sh`、`bash tests/cli.sh` 都输出 PASS。按 main 上主人新定的规则：去掉了 dodo-sbox 的每日自动更新，所有功能都有菜单项。没做：真实 VPS 上的完整部署（等「切换发布」前验收）。
