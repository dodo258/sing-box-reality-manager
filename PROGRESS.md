# 进度交接（新会话第一眼看这里，保持在 40 行以内）

## 当前任务
v4 重写，方案 `docs/specs/2026-10-10-v4-rewrite.md`，2026-10-10 按主人补充修订：sing-box 全协议、Snell 单独部署、核心更新（只提示、手动更新）、快速部署流程；拆成 8 条待办见 `docs/BACKLOG.md`。

## 下一步
1. ~~骨架~~（2026-10-10 合并 e843254：lib/ 模块、协议注册表、常驻菜单、CI）→ 2. ~~多节点/分流~~（2026-10-10 合并 8fb22c4：schema 2、规则限定到节点、端口 1–65535）→ 3. ~~其余协议~~（2026-10-10 合并 95e8a03：7 种协议、自签证书加 pin、Clash Meta / Surge 片段）→ 4. ~~Snell+ShadowTLS~~（2026-10-10 合并 d75eefb：官方 snell-server 独立服务 + sing-box ShadowTLS 前置、Surge/mihomo/sing-box 写法、伴随服务机制）→ 5. ~~更新提示与手动更新~~（2026-10-10 合并 2413813：每日只查版本、菜单提示、手动更新带校验和回滚）→ 6. ~~快速部署~~（2026-10-10 合并 67054b0：没有节点直接进快速部署、最多 2 个带默认值的问题、域名先查解析、部署完一屏给全各客户端配置、`srm add --json`）→ 7. ~~migrate~~（2026-10-10 合并 2d6b536：菜单第一屏引导迁移 v3、`srm migrate` 预览 / `--apply`、失败恢复旧服务、5 份脱敏样本）→ 7b. ~~迁移安全修正~~（2026-10-10 合并 583daa1：有剩余 v3 服务就保留续期任务、旧单元加 drop-in 禁止再启动、多用户逐个列出）→ 7c. ~~客户端导入修正~~（2026-10-10 合并 3a3eb7c：分享链接按规范、Hysteria2/AnyTLS 加 `/?`、Surge 逐项列出、UDP 节点提示） → 7d. ~~伪装目标改海外~~（2026-10-10 合并 2ff078b：14 个海外候选、部署时检测并选最快、排除 Cloudflare、节点管理一键更换）→ 7e. ~~iptables 防火墙~~（2026-10-10 合并 a3ab340：没有 UFW / firewalld 时在兜底 REJECT 前插带 srm 注释的规则、netfilter-persistent 保存） → 7f. ~~完整客户端配置与临时导入链接~~（2026-10-11 合并 e45cbd7：节点管理里导出完整 mihomo / sing-box / Surge 配置，临时下载链接下载一次或 10 分钟关闭并撤防火墙） → 7g. ~~部署提示细节~~（2026-10-11 合并 d10dc10：Reality 提示 Shadowrocket 无 UDP、无 IPv6 时 ipv4_only、AnyTLS/Trojan Clash 带 Chrome 指纹、Naive 不加 padding）→ 7h. ~~Hysteria2 端口跳跃~~（2026-10-11 合并 2392455：部署时可选、iptables/nftables 把范围内 UDP 转到节点端口、服务启动时补回、链接带 mport、各客户端带范围）→ 7i. ~~iptables 开机补回~~（2026-10-11 合并 ec56f37：srm.service 启动前 firewall-restore 按当前节点补回端口规则和跳跃转发，持锁操作进行中只补转发）→ 8. 切换发布（等主人确认）
- UFW / firewalld 停用期间保留 srm 的放行规则：2026-10-11 合并 a169bd5（PR #19），重新启用后节点照常放行；停用期间删掉的节点 UFW 规则照常删。
- firewalld 停着时卸载：2026-10-11 合并 e560303（PR #20），用 firewall-offline-cmd 清 srm 的永久端口、丢运行时记录；没有离线工具时提示先启动 firewalld。
- 测试稳定性：2026-10-11 合并 a1321a9，traffic.sh / snell-traffic.sh 的 mihomo 段先等直连探测通过再测节点（mihomo 开端口早于开始转发，曾偶发 CI 失败）。
- 公开仓库去掉 Lisa 的 IP：2026-10-11 合并 3597fee（PR #21），新增 `tests/no-real-ip.sh` 扫已跟踪文件里的真实 IPv4，CI 单独一步跑；git 历史里的旧提交等主人拍板。
- 同类脚本调研：2026-10-11 合并 5e4f86b（PR #22）。报告见 `docs/research/2026-10-11-同类脚本调研.md`，定位「绝不把你的服务器搞坏」写进方案和 AGENTS.md；补短板的 7 条待做已进 BACKLOG。
- 公开仓库扫描补全：2026-10-11 合并 2545601（PR #23），`tests/no-private-info.sh` 扫 IPv4 / IPv6、UUID、Reality 私钥、short_id、域名、邮箱、本机路径，测试样本全换成占位，CI 单独一步跑。
- 核心大版本上限：2026-10-11 合并 b05ef09（PR #24），新装和更新只取 srm 验证过的 1.14 系列，更新的大版本标「srm 尚未验证」、菜单确认后才装。

## 待用户决定
- 前 7 条验收后，是否正式发布 v4.0.0

## 已知问题 / 风险
- 端口跳跃（2392455）没在真机试过：下次在 Lisa 上给 test-hy2 开启（节点管理 → 10），安全组放行 UDP 20000-20999，用 Shadowrocket 确认读到了 mport 并在中国移动网络下测。
- 完整配置 / 临时导入链接（e45cbd7）还没在真机扫码导入过：下次在 Lisa 上用「2. 节点管理 → 临时导入链接」分别试 sing-box App、Surge、Clash Verge。
- 伪装目标已改成海外候选（2ff078b），但新候选还没在中国移动网络下实测，下次在 Lisa 上用「节点管理 → 10」换成自动选的目标再测一次。
- 2026-10-10 Lisa（主人的生产机）实测 v4 开发版：部署、监听、防火墙正常，菜单 0.07 秒。手机（中国移动 + Shadowrocket，全局代理）：伪装目标 www.ctrip.com 的 Reality 每次握手都报 invalid connection，打不开；同版本只换成 www.seagate.com 的临时对照节点（systemd-run 单元 `srm-ab-test`，UFW 注释 srm-ab-test-temp）正常承载主人全部流量。Hysteria2 只见少量包、未确认连通；Snell v6 未在 Surge 测。测试节点 test-reality/test-hy2/test-snell 和对照节点仍在 Lisa 上，等主人说清理。
- 新装和更新 sing-box 只取 1.14 系列最新稳定版（API 不通退回 1.14.1）；1.15 出来后只在「5. 更新 → 2」确认才装。验证新大版本后发 srm 时把 `CORE_VERSION` 和固定 SHA256 升上去。CI 单元测试仍固定 1.14.1。
- 已装好的 v4 开发版服务器下一次改节点时自动更新 systemd 单元（补上 firewall-restore 和 1024 以下端口的权限，ec56f37）。
- Snell 节点不受流媒体分流规则影响（snell-server 自己发起出站）；部署装固定的 v6.0.0rc2 / v5.0.1，之后在菜单「5. 更新」跟进新版（新构建官方无校验和，靠 HTTPS + 试运行核对版本）。
- 已装好的 v4 开发版服务器没有每日检查 timer，在菜单「5. 更新 → 6. 开启每日检查」打开。
- 快速部署的公网 IP 来自 Cloudflare trace（部署时访问一次）；查不到时菜单里让用户填，`srm add --yes` 要带 `--host`。Shadowrocket 的协议支持没有官方清单，Naive 没列。
- 自签证书目录 `/var/lib/srm/selfsigned/<节点ID>` 删除节点时不清理（回滚可能还要用），只在卸载时随 /var/lib/srm 删除。
- main 上的 `install.sh` 仍是 v3，现网用户靠它安装和更新，切换前不能改。
- 迁移：没在真实 v3 服务器上跑过；有 Xray / 网站时保留 v3 续期任务，但 v3 续期那天若要重启旧 sing-box 会失败并提前退出、nginx 停着（预览有提示）；同一端口多个用户只迁第一个（预览逐个列出）。
- `.github/workflows/create_release.yml` 监听 `master`，从没运行过；里面有删除旧 release 的逻辑，改触发条件前要先去掉。
