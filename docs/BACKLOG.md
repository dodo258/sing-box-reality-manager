# 待办

主人用一句话派活，agent 记到这里，再由后台调度器 agentq 按 `agent-task` 技能做完、测试通过后合并。每条写清：要什么、怎样算做完（验收标准）、涉及哪些页面或文件（知道的话）。

## 待做

从上往下做。正在做的条目后面标「（进行中：分支名 时间）」。

- [ ] v4 骨架：搬入 dodo-sbox 架构和协议注册表 —— 按 `docs/specs/2026-10-10-v4-rewrite.md`「架构」一节，以 `~/projects/dodo-sbox-next` 为蓝本，建立 `lib/`、`build.sh`、`srm.sh`、`dist/srm`、`tests/`、`.github/workflows/check.yml`。改名为 srm（路径 `/opt/srm`、`/var/lib/srm`，服务 `srm.service`，`vasma` 软链）。新增 `lib/protocols.sh` 协议注册表，把 Reality、AnyTLS、Hysteria2 的校验、生成配置、分享链接、客户端出站、传输层集中到注册表，其他模块只通过注册表分派。Reality shortId 每个节点随机生成。二维码只用本地 `qrencode`。支持所有子命令和 `--help`，菜单常驻。验收：CI 全绿（`bash -n`、shellcheck、重新构建后 dist 无差异、移植过来的全部测试）；新增测试证明打开菜单不调用 curl、wget，加一个不存在的协议名会被注册表拒绝；`srm --help` 列出全部子命令；不修改根目录 `install.sh`、`fodder/`、`documents/`。范围：新增 `lib/ build.sh srm.sh dist/ tests/ .github/workflows/check.yml`。（进行中：agent/1010-v4-skeleton 2026-10-10 14:01）
- [ ] v4 多节点与节点级分流 —— state schema 升到 2：同一协议可以有多个独立节点，替代 v3 的「多实例」菜单；policies 加可选的 `inbounds` 字段，把分流规则限定到指定节点（替代 v3 的节点级 DNS 分流）；端口范围放宽到 1–65535（仍检查占用，默认随机 10000–50000）；写 schema 1→2 迁移函数。验收：测试覆盖同协议 3 个节点生成的配置通过 `sing-box check`、限定节点的分流规则只作用在指定 inbound、schema 1 的 state 自动迁移到 2 且节点不变；CI 全绿。
- [ ] v4 ShadowTLS v3 + Shadowsocks 2022 协议 —— 用 sing-box 原生的 shadowtls inbound 加 shadowsocks（2022-blake3-aes-128-gcm）detour 实现，替代 v3 的 Snell+ShadowTLS，在协议注册表里新增一段；分享链接和客户端出站片段给出 sing-box / Clash Meta / Surge 三种写法。验收：配置通过 `sing-box check`；集成测试里用 sing-box 客户端经这个节点访问本地 HTTP 服务成功；CI 全绿。注：主人如果决定保留 Snell，以主人的决定为准（见 PROGRESS.md「待用户决定」）。
- [ ] v4 迁移命令 srm migrate —— 按方案「迁移」一节：从 `/etc/v2ray-agent` 读取 v3 的 sing-box Reality、AnyTLS、Hysteria2 节点（包括 `30_`–`33_` 多实例文件、密钥、证书），生成 schema 2 的 state；默认 dry-run，列出能迁移和不能迁移的内容（Xray、Snell、网站、订阅）；`--apply` 时停旧服务、新服务接管原端口，健康检查失败就恢复旧服务，旧 crontab 行注释掉不删，`/etc/v2ray-agent` 一个字节都不改。验收：`tests/fixtures/v3/` 放至少 3 份脱敏的 v3 配置样本（单 Reality、Reality+AnyTLS+Hy2、多实例），断言迁移结果；测试证明 `--apply` 失败时旧服务被恢复；CI 全绿。

## 等主人拍板

- [ ] v4 切换发布 —— 前 4 条合并、主人验收后才做。内容：
  - 根目录 `install.sh` 换成 v4 引导：从 Release 下载 `srm` 和 `SHA256SUMS`，校验后安装；收到 v3 定时任务参数 `RenewTLS`、`UpdateGeo`、`WebsitePublish` 时输出一行迁移提示并退出 0。
  - v3 脚本冻结到 `legacy/v3` 分支，加 tag `v3.8.4`。
  - 删除 `fodder/` 和过时的 documents。
  - 重写中英文 README，写明功能变化、迁移方法和旧版安装命令。
  - `create_release.yml` 改成按 tag 触发、上传 dist 附件，并去掉删除旧 release 的逻辑。
  - 发布 v4.0.0。

  需要主人决定：是否发布。推荐：前 4 条验收通过后发布。注意：这会改变 main 分支 `install.sh` 的行为，影响所有新安装的人，必须等主人确认。

## 以后再说

## 已完成
