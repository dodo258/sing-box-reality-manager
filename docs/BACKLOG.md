# 待办

主人用一句话派活，agent 记到这里，再由后台调度器 agentq 按 `agent-task` 技能做完、测试通过后合并。每条写清：要什么、怎样算做完（验收标准）、涉及哪些页面或文件（知道的话）。

## 待做

从上往下做。正在做的条目后面标「（进行中：分支名 时间）」。

- [ ] v4 迁移安全修正：旧版证书续期与多用户 —— 验收 2d6b536（v4 旧版迁移）时发现两处会伤到老用户：（进行中：agent/1010-migrate-safety 2026-10-10 22:08）
  1. `lib/migrate.sh` 的 `migrate_cron` 把 v3 的 `RenewTLS`、`UpdateGeo` 定时任务整行注释掉。但没迁移的 Xray 节点和 v3 网站还在运行，靠 RenewTLS 续证书，注释掉以后最多 90 天证书就会过期。另一方面，不注释的话，v3 续期后会重启自己的服务，可能把已停的旧 sing-box（`dodo258-sing-box`/`sing-box`）拉起来，跟 srm 抢端口。先读 v3 `install.sh` 里 RenewTLS 和 UpdateGeo 实际会重启哪些服务，再定方案。推荐：迁移时 `systemctl disable` 并 `mask` 已被 srm 接管的旧 sing-box 单元（恢复时 unmask），只有在没有剩余的 v3 服务（Xray、nginx 网站）时才注释定时任务；还有剩余服务就保留定时任务，预览里写明原因。
  2. v3 同一个 inbound 有多个用户时，现在只迁第一个，其余用户迁过去后连不上。如果 state 能支持一个节点多个用户，就全部迁过去；不能就在预览里逐个列出不会迁过去的用户（名称或 email），写明「这些用户迁移后将无法连接」，并且这时默认选项是「返回」。
  验收：fixtures 增加「Reality 节点 + Xray 节点 + 网站」「一个节点 3 个用户」两种样本；测试证明：有剩余 v3 服务时 RenewTLS 不被注释，并且旧 sing-box 单元被 mask，v3 续期脚本重启它会失败、不会抢端口；没有剩余服务时才注释；迁移失败的恢复流程会 unmask；多用户要么全部迁移，要么在预览里列出并默认返回；CI 全绿。

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

- [x] v4 旧版迁移（菜单引导，命令行 srm migrate）—— 2026-10-10 合并，提交 2d6b536（PR #9）。服务器上有 `/etc/v2ray-agent` 且还没迁移时，打开 srm 第一屏问「发现旧版节点，要迁移过来吗？」：回车先列出能迁移的节点（端口、密码、密钥、证书原样保留，正在用的客户端不用改）和不能迁移的内容及原因（Reality+gRPC、经 nginx 转发的、socks、分流 / DNS 分流设置、Xray 节点、网站、订阅），再「1. 确认迁移 / 0. 返回」（回车 = 返回）；选「否」后主菜单有「9. 迁移旧版节点」。确认后：先装好 srm、整份配置过 sing-box check，才停止并停用旧服务（dodo258-sing-box、迁走的 Snell 节点的 dodo258-snell-* / dodo258-shadowtls-*），srm 在原端口接管；失败或中断恢复旧服务的运行和自启；crontab 只注释 RenewTLS / UpdateGeo；`/etc/v2ray-agent` 只读。Xray 服务不停（和方案不同，见 DECISIONS.md）。迁移来的域名证书到期前 30 天自动向 Let's Encrypt 重新申请（80、443 都被占时预览会提示没法自动申请）。命令行 `srm migrate` 只预览，`--apply [--yes] [--host]` 执行。验收：在 GitHub 打开 PR #9，CI「srm checks」全绿，日志里有 tests/migrate.sh 的「the 5 v3 samples … give the expected nodes」「the menu alone (Enter, 1) migrates …」「--apply that fails restores the old services …」「clients of v3 with ws early data … fetch a page」，以及 install-live 的「a failed takeover with real systemd starts and enables the old v3 service again」「srm takes over the port of the v3 service with real systemd …」；样本在 `tests/fixtures/v3/`（单 Reality、Reality+AnyTLS+Hy2、多实例、Snell+ShadowTLS、TLS 各协议），菜单样子见 `docs/menu-preview.txt` 末尾。服务器上试：在一台装着 v3 的机器上装好 v4 开发版后输入 srm，按回车看预览，再输入 1。没做：没有在真实 v3 服务器上跑过；Reality 真实流量和真实 Let's Encrypt 重新申请没测；同一端口多个用户只迁第一个，v3 的节点级 DNS 分流要在菜单「3. 流媒体分流」里重设。
- [x] v4 快速部署流程与客户端配置片段 —— 2026-10-10 合并，提交 67054b0（PR #8）。没有节点时打开 `srm` 直接进快速部署（`srm install` 在终端里装完也直接进菜单），菜单第 1 项改成「添加节点 · 快速部署」：1 VLESS Reality（回车即选）/ 2 Hysteria2 / 3 Snell + ShadowTLS / 4 AnyTLS / 5 更多协议（不需要域名的排前面）。只问需要证书的协议的域名（回车 = 没有域名，换一个协议），再加最多 2 个带默认值的问题（协议自己的一题 → 端口 → 节点名取前两个）；公网 IP、握手目标、证书方式、节点名「协议-国家代码」自动定。域名在申请证书前检查是否解析到本机，当场给「重新检查 / 换域名 / 换协议 / 仍然申请（CDN）」。部署完一屏：服务器和端口、云安全组放行提示、分享链接、本地二维码、Surge / Clash Meta / sing-box / Shadowrocket / v2rayN 中该协议支持的几段（节点管理「4. 客户端配置」同一套）。`srm add <协议> [--port] [--domain] [--name] [--yes] [--json]`，`--json` 只在 stdout 输出 JSON。验收：在 GitHub 打开 PR #8，CI「srm checks」全绿，日志里有 tests/quick.sh 11 项 PASS（「a fresh server deploys VLESS Reality from the menu with Enter only…」「a domain that does not resolve here is reported before the certificate request…」「srm add --json prints one parsable object…」）和 install-live 的「the real menu deploys a running VLESS Reality node with Enter only」；菜单样子见 `docs/menu-preview.txt`。服务器上试：卸掉所有节点后输入 srm，连按回车三次部署 Reality，看结果页；再选 1 → 4 AnyTLS，输入一个没解析到本机的域名，看提示。没做：Shadowrocket / v2rayN 实际导入（没有对应环境，按 v2rayN 源码和 App Store 说明定的支持范围）；Naive 是否支持 Shadowrocket 查不到可靠来源，没列。
- [x] v4 核心更新：后台只检查、菜单提示、手动更新 —— 2026-10-10 合并，提交 2413813（PR #7）。每日 `srm-version-check.timer` 只查 sing-box 最新稳定版和 Snell 节点所用大版本的最新构建（v6 无正式版时跟最新 RC，有正式版后只跟正式版），写 `/var/lib/srm/update-check.json`，不下载、不重启；菜单顶部显示「可更新：sing-box a → b，Snell v6 …（选 5 更新）」，只读缓存。菜单「5. 更新」：全部 / 只 sing-box / 只 Snell / 只脚本 / 立即检查 / 开关每日检查，更新前提示断开几秒，「1. 确认更新 / 0. 返回」默认返回。命令行 `srm update [core|snell|script] [--yes]`、`srm update-check [on|off|status|run]`。验收：在 GitHub 打开 PR #7，CI「srm checks」全绿，日志里能看到 tests/updates.sh 的 21 条 PASS（timer 检查不调 systemctl、不换文件；校验失败不替换；健康检查失败回滚；已是最新不重启；跳过 pre-release；Snell RC/正式版取舍；菜单选择完成更新和开关）和 install-live 的「the daily version check timer registers with real systemd」「the real check service records versions without replacing or restarting anything」。服务器上试：菜单选 5 看版本和每日检查状态，选 5 再选 5 立即检查一次。没做：aarch64 上的 Snell 更新没实机跑；真实「有新版并替换」只在单元测试里用假程序验证。已装好的 v4 开发版没有这个 timer，在「5. 更新 → 6. 开启每日检查」打开。
- [x] v4 Snell v6（可选 v5）+ ShadowTLS v3 —— 2026-10-10 合并，提交 d75eefb（PR #6）。菜单「1. 部署节点」新增「Snell + ShadowTLS（Surge）」：版本回车 = v6（v6 再选 mode，回车 = default，可选 unshaped），可选 v5。官方 snell-server 作为 `srm-snell@<节点ID>` 只监听 127.0.0.1；sing-box 的 shadowtls → direct(override) 链路实测可用，没有用独立的 shadow-tls 二进制。部署完直接给出 Surge 配置行；「2. 节点管理 → 选节点 → 4. 客户端配置」能看到 Surge、sing-box 写法，v5 节点另有 mihomo 写法（mihomo 不支持 v6，页面上有说明）。状态、日志、健康检查、卸载、重启都覆盖 snell 服务。验收：在 GitHub 打开 PR #6，CI「srm checks」全绿，日志里能看到：
  - tests/snell-traffic.sh：「sing-box client (snell 6 + shadowtls v3) fetches the page through snell-v6」，unshaped、v5 各一条；「mihomo … through snell-v5」；「a TLS 1.3 handshake on the ShadowTLS port completes」。
  - tests/install-live.sh：「Snell v6 and v5 run as srm-snell@<node> …」「uninstall stops sing-box and snell-server …」。
  - 本机 `bash tests/snell.sh` 13 项 PASS，其中第 1 项是 v5、v6 两种 Surge 配置行。
  - 顺带修了：卸载时 timer 不存在会导致服务停不掉；连续修改节点会撞上 systemd 启动频率限制。
  - 没做：Surge 实连（没有 Linux 版，只有格式测试）；aarch64 的 snell-server 没有实际运行过；流媒体分流对 Snell 节点不生效（snell-server 自己发起出站，菜单里有说明）。
- [x] v4 补齐 sing-box 其余服务端协议 —— 2026-10-10 合并，提交 95e8a03（PR #5）。注册表新增 Shadowsocks 2022、TUIC v5、VLESS TLS（tcp Vision / ws / grpc / httpupgrade）、Trojan、VMess（TLS+ws）、Naive、Hysteria v1；每种有校验、服务端配置、分享链接、sing-box / Clash Meta / Surge 片段（客户端支持的才给）和防火墙传输层（SS 同端口 TCP+UDP）。TUIC、Hysteria v1、Hysteria2 没有域名时默认自签证书，客户端按指纹校验。验收：在 GitHub 打开 PR #5 看 CI「srm checks」全绿，日志里 tests/traffic.sh 有每个协议「sing-box client fetches the local HTTP page through …」和 mihomo 的 PASS（Naive 也是真实 sing-box 客户端走通）；本机 `bash tests/clients.sh` 15 项 PASS。菜单里试：「1. 部署节点」能看到 10 种协议；「2. 节点管理 → 选节点 → 4. 客户端配置」一屏给出 sing-box / Clash Meta / Surge 写法。没做：Surge 行只有格式测试（没有 Linux 客户端）；各协议的 UDP 转发没单独测；部署菜单还没按「需要域名」分组（属于「快速部署」那条）。
- [x] v4 多节点与节点级分流 —— 2026-10-10 合并，提交 8fb22c4（PR #4）。state schema 2（schema 1 在第一次修改或应用配置时自动迁移，节点不变）；分流规则可限定到指定节点；同一协议可部署多个节点（默认名自动编号）；端口 1–65535（随机仍 10000–50000），TCP 节点不能占用证书续期验证端口。验收：在 GitHub 打开 PR #4 看 CI「srm checks」全绿；本机 `bash tests/state.sh` 全部 PASS；装了 sing-box 1.14.1 的话用 `TEST_CORE=<路径> bash tests/local.sh`，能看到「three nodes of each protocol…」「a rule limited to one node…」两条 PASS。菜单里试：「3. 流媒体分流 → 4. 添加/替换平台规则」，有 2 个以上节点时会列出节点让你按序号选（回车 = 全部）。没做：DNS 规则限定节点的真实 DNS 流量测试（只验了生成结果和 `sing-box check`）；方案里的节点 `transport` 字段放到「补齐其余协议」那条。
- [x] v4 骨架：搬入 dodo-sbox 架构和协议注册表 —— 2026-10-10 合并，提交 e843254（PR #3）。验收：在 GitHub 打开 PR #3 看 CI「srm checks」全绿（65 项 PASS）；本机 `bash srm.sh --help` 列出全部子命令，`bash tests/menu.sh`、`bash tests/protocols.sh`、`bash tests/cli.sh` 都输出 PASS。按 main 上主人新定的规则：去掉了 dodo-sbox 的每日自动更新，所有功能都有菜单项。没做：真实 VPS 上的完整部署（等「切换发布」前验收）。
