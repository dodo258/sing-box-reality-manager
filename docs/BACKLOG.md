# 待办

主人用一句话派活，agent 记到这里，再由后台调度器 agentq 按 `agent-task` 技能做完、测试通过后合并。每条写清：要什么、怎样算做完（验收标准）、涉及哪些页面或文件（知道的话）。

## 待做

从上往下做。正在做的条目后面标「（进行中：分支名 时间）」。

- [ ] 核心大版本上限：新装只装 srm 测过的大版本 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（fscarmen 默认装 alpha，相关 issue 23 条；233boy #112、TheyCallMeSecond #5、caigouzi #4 都是核心大版本升级后配置不兼容、服务停掉）。现在新装取「最新稳定版」，PROGRESS 已记下风险：1.15 如果改了配置格式，新装机器会在 `sing-box check` 处失败。做法：
  - srm 里写一个「已验证的大版本」（如 1.14），安装和「只更新 sing-box」默认取这个大版本里最新的稳定版。
  - 比它新的稳定版在菜单状态栏和「5. 更新」里显示为「sing-box 1.15.0 可更新（srm 尚未验证）」，用户在菜单里确认后才装，装之前照常 check、失败回滚。
  - 同步改方案「架构」一节的「核心版本」、「更新」一节和 DECISIONS。
  - 验收：测试里用假的 Release 列表（1.14.5、1.15.0），新装选 1.14.5；更新菜单显示 1.15.0 未验证、默认返回；确认后装 1.15.0。检查命令全过。
- [ ] 凭据不轮换的测试：改设置不让已发出去的链接失效 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（Amnezia #2958：改设置后 Reality 被悄悄去掉、密钥被轮换，客户端连不上）。现在只有「换伪装目标保留凭据」有测试（`tests/management.sh:32`）。补测试：每种协议的节点，分别做改端口、改名、停用后启用、开关端口跳跃、换核心版本（测试里换二进制）、迁移后再改一次，之后 uuid / password / private_key / public_key / short_id / 证书 pin 都不变；只有「rotate」会变。发现会变的就修。验收：测试覆盖上面每个操作，撤掉任一处保留逻辑测试会失败；检查命令全过。
- [ ] 离线 / 代理更新：GitHub 不通时也能装核心 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（233boy `-f/-p/-v`、Xray-install `--local/-p/--version`，GPL-3.0；233boy 下载 GitHub 失败约 6 条，Xray-install #42 API 限流；mack-a #1046 #1296）。
  - 菜单「5. 更新」加「从本地文件更新 sing-box」：用户把官方 tar.gz 传到服务器后，在菜单里选这个文件。命令行 `srm update core --file PATH`。
  - 有官方 digest 可查时照常比对；查不到时提示「无法核对校验和」，要用户确认，再跑 `version`、`check`，健康检查失败照常回滚。
  - 同时支持 `HTTPS_PROXY` 环境变量下载，提示文字写明。
  - GitHub 下载失败时，报错提示「在菜单「5. 更新」里选「从本地文件更新」」。
  - 验收：测试里本地文件更新成功、坏文件被拒、check 失败回滚；`docs/menu-preview.txt` 同步。检查命令全过。
- [ ] 换机：导出备份 / 在新服务器导入 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（mack-a #1240、#1265、#878 要备份恢复；Outline #1268 自 2023 年未处理；Amnezia #938；反例：reality-ezpz 把含私钥的备份上传到 temp.sh）。
  - 菜单「2. 节点管理」加「导出备份」：把 state、证书、Snell 配置打成一个本地文件（权限 600），可选口令加密，提示用 scp 取走。不上传任何地方。
  - 新服务器装好 srm 后，第一屏加「从备份导入」：读备份，把节点地址换成新机的公网 IP，重新放行防火墙，走正常的 check、切换、回滚流程。
  - 域名证书在 IP 变了以后要提醒改解析。
  - 验收：测试里在 A 导出、在空的 B 导入，各协议节点的凭据不变、地址换成 B 的、防火墙规则补上，真实核心能连通；错口令、坏文件不改动任何东西。检查命令全过。
- [ ] 连不上自查 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（yg「节点 -1」类 14 条、fscarmen #242 97 评论，多数是安全组、运营商限 UDP、客户端证书设置这些环境问题；Outline `install_server.sh:410-438` 的防火墙提示写法，Apache-2.0）。
  - 菜单「4. 运行状态」加「连不上？逐项检查」，逐个节点检查：服务在运行、端口在监听（TCP / UDP 对得上）、本机防火墙规则在、证书没过期且域名还解析到本机、Reality 伪装目标还能握手。
  - 最后列出本机查不到、要用户去做的事：安全组放行哪个端口和协议；UDP 节点被限时换 Reality / AnyTLS；自签证书节点在客户端要填 pin。
  - 只在查伪装目标和域名解析时联网，不做本机回环访问自己（会误报，见 mack-a #757）。
  - 验收：测试里构造监听缺失、防火墙规则缺失、证书过期三种情况，各自报出对应的一条；`docs/menu-preview.txt` 同步。检查命令全过。
- [ ] 识别别家脚本装的服务，只提示、不动 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（fscarmen `sing-box.sh:2230-2262` 的识别表，GPL-3.0；fscarmen 识别到就退出，srm 改成只提示）。
  - 打开菜单时按本地的 systemd 单元和路径（不联网）识别 mack-a、233boy、yonggekkk、fscarmen、s-ui、3x-ui 装的 sing-box / xray。
  - 第一屏提示一行「这台机器上还有 <谁> 装的 <服务>，占着端口 …；srm 不会动它」。快速部署选端口时避开这些端口。
  - v3 照旧走迁移引导。
  - 验收：tests 里用替身单元覆盖每一家，各显示对应提示；随机端口避开它们的端口；没有别家时不显示。菜单打开仍不联网。检查命令全过。
- [ ] 文档「srm 会改你系统的哪些地方」 —— 依据 `docs/research/2026-10-11-同类脚本调研.md`（V2EX t/929902 里用户判断脚本可不可信的几个信号；Amnezia、Hiddify 改系统设置却不还原的反例）。写 `docs/what-srm-changes.md`：
  - 装了哪些包；写了哪些路径、systemd 单元、定时任务；建了哪个系统用户；防火墙规则长什么样（注释、所有权记录）；改了哪个 sysctl（BBR，要用户选）。
  - 卸载时逐项怎么还原、哪些故意保留（系统依赖）。
  - 会联网的全部时机和地址（部署查 IP、伪装目标检测、GitHub Release、acme、临时导入链接）；没有遥测。
  - 「先下载、看过再运行」的安装写法。
  - 切换发布时 README 链到这里。
  - 验收：文档里每个路径、单元名、地址都能在 `lib/` 里 grep 到（附一个检查脚本或写进 tests）；检查命令全过。

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

- [ ] 每个家人一份凭据：按人分发、能看用量、能撤销（不做计费和到期）—— 来源：Outline 访问密钥（一人一个、看用量、能撤销）、s-ui 多用户；调研见 `docs/research/2026-10-11-同类脚本调研.md`。要改 state 的用户模型，用量统计要用 sing-box 的 API，又不能常驻，方向性大，先不做。
- [ ] 临时导入链接按客户端 UA 自动给对应格式，少问一步 —— 来源：fscarmen `sing-box.sh:3872-3890`（GPL-3.0）。
- [ ] 双栈机器同时给 IPv6 链接和二维码 —— 来源：reality-ezpz `reality-ezpz.sh:1515-1531`（Apache-2.0）、yonggekkk `sb.sh:925-940`（GPL-3.0）。
- [ ] 从别家脚本迁入节点（233boy、yonggekkk、fscarmen）—— 来源：fscarmen 的识别表；srm 现在只迁 v3。先做待做里的「识别别家脚本」，看有没有人要。
- [ ] Alpine / OpenRC 支持 —— 来源：233boy、yonggekkk、eooce、passeway、caigouzi 都支持。srm 的服务、定时器、drop-in、伴随服务都建在 systemd 上，改动很大；目标系统仍是 Debian / Ubuntu。
- [ ] cloud-init / user-data 开机即部署的示例 —— 来源：Outline 用 DigitalOcean API 把安装脚本当 user_data 塞进新机器。等 v4 发布后在 README 进阶用法里给一段 `srm add --yes` 示例。
- [ ] 证书支持 DNS API（Cloudflare / 阿里云）和通配符证书 —— 来源：对比 mack-a（M 2050 起，可选 CA 1998）；同类调研（2026-10-11）里 3x-ui、s-ui、TheyCallMeSecond（`Install.sh:1116-1153`，GPL-3.0）也都有。80 和 443 都被挡的用户现在只能手动导入证书。新手用得少，先不做。

## 已完成

- [x] 公开仓库扫描补全：IPv6、UUID、域名、密钥、邮箱、本机路径 —— 2026-10-11 合并，合并提交 2545601（PR #23）。
  - `tests/no-real-ip.sh` 改名 `tests/no-private-info.sh`，扫已跟踪文件里的八类：IPv4、IPv6（全球单播，放过 2001:db8::/32、3fff::/20）、UUID、Reality 私钥、short_id、域名、邮箱、`/Users`/`/home` 路径。每类有放行的占位写法，公共地址进 `KNOWN`、`KNOWN_*` 清单并写理由；规则写在脚本开头和 DECISIONS.md。
  - 测试样本统一成占位：UUID 用 `00000000-0000-4000-8000-00000000000N`，迁移样本私钥用 `AAAA…AAAx`（公钥重新推导）；测试输入里的真实短域名换成 example.com 下的名字。README 和菜单预览原本就是占位，没改。CI 那一步和 AGENTS.md 同步。
  - 验收：在 GitHub 打开 PR #23，CI「verify」全绿，「Check tracked files for real addresses, UUIDs, keys, domains, emails and home paths」那一步日志里有两条 PASS。本机在仓库里 `bash tests/no-private-info.sh` 应两条 PASS；随便建个文件写一个真实样子的域名（如你自己的域名）和一个 `/Users/你的用户名`，`git add` 后再跑应 FAIL 并报出这两行（看完 `git rm -f` 删掉）。
  - 已知局限：私钥和 short_id 只认和字段名同一行的值；`TLDS` 清单外的冷门后缀不报。
- [x] 同类一键脚本全面调研，写出 srm 凭什么值得用 —— 2026-10-11 合并，合并提交 5e4f86b（PR #22）。只改了文档。
  - 报告 `docs/research/2026-10-11-同类脚本调研.md` 的覆盖面：
    - 12 个直接同类：mack-a、yonggekkk、fscarmen、eooce、233boy、Xray_onekey、reality-ezpz、Xray-install、caigouzi、deathline94、TheyCallMeSecond、passeway。
    - 7 类相邻形态：3x-ui、s-ui、Hiddify、PasarGuard/Marzban、Docker、Outline、Amnezia，以及纯手工、商家一键应用、买机场。
    - 每个都有链接、star、最近更新、许可证和读代码或 issue 得出的结论。
  - 结论：srm 定位「装上能用，而且绝不把你的服务器搞坏」，三条底线：
    - 改了不会坏、坏了能回去：同类被骂得最多的是升级后要卸载重装，mack-a、yg、fscarmen 合计 100 条以上。
    - 不越界：yg、fscarmen、mack-a 都有卸掉 UFW、关防火墙的 issue。
    - 装完就能连上，连不上知道为什么。
  - 已写进方案「定位与差异化」一节、AGENTS.md「项目是什么」和 DECISIONS。补短板拆成上面 7 条待做，「以后再说」加了 6 条。
  - 替主人定了：
    - 不追功能广度、不做面板和 Docker（理由见 DECISIONS「2026-10-11 srm 的定位」）。
    - 「新装取最新稳定版」和第一条底线冲突，写成待做「核心大版本上限」，没直接改方案。
  - 验收：打开报告，看第五节「srm 凭什么」和第六节「明确不做」，再看第一节对照表最后一行 srm 和同类的对比；不同意哪条直接说。
  - 没做：Reddit 英文社区抓不到；面板内存数字只引用 issue，没实测。
- [x] 要不要改写 git 历史清掉旧提交里的生产机 IP —— 2026-10-11 按推荐 A 定：不改写历史（IP 已公开约 8 小时，改写收不回已被抓取的副本，还会改掉所有提交号），当前文件里的 IP 已在 3597fee 去掉并加了 CI 检查。决定记在 DECISIONS.md
- [x] 公开仓库去掉生产机真实 IP，并加自动检查 —— 2026-10-11 合并，合并提交 3597fee（PR #21）。PROGRESS.md 里 Lisa 实测那一条只写代号「Lisa（主人的生产机）」，去掉公网 IP、v3 节点端口、所跑服务和对照节点端口；全仓核查已跟踪文件：公网 IPv4 只有那一处，UUID 都是示例值，IPv6 是文档段 / ULA / 公共 NAT64 DNS，域名都是示例或公共服务。新增 `tests/no-real-ip.sh`：扫已跟踪文件里保留段、文档段和脚本 `KNOWN` 公共地址（公共 DNS 等）以外的 IPv4，报文件和行号、退出 1，先自检扫描本身；CI 单独一步「Check tracked files for real server IP addresses」，AGENTS.md「常用命令」写明。验收：在 GitHub 打开 PR #21，CI「verify」全绿，那一步日志里有「PASS tracked files contain no real server IPv4 address」；本机在仓库里 `bash tests/no-real-ip.sh` 应两条 PASS，把 PROGRESS.md 换成 `git show a15df5f:PROGRESS.md` 再跑应 FAIL 并报出 `PROGRESS.md:19`（看完 `git checkout -- PROGRESS.md` 恢复）。没做：git 历史里的旧提交（等主人拍板那条）；IPv6、域名、UUID 没有自动检查，靠提交前人工复核。
- [x] firewalld 停着时也能卸载 srm —— 2026-10-11 合并，提交 e560303（PR #20）。firewalld 没运行时卸载不再停在「端口规则清理失败」：运行时记录丢掉（停止时规则已没了），srm 加的永久端口用 `firewall-offline-cmd` 从配置文件删掉，原有端口不动；同端口永久规则没删成功时运行时记录也保留；系统没有 `firewall-offline-cmd` 时报错提示「先启动 firewalld（systemctl start firewalld）再重试」；firewalld 已卸掉时直接丢记录。CI 新增一步装 firewalld 但不启动，用真实 `firewall-offline-cmd` 验证。验收：在装了 firewalld 的测试机上部署一个节点，`systemctl stop firewalld` 后在菜单里卸载，应显示「卸载完成。」，`firewall-offline-cmd --list-ports` 里不再有节点端口。
- [x] UFW / firewalld 临时停用时保留 srm 的放行规则 —— 2026-10-11 合并，提交 a169bd5（PR #19）。同步时 UFW / firewalld 只要不是当前活动的防火墙（`ufw disable`、开机时还没起来、检测选了 iptables 或 none），它的记录就不当作多余删：UFW 停用时还能改规则文件，只删已经不用的端口（停用期间删掉的节点）；firewalld 停着时什么都改不了，记录全保留，等它运行后的第一次同步再清。iptables 记录照旧。同步结果提示「UFW 当前没有运行，还在用的节点的放行规则保留着…启用后在菜单「4. 运行状态」里选「重新同步防火墙端口规则」」。以前 firewalld 停着时每次同步都失败、改节点被回滚，现在也好了。
  - 替主人定了：不只 backend none，UFW 停用后检测选 iptables（Oracle 这类镜像）时也保留；停用期间新加的节点不往停用的 UFW 里加规则（Ubuntu 默认装了 UFW 但不启用）。理由见 DECISIONS.md「2026-10-11 UFW / firewalld 停用期间保留 srm 的放行规则」。
  - 验收：在 GitHub 打开 PR #19，CI「verify」全绿，日志里有 firewall-live 的「PASS real UFW disabled, synced, enabled again: the srm rules are still there and let the nodes through」「PASS real UFW: a node deleted while UFW is disabled loses its rule, the others keep theirs …」和 tests/firewall.sh 的「PASS firewalld stopped, synced (also deleting a node), started again …」。服务器上试：在开着 UFW 的机器上 `ufw disable`，菜单「4. 运行状态 → 3」同步一次（应提示 UFW 当前没有运行、规则保留着），`ufw enable` 后 `ufw status` 里仍有 `srm-<端口>-<协议>`，节点能连。
  - 没验证：真机；「没有 ufw 命令时记录全保留」这一支没有单独测试。永久换防火墙或卸掉 ufw 后旧记录一直留着，卸载 srm 时才清。
- [x] tests/traffic.sh 的 mihomo 流量测试偶发失败 —— 2026-10-11 合并，提交 a1321a9（PR #18）。原因：mihomo 先开监听端口、后把隧道切到 Running，中间进来的连接被静默关闭（源码 hub/executor ApplyConfig、tunnel handleTCPConn 的 isHandle），wait_port 只等端口，CI 稍慢时 curl 落进窗口拿到 Empty reply。改法：mihomo 配置多一个直连入站（traffic.sh 18296、snell-traffic.sh 18396，proxy: DIRECT），直连取到测试页才经节点取一次，断言不变；snell-traffic.sh 的 mihomo 段同样有这个竞态，一并修了。验收：在 GitHub 打开 PR #18，CI「verify」两次全绿，日志里 13 条「PASS mihomo (Clash Meta snippet) …」和「PASS mihomo (Clash Meta snippet: snell v5 + shadow-tls v3) …」；本机给 cache.db 加锁放大窗口时，旧代码「FAIL mihomo through ss 测试」、新代码全过；正常速度连跑 20 次全过。没做：没在 Linux 上复现原失败（靠源码和放大窗口实验定位）。
- [x] v4 iptables 规则开机自动补回 —— 2026-10-11 合并，提交 ec56f37（PR #17）。
  - srm.service 每次启动前（含开机）运行 `firewall-restore`：主锁空闲时按当前节点完整同步防火墙端口规则和端口跳跃转发；正在应用配置等操作持锁时只补转发，端口规则由那个操作同步；失败不挡服务启动。`hop-sync` 留作旧名；已装好的服务器下次改节点时自动更新单元。
  - 验收：在没有 netfilter-persistent、INPUT 末尾有 REJECT 的服务器（如 Oracle 镜像）上部署节点后重启服务器，`iptables -S INPUT` 里仍有注释 srm 的放行规则、节点能连；`systemctl show -p ExecStartPre srm.service` 里有 `firewall-restore`。
  - 没验证：真机重启（CI 用真实 systemd 删规则后重启服务验证）。

- [x] v4 Hysteria2 端口跳跃 —— 2026-10-11 合并，提交 2392455（PR #16）。
  - 部署 Hysteria2 时多一问「端口跳跃（运营商限制 UDP、单个端口被限速时用）」：回车 / 1 = 不开，2 = 20000 起第一段空闲的 1000 个端口，3 = 自己填；之后问端口，节点名用默认值。命令行 `srm add hysteria2 --hop off|auto|起-止`。
  - 服务器把范围内发给本机的 UDP 转到节点端口：有 iptables 用 iptables / ip6tables nat（注释 `srm-hop`），否则 nftables 表 `inet srm_hop`；停用节点、关闭跳跃、删节点、卸载都撤掉；srm.service 每次启动（含重启服务器）先 `hop-sync` 补回。
  - 客户端：分享链接带 `&mport=起-止`，Surge `port-hopping`、Clash Meta `ports`、sing-box `server_ports` 都带上（完整配置导出也是）；「说明：」给出 Hysteria2 官方 `端口,起-止` 写法的链接。部署完成页提醒云安全组放行跳跃范围。
  - 节点管理：Hysteria2 节点多「10.端口跳跃」（开 / 关 / 改范围），列表显示「端口 N（跳跃 起–止）」；`srm node ID hop off|auto|起-止`。
  - 替主人定了：分享链接没用待办写的官方 `端口,起-止`，改用 `mport`（v2rayN 解析不了官方写法会整条导入失败；mack-a、Xboard 给 Shadowrocket 的订阅都用 mport），官方写法放进「说明」；只转发发给本机的包；有 iptables 优先用 iptables，没有才用 nftables；客户端跳跃的端口集合含节点端口本身。理由见 DECISIONS.md「2026-10-11 Hysteria2 端口跳跃」。
  - 验收：在 GitHub 打开 PR #16，CI「verify」全绿，日志里有 tests/hop.sh 的 14 条 PASS（「share links keep the node port and carry the range in mport …」「enabling port hopping adds an srm-hop REDIRECT rule …」「disabling the node or turning hopping off removes its rule …」「changing the range replaces the rule; deleting the node and uninstalling remove it」等），firewall-live 的「real iptables: UDP to the hop range (IPv4 and IPv6) reaches the node port …」「real nftables: …」，install-live 的「port hopping with real systemd: … the redirect comes back when the service starts …」。菜单样子见 `docs/menu-preview.txt`「Hysteria2（问了端口跳跃和端口…）」和「Hysteria2 节点（…）」两段。服务器上试：Lisa 更新到最新开发版后，菜单「2. 节点管理 → 选 test-hy2 → 10 → 2」，到服务商安全组放行 UDP 20000-20999，`iptables -t nat -S PREROUTING | grep srm-hop` 应有一条；用 Shadowrocket 扫新二维码（看节点详情里端口跳跃是否带上），在中国移动网络下测速；再选「10 → 1」关闭，那条规则应消失。
  - 没验证：运营商限速下的实际效果；Shadowrocket 读 `mport` 只有面板做法作依据（没有官方说明）、Surge 只做了格式断言。已装好的开发版服务器第一次开启跳跃时会重写 srm.service 单元（补 hop-sync 这行），应用时服务照常重启。
- [x] v4 部署结果提示与客户端细节 —— 2026-10-11 合并，提交 d10dc10（PR #15）。
  - ① Reality 节点（以及同样用 Vision 流控的 VLESS TLS tcp）的部署结果、「2. 节点管理 → 选节点 → 4. 客户端配置」和 `srm add --json` 的 note 末尾多一句「说明：Shadowrocket 走这个节点时 UDP 不可用，需要 UDP 请用 Hysteria2 / TUIC / AnyTLS（在菜单里选「1. 添加节点」部署）。原因：…网页会自动改走 TCP 照常打开，游戏、语音通话等纯 UDP 应用不通。」ws / grpc / httpupgrade 没有流控，不加。
  - ② 生成配置时用 `ip -6 route get 2606:4700:4700::1111` 查本机有没有 IPv6 路由（只查路由表，不联网；WARP / wg-quick 策略路由补的 IPv6 也算）。没有时 `route.default_domain_resolver` 和流媒体分流 socks 出站的 `domain_resolver` 写成 `{"server":"local","strategy":"ipv4_only"}`；有 IPv6 或没有 ip 命令时保持 `"local"`。
  - ③ AnyTLS 的 Clash Meta 片段加 `client-fingerprint: chrome` 和 `alpn: [h2, http/1.1]`（mihomo 文档示例、mack-a 输出相同）；同类的 Trojan 片段也加 `client-fingerprint: chrome`。
  - ④ Naive 链接不加 `padding=true`：naiveproxy 自动协商 padding，sing-box naive 入站本来就要求 Padding 头，v2rayN 解析链接不读这个参数（出处见 DECISIONS.md 2026-10-11）。
  - 替主人定了：Vision 的 UDP 说明也加到 VLESS TLS tcp；IPv6 用本机路由判断，不像 mack-a 那样 curl -6 联网；Trojan 顺带加指纹；Naive 不加 padding。理由见 DECISIONS.md。
  - 验收：在 GitHub 打开 PR #15，CI「verify」全绿，日志里有 tests/state.sh「without an IPv6 route the config resolves domains ipv4_only; with one it does not」、tests/local.sh「without IPv6 the ipv4_only domain resolver is accepted by real core」、tests/quick.sh「… and that Shadowrocket has no UDP through Reality」、tests/clients.sh「… Vision nodes say Shadowrocket has no UDP through them」、tests/traffic.sh「mihomo (Clash Meta snippet) fetches the page through anytls / trojan」。菜单样子见 `docs/menu-preview.txt` 部署完成页末尾的「说明：」。服务器上试：Lisa 更新到最新开发版后，菜单「2. 节点管理 → 选 test-reality → 4」看末尾说明；在 Lisa 上 `ip -6 route get 2606:4700:4700::1111` 看有没有 IPv6，再 `jq .route.default_domain_resolver /var/lib/srm/current/config.json`（改一次节点后生成），没有 IPv6 时应是 ipv4_only 对象。
  - 没验证：Shadowrocket 里的实际显示；AnyTLS 的 UDP（UDP over TCP）在 Shadowrocket 里能否用；无 IPv6 真机上 network unreachable 是否减少。已装好的服务器要等下次改节点重新生成配置才带上 ipv4_only。
- [x] v4 完整客户端配置与一键导入（替代旧订阅）—— 2026-10-11 合并，提交 e45cbd7（PR #14）。菜单「2. 节点管理」在节点列表后面多了两项：
  - 「导出完整配置」：先选节点（回车 = 全部启用的节点），再选 App（1. Clash Verge / Clash Meta for Android，2. sing-box 官方 App，3. Surge），屏幕上显示整份配置：所选节点、一个「节点选择」策略组、DNS，以及局域网和国内网站直连、其余走代理的基本分流。App 不支持的协议不放进去，并列出跳过了哪些节点。
  - 「临时导入链接」：同样选节点和 App，再问端口（回车随机）。srm 在随机路径上开一个临时下载端口，给出二维码、该 App 的一键导入链接和下载地址；下载一次或 10 分钟后自动关闭，并撤掉防火墙放行（Ctrl+C、SSH 断开也会撤）。服务器上有正式证书且域名解析到本机时走 HTTPS，否则走 HTTP，并提示「链接里带节点密码，用完即关」。
  - 一键导入链接：sing-box `sing-box://import-remote-profile?url=…#名称`（官方文档）、Surge `surge:///install-config?url=…`（官方手册）、Clash `clash://install-config?name=…&url=…`（没有文档页，依据 Clash Verge Rev 和 Clash Meta for Android 的源码，出处见 DECISIONS.md）。命令行另有 `srm profile`、`srm profile-link`。
  - 替主人定了：基本分流用各 App 自带的 geo 数据（mihomo、Surge）和 sing-box 官方规则集，不用 mack-a 的远程规则；一次只给一个 App 开下载（下载一次就关）；用 python3 做下载服务（缺了会自动装）；Surge 也给了完整配置。理由见 DECISIONS.md 2026-10-11。
  - 验收：在 GitHub 打开 PR #14，CI「verify」全绿，日志里有 tests/profiles.sh 的「sing-box check accepts the whole sing-box profile …」「mihomo -t accepts the whole mihomo profile …」「the temporary link serves the profile once at its random path (404 elsewhere), then closes and removes the firewall opening …」「without a download the link closes after its time …」「an interrupted link stops serving …」，和 firewall-live 的「real iptables: the temporary import link opens its port before the REJECT while serving and removes the rule after one download …」。菜单样子见 `docs/menu-preview.txt`「「2. 节点管理」：节点后面是…」一节。服务器上试：Lisa 更新到最新开发版后，菜单「2. 节点管理」→ 选倒数第一项「临时导入链接」→ 回车 → 选 2（sing-box）→ 回车，用手机相机扫码导入 sing-box App；再试一次选 3 用 Surge 扫码；电脑上选 1，把下载地址粘到 Clash Verge「订阅」页导入。导入后 `iptables -S INPUT` / `ufw status` 里不应再有那个临时端口。
  - 没做 / 没验证：三个 App 都没实际扫码导入（没有设备），Surge 配置只做了格式检查；云安全组拦住临时端口时只能按提示放行或改用「导出完整配置」；临时链接等待期间占着 srm 锁，那天的自动续期会顺延一天。
- [x] v4 防火墙支持 iptables（无 UFW / firewalld 的系统）—— 2026-10-10 合并，提交 a3ab340（PR #13）。UFW、firewalld 都没运行，且 iptables / ip6tables 的 INPUT 有兜底 `-j REJECT` / `-j DROP`（或默认策略 DROP）时，在兜底规则正前方插入 `-p tcp|udp --dport <端口> -m comment --comment srm -j ACCEPT`，IPv4、IPv6 分别判断；规则有变化且有 netfilter-persistent 就 `netfilter-persistent save`，没有就提示「重启后会失效；安装 iptables-persistent 时选「是」保存当前规则」。删节点、改端口、停用、卸载按完整规则（含注释）精确删除，同端口的别人规则不动。提示文字改成「UFW / firewalld / iptables」。
  - 替主人定了：只在有兜底拦截时才启用 iptables（INPUT 全放行的普通机器不加规则）；插在兜底规则正前方而不是最前面（mack-a 插最前面，会跳过用户自己的封 IP 规则）；缺 comment 模块的机器部署会失败回滚并提示可改用 UFW。理由见 DECISIONS.md。
  - 验收：在 GitHub 打开 PR #13，CI「verify」全绿，日志里有 tests/firewall-iptables.sh 的 10 条 PASS（「adding nodes inserts ACCEPT rules commented srm before the REJECT and saves them with netfilter-persistent」「deleting a node removes only its srm rule and saves」「uninstall removes every srm rule and keeps the existing allow on the same port」等）和 firewall-live 的三条「PASS real iptables: …」（真实 iptables 下 REJECT 挡住、同步后能访问、删节点又被挡、卸载后规则逐字节复原）。服务器上试：在甲骨文 Ubuntu 镜像（`iptables -S INPUT` 末尾有 `-j REJECT`）上部署一个节点，`iptables -S INPUT` 应在 REJECT 前多一条带 `--comment srm` 的规则、`/etc/iptables/rules.v4` 里也有；删掉节点后这条消失。
  - 没做：没在真实甲骨文镜像上跑；`netfilter-persistent save` 会把 fail2ban / Docker 的动态规则一起存进去（照 mack-a 的做法）；没装 netfilter-persistent 时重启后的自动补回放进了待做。原生 nftables 规则仍不接管。
- [x] v4 Reality 伪装目标不能写死国内网站 —— 2026-10-10 合并，提交 2ff078b（PR #12）。写死的「携程 / 西瓜视频」换成 14 个海外候选：www.jetbrains.com、www.mozilla.org、www.python.org、www.cisco.com、www.oracle.com 等，都满足 TLS 1.3、HTTP/2、证书有效、首页不跳转、不经 Cloudflare。Reality 和 ShadowTLS（Snell）共用这份列表。
  - 部署：在服务器上同时检测全部候选（openssl 查 TLS 1.3、HTTP/2 和证书；curl 请求 `/cdn-cgi/trace` 测握手耗时，回答里有 `visit_scheme=` 就视为经 Cloudflare 并排除），自动选握手最快的。快速部署的问题数不变，结果前显示「伪装目标：自动选用 X（握手 N ms）」。
  - 「2. 节点管理 → 选节点 → 10. 更换伪装目标」：通过检测的候选按耗时列出，回车选最快的；也可以自己填域名（同样要通过检测）。换完重新显示链接、二维码和各客户端配置。
  - `--sni` 和 `retarget` 接受任何通过检测的域名。迁移 v3 时保留原来的目标。实测结论写进了 DECISIONS.md。
  - 替主人定了：自己填的域名如果经 Cloudflare，只提示、照常使用，不拒绝。原因是主人在用的 seagate、sennheiser、umich 都经 Cloudflare，而且 seagate 已经实测可用。内置候选仍然排除 Cloudflare。
  - 验收：
    - 在 GitHub 打开 PR #12，CI「verify」全绿，日志里有 tests/certificates-menu.sh 的「candidates that fail the check or answer /cdn-cgi/trace (Cloudflare) are never picked; the fastest is」、tests/quick.sh 的「node management switches the target with Enter …」、tests/management.sh 的「a target outside the built-in list that passes the check is accepted …」、tests/protocols.sh 的「… --sni takes any domain that passes, not one that fails …」。
    - 服务器上试：Lisa 更新到最新开发版后，在菜单里选「2. 节点管理 → 选 test-reality → 10」，看候选列表和耗时，回车，用 Shadowrocket 扫新的二维码，在中国移动网络下打开网页。
  - 没做：新候选还没在中国移动网络下实测；本机检测走本地代理，耗时数字没有参考价值；自己填的国内网站能通过技术检测，脚本识别不出它是国内网站。
- [x] v4 客户端导入修正：分享链接格式与 Surge 导入 —— 2026-10-10 合并，提交 3a3eb7c（PR #11）。分享链接逐个对照规范（依据链接写在 `lib/protocols.sh` 各 `share_uri` 上方）：Hysteria2 改为 `hysteria2://密码@主机:端口/?sni=…[&insecure=1&pinSHA256=…]`（加 `/`、去掉 `alpn`），AnyTLS 按 anytls-go 规范同样加 `/`；VLESS、Trojan、VMess、SS2022、TUIC、Hysteria v1、Naive 原本就符合规范，没改。Surge 官方 URL scheme（manual.nssurge.com/tools/url-scheme.html）只有安装整份配置的 install-config，没有导入单个代理的方式，所以 Surge 段改成先「手机版新建代理后按下面逐项填写」（中文名 +「Surge 参数名」），再给 Mac 版 / 文本编辑用的整行。Hysteria2、TUIC、Hysteria v1 的客户端配置末尾加「只走 UDP：…TCP 延迟测试显示不出延迟属于正常；连不上多半是本地网络限制了 UDP，可换 VLESS Reality、AnyTLS」。依据和被否决的方案（install-config 一键安装要开下载服务、会替换整份配置）见 DECISIONS.md。验收：在 GitHub 打开 PR #11，CI「verify」全绿，日志里有 tests/clients.sh 的「every protocol with a share link follows its standard … Hysteria2 has /? and no alpn」「Surge is listed field by field …」和 tests/snell.sh 的「… and the same as form fields for Surge for iOS」；菜单样子见 `docs/menu-preview.txt`（Snell v6 的 Surge 段和 UDP 提示）。服务器上试：Lisa 更新到最新开发版后，菜单「2. 节点管理 → 选 test-hy2 → 3. 二维码 / 2. 原始分享链接」，用 Shadowrocket 扫码或复制链接导入；选 test-snell → 4 看 Surge 逐项列表，按它在 Surge 手机版新建代理。没做：Surge iOS 界面上字段的实际叫法没有官方文档，按「中文名（参数名）」写；AnyTLS、TUIC 链接没在 Shadowrocket 实测；顺带修了 CI 的 jq 1.7.1 对中文节点名 `index` 返回字节偏移的问题（改用正则拆分）。
- [x] v4 迁移安全修正：旧版证书续期与多用户 —— 2026-10-10 合并，提交 583daa1（PR #10）。读了 v3 `install.sh`：RenewTLS / UpdateGeo 都调 `reloadCore`，会 `systemctl start dodo258-sing-box`。现在：还有 Xray 节点、网站，或旧 sing-box 节点一个都没迁走时，**保留** RenewTLS / UpdateGeo，预览写明还有谁要靠它续证书；没有剩余服务才注释。迁走节点的旧单元 stop + disable 后再加 drop-in `/etc/systemd/system/<单元>.d/srm-migrated.conf`（`AssertPathExists=!/var/lib/srm/migrated-v3.json`），v3 续期重启它会失败（Assertion failed），不抢端口；迁移失败恢复时先删 drop-in；卸载 srm 时也删。和推荐不同：没用 `systemctl mask`，因为 v3 单元文件就在 /etc/systemd/system，mask 会报 File exists（DECISIONS.md 有理由）。装了 nginx 且 v3 续期会重启 sing-box 时，预览提示续期那天 v3 会提前退出、nginx 停着。多用户：v4 一个节点一个用户，只迁第一个，预览逐个列出其余用户「迁移后将无法连接」，确认前再提示总数，回车 = 返回；`--apply --yes` 也会列出。验收：在 GitHub 打开 PR #10，CI「verify」全绿，日志里有 tests/migrate.sh 的「the 7 v3 samples …」「with Xray, the website or v3 sing-box still running the cron jobs stay; the old sing-box is blocked …」「a node with 3 users …」，以及 install-live 的「with real systemd the taken-over v3 unit cannot be started again (v3 renewal restarting it fails, srm keeps the port) …」「a failed takeover … (no longer blocked)」；新样本在 `tests/fixtures/v3/xray-site`、`users3`，菜单样子见 `docs/menu-preview.txt` 末尾。服务器上试：在装着 v3（带 Xray 或网站）的机器上 srm → 回车看预览，应写「保留旧版定时任务」；迁移后 `systemctl start dodo258-sing-box` 应报 Assertion failed，`crontab -l` 里 RenewTLS 没被注释。没做：没在真实 v3 服务器上跑 v3 自己的 RenewTLS（CI 用真实 systemd 模拟 stop + start）；多用户全部迁移（要改 state 和所有协议，没做）；v3 续期那天 nginx 停着的问题无法在 srm 侧修，只在预览提示。
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
