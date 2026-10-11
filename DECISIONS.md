# 决定记录（只追加，不修改旧条目；按需读取）

<!-- 格式：
## YYYY-MM-DD 标题
- 决定：
- 理由：
- 备选/被否决的方案：
- 拍板人：用户 / Claude
-->

## 2026-10-10 v4 以 dodo-sbox 架构重写，只保留 sing-box
- 决定：放弃在 14851 行单文件上修补，以 dodo-sbox 的模块化架构重写；删除 Xray、上游残留协议、网站管理和 nginx 订阅；保留 Reality、AnyTLS、Hysteria2、多节点、节点级分流、证书、BBR；v3 冻结到 `legacy/v3`。
- 理由：卡顿、冗余和「不像工具」的根源都在单文件双核心结构；dodo-sbox 已经验证过同一套功能更好的实现。详见方案。
- 备选/被否决的方案：在 v3 上逐步删减（死代码和双核心交织，删减风险大、收益小）；把 dodo-sbox 公开取代本仓库（会丢掉本仓库的 10 星和现有用户的更新路径）。
- 拍板人：Claude（主人要求「好好整理」）；Snell 去留和正式发布待主人确认。

## 2026-10-10 协议范围按 sing-box 全支持；Snell 用官方 snell-server 单独部署；核心每日自动更新
- 决定：支持 sing-box 所有对外代理协议（VLESS Reality/TLS、Hysteria2、AnyTLS、SS2022、TUIC、Trojan、VMess、Naive、Hysteria v1）；Snell v5 用官方 `snell-server` 独立服务，ShadowTLS v3 由 sing-box shadowtls → direct(override) 转发；sing-box 和 snell-server 默认每日自动更新到最新稳定版，带校验和回滚。部署流程以 VLESS Reality 为默认首选。
- 理由：主人原话「singbox 支持哪些协议部署，你就加入什么，snell 就不放在 singbox 中部署」「各个协议能自动更新最新」；主人用 Surge 的 Snell+ShadowTLS，外部用户以 VLESS、Hysteria2、AnyTLS 为主。sing-box 1.14 虽有 snell inbound，但官方说明不支持 Snell v5 的 QUIC 代理模式。
- 备选/被否决的方案：用 sing-box 自带的 snell inbound（缺 QUIC 代理模式，主人不要）；用 SS2022+ShadowTLS 替代 Snell（主人习惯 Snell）；核心固定版本手动升级（主人要自动更新）。
- 拍板人：用户（方向）/ Claude（实现方式）

## 2026-10-10 Snell 默认 v6
- 决定：Snell 默认部署 v6（官方最新 v6.0.0rc2），可选 v5；snell-server 自动更新跟随所选大版本的最新构建（无正式版时含 beta/RC）。
- 理由：主人指出「snell 现在都 v6 了」；Surge 官方发布说明显示 v6 是当前主线，但尚无正式版；官方没说 v6 服务端是否兼容 v5 客户端，所以保留 v5 选项。
- 备选/被否决的方案：默认 v5（落后于主人在用的版本）。
- 拍板人：用户

## 2026-10-10 不自动更新：后台只检查版本并提示，用户手动更新
- 决定：取消核心自动更新；每日 timer 只查版本写缓存，菜单提示，用户执行 `srm update` 手动更新（先提示会断开几秒）。
- 理由：主人原话「自动更新会不会造成短暂断网？如果会断网话，就不要自动更新，用户可以手动更新，避免断网影响工作」。替换 sing-box / snell-server 二进制必须重启服务，现有连接会断开。
- 备选/被否决的方案：凌晨随机时刻自动更新（仍会断网，主人不要）。
- 拍板人：用户

## 2026-10-10 新手只用菜单选，不用敲命令
- 决定：所有功能都有菜单项；安装后直接进菜单；界面不出现「运行 srm xxx」；能选的不让填；检测到 v3 时菜单第一屏引导迁移。命令行子命令只给进阶用户和自动化。
- 理由：主人原话「直接让用户选，不要让他们输入任何命令。很多新手就是想着越简单越好」。
- 拍板人：用户

## 2026-10-10 state schema 2：多节点、节点级分流、端口 1–65535
- 决定：
  - 同一协议多个节点直接用 `nodes` 数组表示（骨架已支持），不再有单独的「多实例」菜单；部署菜单写明可重复部署，默认名自动编号（`vless`、`vless-2`…）。
  - policies 加可选 `inbounds`（节点 ID 列表，非空、不重复、必须是现有节点）；缺省表示全部节点。生成配置时每条规则单独出一条 route/DNS 规则并带 `inbound`，代理规则仍排在 DNS 解锁规则前面；冲突检查只在两条规则的节点范围有交集时报。
  - 规则限定的节点停用时，规则照样带着它的 ID（sing-box 1.14.1 实测接受不存在的 inbound 标签，只是匹配不到），不会因为过滤成空列表而变成全局规则；删除节点时从规则里去掉它，规则因此没有节点了就一并删除并提示。
  - 迁移：`state_upgrade` 按版本逐级迁移（1→2 只改 `schema`），在 `new_candidate` 和 `apply_state` 里调用，所以升级脚本后的第一次修改、回滚到旧版本的 generation 都会自动迁移；不改输入文件，只读页面两种版本都能读；遇到比脚本新的版本拒绝修改。
  - 端口 1–65535，随机仍在 10000–50000；systemd 单元加 `AmbientCapabilities=CAP_NET_BIND_SERVICE`（边界集也只留这一项），服务用户能监听 1024 以下端口。
  - 菜单里选节点用序号（空格分隔）；新规则回车 = 全部节点，替换已有规则时回车 = 沿用它原来的节点，输入「全部」才改成所有节点。命令行用 `--nodes ID,ID`，`--nodes all` 改成所有节点，不写时替换的规则保留原来的节点（审查指出：否则替换同名规则会悄悄变成全局）。
  - 端口放开后，TCP 节点不能占用正在使用的 ACME 证书续期验证端口（记录在 `acme-accounts/<域名>/challenge-port` 的 80 或 443）：部署前、申请或复用证书后、改端口和重新启用时都检查；自动验证方式会避开正在部署的节点端口和 state 里所有 TCP 节点的端口（包括停用的）。UDP 节点（Hysteria2）不受限制。否则续期每天失败，到期后所有 TLS 节点一起断（审查发现）。
- 理由：方案「state」一节；v3 的节点级 DNS 分流和多实例要有对应功能。逐条规则输出比合并成一条更容易限定范围，全局规则的效果不变。
- 备选/被否决的方案：停用节点从规则里过滤掉（可能过滤成空列表，sing-box 会把它当成不限 inbound，等于悄悄扩大范围）；删节点时把没有节点的规则改成全局（扩大范围）或拒绝删除（新手卡住）；开机自动把旧 state 改写成 schema 2（要改动线上 generation，不走事务）。
- 没验证：DNS 规则带 `inbound` 只验了生成结果和 `sing-box check`，没有做「客户端 DNS 查询经 hijack-dns 后按 inbound 选 unlock」的真实流量测试（要在 53 端口起 DNS 夹具，现有的 `tests/routing.sh` 只在授权测试服务器上跑）；route 规则的限定有真实流量测试。
- 已知限制：写成 schema 2 后，手动回滚到只认 schema 1 的旧脚本就不能再修改节点（会提示数据格式不合法）；v4 还没发布，只影响开发版。
- 没做：方案里「节点加 `transport` 字段」放到「补齐其余协议」那条做（VLESS+TLS 的 tcp/ws/grpc/httpupgrade 才需要）。已经装好的 v4 开发版服务器不会自动重写 systemd 单元，用 1024 以下端口要先重装；v4 还没发布，正式安装都会带上。
- 拍板人：Claude

## 2026-10-10 补齐其余服务端协议：注册表新增 7 种协议、自签证书加 pin、各客户端配置片段
- 决定：
  - 协议类型名：`shadowsocks`（SS2022）、`tuic`（v5）、`vlesstls`（VLESS+TLS，节点字段 `transport` = tcp/ws/grpc/httpupgrade）、`trojan`、`vmess`（TLS+ws）、`naive`、`hysteria`（v1）。原有 `vless` 仍是 Reality。
  - 注册表的 `transport` 钩子可以返回 `tcp udp`：Shadowsocks 同一端口同时开 TCP 和 UDP，防火墙、健康检查、证书续期端口避让都按每种传输层展开（`proto_jq_transports` 返回数组）。
  - 节点的 `sni` 改为可选，只有不用 TLS 的协议（Shadowsocks）不写；其余协议在自己的 validate 里要求 `sni`。
  - 自签证书只给客户端能固定证书的 TUIC、Hysteria v1、Hysteria2（方案的协议表也要求 Hysteria2 无域名时自签 + pin，同一套代码一起做了）。服务器地址是 IP 且没给 `--sni` 时默认选自签，SNI 默认 `www.bing.com`；给了 `--sni` 域名就默认申请 Let's Encrypt（审查发现：否则用户给了域名却悄悄拿到自签证书，链接还带 insecure）。自签时用 `--cert selfsigned --sni 域名` 可改 SNI。每个节点一份，放 `/var/lib/srm/selfsigned/<节点ID>/`（root:srm 640），有效期十年，不参与续期，证书页单独提示。部署失败时删掉；删除节点时保留（「回滚配置」恢复的上一份配置可能还引用它，卸载时随 `/var/lib/srm` 一起删）。state 里记 `cert_sha256`（证书 DER 的 SHA-256 十六进制，Surge `server-cert-fingerprint-sha256`、mihomo `fingerprint`、Hysteria2 链接 `pinSHA256` 用）和 `pubkey_sha256`（公钥 SPKI 的 SHA-256 base64，sing-box `certificate_public_key_sha256` 用，实测不需要 insecure 就能连自签证书，指纹不对就连不上）。
  - 自签节点的分享链接：Hysteria2 写 `insecure=1&pinSHA256=…`（官方客户端的 pinSHA256 只在常规校验通过后才检查，自签必须同时 insecure，见 v2.hysteria.network 客户端文档）；TUIC、Hysteria v1 的链接格式没有指纹参数，只能写 `allow_insecure=1` / `insecure=1`。客户端配置页会提示「只导入链接的客户端会跳过证书校验」，并给出指纹让能填的客户端填上；sing-box、Clash Meta、Surge 片段都带指纹，不跳过校验。
  - 证书提问顺序改为先选证书方式、再问域名；服务器地址是 IP 时域名不再默认填 IP（以前会拿 IP 去申请证书）。
  - Shadowsocks 只提供 `2022-blake3-aes-128-gcm`（Surge 和 mihomo 都支持，密钥 16 字节），不让用户选加密方式。链接按 SIP002：2022 方法的 userinfo 不做 base64，方法和密码百分号编码。
  - VLESS TLS：tcp 用 Vision 流控；ws / httpupgrade 的 ALPN 只给 http/1.1（ws 不能走 h2），grpc 给 h2；路径和 gRPC 服务名随机生成。VMess 只用 alterId 0（AEAD），链接用 v2rayN 的 base64 JSON 格式。
  - Naive 只开 TCP（HTTP/2），不开 QUIC；链接主机用证书域名（Naive 客户端按域名连接和校验证书）。Clash Meta 和 Surge 没有 Naive 客户端。
  - Hysteria v1 服务端上下行上限 1000 Mbps；客户端片段和链接写上行 30、下行 100 Mbps（v1 客户端必须填带宽），用户可在客户端里调高。
  - 客户端配置片段：注册表新增可选钩子 `clash`（mihomo 代理，一行 JSON 流式写法，可直接放进 YAML 的 proxies 列表）和 `surge`（Surge 代理行）；Surge 不支持 VLESS、Naive、Hysteria v1（manual.nssurge.com/policies/overview 的协议表）。节点管理「4. 客户端配置」一屏列出 sing-box / Clash Meta / Surge，Shadowrocket、v2rayN 用原始链接或二维码。命令行 `srm export ID clash|surge|clients`。
  - CI 下载固定哈希的 mihomo v1.19.32，用它把每个 Clash Meta 片段实际跑一遍流量；另从同一个固定哈希的 sing-box 压缩包里解出 `libcronet.so` 放在核心旁边，让 sing-box 的 naive 客户端在 CI 里真跑（官方文档：Linux purego 构建运行时从核心所在目录或系统库路径加载它）。服务器不装这个库，服务端用不到。
- 理由：方案「协议」表；验收要求每个协议的配置过 `sing-box check`、真实流量走通、链接格式有单元测试。参数名和格式都对照了官方文档或客户端源码（Surge 手册、mihomo 文档、SIP002、Hysteria v1/v2 URI 文档、v2rayN/NekoBox 源码），出处写在代码注释里。
- 备选/被否决的方案：自签证书节点的链接不写 insecure（TUIC、Hysteria v1 的链接客户端会直接连不上）；自签证书和域名证书放同一目录（同名 SNI 会和 Let's Encrypt 证书冲突，续期逻辑也会误判）；Shadowsocks 让用户选 128/256（多一个问题，安全性差别对代理场景不大）；Naive 同时开 QUIC（要多管一个 UDP 端口，Naive 客户端默认也走 HTTP/2）。
- 没验证：Surge 配置行只做了格式单元测试（Surge 没有 Linux 版，CI 跑不了）；只测了 TCP 流量，各协议的 UDP 转发没有单独测；curl 不能当 Naive 客户端（sing-box 的 naive 入站要求 naive padding，实测报 `missing naive padding`），所以 Naive 只用 sing-box 自带的 naive 客户端验证，核心编译时不带它的话测试会打印跳过原因。
- 拍板人：Claude

## 2026-10-10 Snell v6（可选 v5）+ ShadowTLS v3：官方 snell-server 独立服务，sing-box 做 ShadowTLS 前置
- 决定：
  - 链路按方案做，实测可行：sing-box 1.14.1 的 `shadowtls` inbound（version 3、strict_mode）用 `detour` 交给一个 `direct` inbound，后者用 `override_address`/`override_port` 转到 `127.0.0.1:<local_port>` 上的 snell-server。本机先用 HTTP 后端验证转发，CI 里再用真实 snell-server 端到端跑通，所以没有引入独立的 shadow-tls 二进制。direct inbound 不写端口也会自己开一个监听（sing-box 默认绑 127.0.0.1 随机端口），因此显式写 `listen: 127.0.0.1`、`network: tcp`。
  - 官方 snell-server 固定版本并校验 zip 的 SHA-256（官方不提供校验和）：v6.0.0rc2、v5.0.1，各有 amd64 / aarch64 两个哈希；下载后先运行 `-v` 核对大版本（6.0.0rc2 自报 `v6.0.0`，所以只核对大版本），顺带确认二进制能在本机加载。v6 是动态链接的 glibc 程序。装 Snell 时才按需安装 `unzip`，不加进所有协议的依赖。跟进新版本属于「核心更新」那条待办。
  - 服务端配置照各版本 `snell-server --wizard` 生成的格式写，只把 listen 改成 `127.0.0.1:<local_port>`：v6 是 `listen / psk / mode / dns-ip-preference = default`，v5 是 `listen / psk / ipv6 = false`。v6 的配置项以二进制 `--help` 为准（listen、psk 12–255 字节、mode、dns、dns-ip-preference、ipv6（已废弃）、egress-interface），出处写在代码注释里。
  - 通用「伴随服务」机制，不只为 Snell 写死：注册表加可选钩子 `sidecar`（节点的 systemd 单元名）和 `sidecar_render`（把节点的文件写进 generation）；节点字段 `local_port` 是伴随服务的本机端口，和所有节点端口一起查重、算作已占用。snell 的配置和指向对应版本二进制的软链接都放在 generation 的 `sidecar/<节点ID>/` 里，单元模板 `srm-snell@.service` 从 `/var/lib/srm/current/sidecar/%i/` 启动。这样切换和回滚 generation 时，配置和版本一起切换。每次应用配置都先重启所有启用节点的 snell-server，再重启 sing-box；停用或删除的节点执行 `disable --now`。健康检查要求每个 snell 单元都是 active，并且本机端口在监听；健康检查失败时，回滚会按旧 state 恢复伴随服务。状态、日志、卸载、「重启节点」都覆盖这些单元，防火墙只放行节点的 TCP 端口。snell-server 用 `srm` 用户运行，单元的加固项和 srm.service 相同，并且去掉所有 capability。
  - 客户端输出：
    - Surge 配置行：`psk=…, version=6, mode=…, reuse=true, shadow-tls-password=…, shadow-tls-sni=…, shadow-tls-version=3`；v5 不写 mode。依据：manual.nssurge.com/policies/snell.html 写明 version 必须显式写、mode 只给 v6、低于 v6 写 mode 会报配置错误；tls.html#shadow-tls 写明 shadow-tls-version 默认是 2。
    - Snell 没有通用分享链接，「原始链接」和二维码给的是 Surge 配置行，并在页面上说明。
    - sing-box 客户端给两个出站：snell 出站 detour 到 shadowtls 出站。sing-box 1.14 的 snell 出站只支持 v4 和 v6，实测填 v5 会报 `unsupported version: 5`，所以 v5 节点用 v4 客户端；依据是 Surge 发布说明「v5 服务端兼容 v4 客户端」，CI 实测能连通。
    - mihomo：snell 支持 v1–v5（v5 按 v4 发送），不支持 v6，所以只给 v5 节点出写法：`obfs-opts: {mode: shadow-tls, host, password, version: 3}`。v6 节点在页面上说明「Clash Meta 不支持 Snell v6，要用请另部署 v5 节点」。
  - ShadowTLS 握手目标和 Reality 共用同一份审核过的列表（携程 / 西瓜视频），检查方式也相同（TLS 1.3 + 证书 + h2）。节点管理里可以切换目标，凭据重置会同时换 PSK 和 ShadowTLS 密码。
  - 命令行新增通用参数 `--proto-version 6|5`、`--proto-mode default|unshaped`；名字里不带协议名，方便以后别的协议复用，用在不支持的协议上会报错。菜单里依次问版本（回车 = v6）、v6 模式（回车 = default）、握手目标（回车 = 携程）。
  - Snell 注册在 Hysteria2 后面，对应方案里的「常用」位置。部署菜单里 Shadowsocks 及以后的序号因此后移一位；v4 还没发布，「快速部署」那条会重排菜单。
  - 审查前自己发现并修好的两个问题：
    - 卸载时 `systemctl disable --now srm.service srm-renew.timer` 只要 timer 不存在，整条命令就失败，服务不会被停掉。没申请过证书的服务器在节点运行时卸载会报「服务仍在运行」。现在改成逐个单元停用。
    - systemd 默认 10 秒内最多启动 5 次，连续几次修改节点就会撞上，启动失败报 `start-limit-hit`。CI 有一次间歇性失败就是这个原因：撤掉修复后日志明确显示 `Failed with result 'start-limit-hit'`。现在主动重启前先 `systemctl reset-failed`，systemd.unit 文档说明这会清空启动计数；崩溃后的自动重启仍然受限制。
  - 独立审查提的建议采纳了 4 条：
    - snell 的本机端口只在 10000–32767 里选，避开 Linux 默认的临时端口范围 32768–60999。否则某个活动连接的源端口恰好等于它时，snell-server 重启后可能绑不上。
    - 停用的节点重新启用时，先检查本机端口有没有被别的程序占了，被占就直接说明原因，不再等健康检查失败、回滚才发现。
    - 命令行的 `--proto-version`、`--proto-mode` 只接受 `6|5`、`default|unshaped`，不再把菜单序号当参数值。
    - 给下载校验补了测试：用格式正确、但哈希对不上的 zip 验证不会被安装。
  - 剩余风险：sing-box 启动时，direct inbound 的随机监听端口是内核从临时端口范围里分的。如果碰巧分到另一个节点还没来得及绑定的对外端口，sing-box 会启动失败，然后自动回滚。概率约为万分之一级别，所以没有为此再加一个端口字段。
- 理由：方案「Snell + ShadowTLS」一节；主人要求 Snell 单独部署、用官方 snell-server；前置交给 sing-box，可以复用配置校验、原子切换和回滚。
- 备选/被否决的方案：
  - 独立 shadow-tls 二进制：链路实测可行，用它反而多一个要下载、更新的程序。
  - sing-box 自带的 snell inbound：1.14 起支持 v5/v6，但主人要求用官方 snell-server。
  - snell 配置直接写进 `/var/lib/srm/snell/`、不放进 generation：回滚时配置会和 sing-box 前置对不上。
  - 每个节点单独生成一个 unit 文件：模板单元加 generation 软链接更简单，删除节点也不用清理文件。
  - v5 节点转发 UDP 来支持 QUIC 代理模式：注册表的传输层是按协议定义的，不是按节点；sing-box 自己的实现也有意不支持这个模式。QUIC 流量会被应用回落到 TCP，页面上已说明。
- 没验证：
  - Surge 本身连接：Surge 没有 Linux 版，配置行只有格式单元测试，参数名对照官方手册。
  - 握手目标用真实的 www.ctrip.com：CI 用本地 TLS 1.3 服务器和测试证书代替，避免外网波动。
  - aarch64 的 snell-server：只固定了哈希，没有在 arm64 上运行过。
  - snell 在真实 systemd 下的端到端流量：systemd 测试只验证了单元启动、本机监听和 sing-box 健康检查；真实流量在 `tests/snell-traffic.sh` 里用同一份 generation 文件验证。
- 已知限制：
  - 流媒体分流对 Snell 节点不生效，因为 snell-server 自己发起出站连接。分流菜单和「查看」页会列出这些节点并说明。
  - 已装好的 v4 开发版不受影响，第一次部署 Snell 时会写入单元模板。
- 拍板人：Claude

## 2026-10-10 核心更新的实现取舍（待办「核心更新」）
- 决定：
  - sing-box 最新版取 GitHub `/releases/latest`（GitHub 定义上不含 draft 和 pre-release），再拒绝 `prerelease`/`draft` 为真或 tag 带后缀的结果；只在比已装版本新时更新，不降级；附件 SHA256 用 API 返回的 `digest`。安装也取最新稳定版，Release API 不通时退回本脚本测试过的 1.14.1（固定 SHA256）。CI 的单元测试仍用固定的 1.14.1。
  - snell-server 只检查和更新「现有节点用到的大版本」，没有 Snell 节点就不查；部署新节点仍装固定 SHA256 的已知构建，手动更新才取发布说明里的最新构建。官方不给校验和，新构建靠 HTTPS 下载 + 运行 `-v` 核对版本号（去掉 rc/beta 后缀比较，因为 rc2 自报 v6.0.0）；实际装的完整版本号写进 `/opt/srm/snell/v<大版本>/version`。
  - 每日检查用 `srm-version-check.timer`（凌晨 2 点起随机 4 小时内），服务只跑 `srm update-check run`，systemd 沙箱 `ProtectSystem=strict`、只允许写 `/var/lib/srm`、不带任何 capability；检查不拿锁（拿锁会触发「恢复中断操作」，可能重启服务）。关闭后写 `/var/lib/srm/update-check.off`，重装也保持关闭，并删除缓存，菜单不再显示旧提示。
  - 菜单「5. 更新」里确认用「1. 确认更新 / 0. 返回」，回车 = 返回；只更新脚本不重启服务，不弹确认。
  - 命令行 `srm update-script`、`srm update-core` 去掉，统一成 `srm update [core|snell|script] [--yes]`（v4 尚未发布，没有外部用户依赖旧子命令）。
  - Snell 的版本查询、下载放在协议注册表的 `program_*` 钩子里，更新模块只按钩子分派，不出现协议名。
  - 「全部更新」：sing-box 和 Snell 不再跟脚本版本绑定，它们查不到或下载失败时保留已更新的新脚本、整体报失败；只有新脚本加载不了才退回旧脚本。sing-box 服务停着时更新 Snell 只换程序，不重启、不拉起节点。新的 Snell 构建试运行 `-v` 时以 srm 用户身份执行（root 下用 runuser）。
  - 风险：安装取最新稳定版只限最低 1.14；将来 1.15 若改了配置格式，新装机器部署节点会在 `sing-box check` 处失败（不会破坏已有节点）。届时要么更新生成配置的代码，要么把安装限制到测试过的小版本。
- 理由：主人定的「后台只查、菜单提示、手动更新」；`/releases/latest` 一次只下 300 多 KB，列表接口一页 10 条就 3.5MB；只查在用的大版本避免没有 Snell 的用户每天访问第三方网站。
- 备选/被否决的方案：拉 Release 列表自行挑稳定版（体积大，翻页才能保证找到）；Snell 新构建要求固定 SHA256（每出一个构建都要发新脚本，等于不能跟进）；timer 命名 `srm-update-*`（和「不自动更新」的守护测试冲突，也容易误解为自动更新）。
- 拍板人：Claude

## 2026-10-10 快速部署流程与客户端配置片段
- 决定：
  - 菜单「1. 添加节点 · 快速部署」、没有节点时打开 `srm` 直接进入的列表、`srm add`（不带 `--yes`）共用同一套流程：先选协议（1 VLESS Reality 回车即选；2 Hysteria2；3 Snell + ShadowTLS；4 AnyTLS；5 更多协议，不需要域名的排前面），之后只问：需要证书的协议的域名（唯一手填的内容），再加最多 2 个带默认值的问题，按「协议自己的一个问题 → 端口 → 节点名」取前两个。所以 Reality / Hysteria2 / AnyTLS 等问端口和节点名；Snell 问「版本+模式」（v6 default / v6 unshaped / v5 合成一题）和端口，节点名用默认值（节点管理里能改）；VLESS TLS 问传输方式和端口。
  - 不再提问的：服务器地址（部署时访问 `https://www.cloudflare.com/cdn-cgi/trace` 取公网 IP 和国家代码，先 IPv4 后 IPv6，各 8 秒超时，写进 state；查不到时菜单里让用户填，`--yes` 报错要 `--host`）；Reality / ShadowTLS 握手目标（按内置列表依次做 TLS 1.3 + h2 + 证书链检查，取第一个通过的）；证书方式（无域名且协议能用自签时自签，否则 Let's Encrypt 自动验证；80 和 443 都被占时菜单里才给「网站目录验证 / 导入证书」两个选项）；BBR（默认保持现状，在菜单 6 里开）；部署前的 y/N 确认（只用数字和回车，任一步输入 0 返回）。
  - 节点名默认「协议-国家代码」，如 `vless-JP`，重名自动编号；查不到国家时用协议名。
  - 域名先检查再申请证书：`getent ahosts` 的结果要包含本机地址（节点地址、检测到的公网 IP、本机网卡地址之一）。菜单里当场提示，并给「1 重新检查 / 2 换一个域名 / 3 没有域名，换一个协议 / 4 仍然申请（开了 CDN 代理时）/ 0 返回」；域名那一步直接回车也等于「没有域名，换一个协议」。命令行解析不对就报错退出，开了 CDN 的用户改用 `--cert webroot` 或 `--cert import`（这两种方式和已有有效证书时不检查解析）。
  - 部署完一屏给全：服务器和端口、云安全组要放行的 TCP/UDP 端口、分享链接和本地二维码，以及 Surge / Clash Meta / sing-box / Shadowrocket / v2rayN 里该协议支持的几段；不支持的客户端不出现。节点管理「4. 客户端配置」用同一个函数。`srm add … --json` 输出同样的内容（`share_link`、`firewall`、`clients.{surge,clash_meta,sing_box,shadowrocket,v2rayn}`，没有的键不出现；Snell 没有 `share_link`），进度信息写到 stderr。
  - 注册表新增必需钩子 `domain`（none / optional / required）和 `link_clients`（能导入分享链接的客户端），可选钩子 `hint`（列表说明）和 `variant`（协议自己的那一个问题）；第一页的协议和顺序是 `QUICK_PROTOCOLS`。新协议注册后自动出现在「更多协议」里。
  - 能导入分享链接的客户端：v2rayN 按它的源码（`ServiceLib/Enums/EConfigType.cs` 和 `Handler/Fmt/`，7.25.4）支持 VMess、Shadowsocks、VLESS、Trojan、Hysteria2、TUIC、AnyTLS、Naive，不支持 Hysteria v1 和 Snell。Shadowrocket 没有公开的协议清单：AnyTLS 按 App Store 版本说明（2.2.64 起）；VLESS Reality、Hysteria v1/v2、TUIC、Trojan、VMess、SS2022 按社区普遍用法；Naive 查不到可靠来源，不列；Snell 的分享内容是 Surge 配置行，两者都不能导入。
  - `srm add` 新增 `--domain`（证书域名，不需要域名的协议拒绝）和 `--json`；`--host` 改为可选。`--cert` 只接受 auto/webroot/import/selfsigned（菜单不再问证书方式，数字写法去掉了）。
  - `srm add` 交互运行时没部署出节点（输入 0、读到输入结尾）退出码为 1、`--json` 不输出；在菜单里同样的情况不算失败。`srm add <协议>` 里选「没有域名，换一个协议」会打开快速部署列表。命令行指定了 `--cert webroot|import` 却没给路径时，交互模式会问路径（审查发现原先报「非交互模式缺少参数」）。
  - 节点地址是域名、又查不到本机公网 IP 时（NAT 且访问不到 Cloudflare），没有可比对的地址，域名解析检查只提示跳过、不拦截。
  - `srm install` 在终端里运行完会直接打开菜单（没有节点就是快速部署）；非终端（自动化、CI）不进菜单。
  - 已有启用的节点时，添加节点前显示一句「应用新配置会重启服务，已有节点的连接会断开几秒」，不再二次确认（方案「更新」一节）。
- 理由：方案「交互原则」「部署流程」；主人要新手只用选、不用填。
- 备选/被否决的方案：每个协议都问端口和节点名、Snell 版本另问（Snell 会有 3 个问题，超过方案的上限）；用第三方 GeoIP 接口查地区（多一个请求，Cloudflare trace 一次就带国家代码）；域名解析不对直接拒绝（开了 CDN 代理的用户也能用 http-01 申请证书，所以菜单留「仍然申请」，命令行留 webroot/import）；Shadowrocket 按协议全部列出（没有官方清单，不确定的宁可不列）。
- 没验证：Shadowrocket、v2rayN 的实际导入（没有 iOS/Windows 环境，只按源码和链接格式）；真实 Cloudflare trace 和 `getent` 只在代码里调用，测试里用替身；真实 Let's Encrypt 申请仍没有在测试里跑。
- 拍板人：Claude

## 2026-10-10 旧版迁移（srm migrate）的取舍
- 决定：
  - 协议相关的读取都放在注册表的可选钩子里：`v3_import`（把 v3 sing-box 配置里的一个 inbound 转成节点字段；不是本协议返回 1，是本协议但迁不了返回 2 和原因）、`v3_scan`（v3 自己存文件的节点，目前只有 Snell 的 `snell-shadowtls/nodes/*.env`，按文本解析，不 source）、`v3_prepare`（应用前安装节点需要的程序，Snell 装 v5）。`lib/migrate.sh` 只做通用部分：逐个读 `sing-box/conf/config/*.json`（含 `30_`–`33_`）、证书、停启服务、crontab、菜单。
  - 凭据原样保留，正在用的客户端不用改：Reality 的公钥由私钥用 openssl 推出（不依赖 `reality_key` / `.key` 文件，CI 用真实核心核对过推导结果）；shortId 沿用 v3 链接里那个固定值 `6ba85179e30d4fc2`（v3 所有部署共用，想换成独立的 shortId 只能重新部署节点）。ws 的 early data（v3 的 sing-box 客户端会发）用节点字段 `early_data` 保留，服务端加 `max_early_data 2048 / Sec-WebSocket-Protocol`；实测去掉这个字段 v3 客户端就连不上，不带 early data 的客户端照常能连。Naive 用户名、Snell 的 PSK / ShadowTLS 密码放宽为字母数字和 `._~-`（新部署仍是随机十六进制）。
  - 同一端口有多个用户时只迁移第一个，其余用户在预览里逐个列名字（v4 每个节点一个凭据）。Snell v4 节点改由 snell-server v5 运行（v5 兼容 v4 客户端），节点 DNS 设置不迁移；ShadowTLS / Reality 握手目标不是「同名域名:443」的不迁移。
  - 迁不了的都列出原因：Reality + gRPC、经 nginx 转发（只监听本机）的节点、socks 等 v4 没有的入站、分流和出站设置文件（含 `31_` / `33_` 节点级 DNS 分流：v3 用的是 geosite 规则集和正则，v4 只有平台域名后缀规则，自动转换不可靠，提示到菜单「3. 流媒体分流」重设）、Xray 核心的节点、网站、订阅。
  - 证书：域名证书复制进 srm 的证书目录，来源标记为新的 `v3`；v3 的续期定时任务停用后，srm 每日续期检查在到期前 30 天对它向 Let's Encrypt 重新申请，成功后变成普通的 `acme` 证书。srm 已有同域名的有效证书时沿用 srm 的。自签证书（v3 Hysteria2 无域名模式）复制到 `selfsigned/<节点ID>`，并算出指纹，只用于能校验指纹的协议。
  - 执行顺序：先装好 srm、准备程序和证书、生成完整配置并通过 `sing-box check`，这之前旧服务一点不动；然后停止并停用（disable，防止重启后两边抢端口）这些节点所属的旧服务，再走正常的 apply_state 事务。失败或被中断就按原来的运行 / 开机自启状态恢复旧服务。只停有节点迁走的服务：`dodo258-sing-box`（以及指向 `/etc/v2ray-agent` 的旧名 `sing-box.service`）、迁走的 Snell 节点的 `dodo258-snell-*` / `dodo258-shadowtls-*`。
  - **和方案不同：不停 Xray 服务**。方案写了停 `dodo258-xray`，但 Xray 的节点 v4 一个都迁不了，也不会跟 srm 抢端口，停掉只会让这些用户断线；预览里写明「旧 Xray 服务继续运行」。
  - crontab 只注释 `/etc/v2ray-agent/install.sh RenewTLS` 和 `UpdateGeo` 两类（它们会重启旧服务），行首加「# srm 迁移后停用：」；网站发布 `WebsitePublish` 不动，网站本来就不迁移。
  - 菜单：发现 `/etc/v2ray-agent` 且还没迁移过时，打开菜单第一屏（在快速部署之前）问「发现旧版节点，要迁移过来吗？」，回车 = 先看能迁和不能迁的内容（只读本地文件，不联网），再「1. 确认迁移 / 0. 返回」，回车 = 返回。选「否」后主菜单多一项「9. 迁移旧版节点」。迁移成功写 `/var/lib/srm/migrated-v3.json`，之后不再提示。命令行 `srm migrate` 默认只预览，`--apply` 执行（不带 `--yes` 会再确认），`--host` 指定客户端连接地址（默认部署时查一次公网 IP，和快速部署一样）。
  - 迁移后的节点名为「协议-端口」（如 `vless-443`），节点管理里可改。
  - 独立审查后补充：注释 RenewTLS / UpdateGeo 后，继续运行的旧版网站和 Xray 节点用的 `/etc/v2ray-agent/tls` 证书不再续期、geo 不再更新，预览里明确提示（不保留这两行：它们会重启旧 sing-box 服务，和 srm 抢端口）。迁移后 80 和 443 都会被占用（例如 nginx 占 80、节点占 443）时，预览不承诺自动续期，改为提示到期前空出 80 端口；证书管理页对 v3 来源的证书按当前端口情况显示能否自动重新申请。没有任何可迁移节点时，预览一次后记下，第一屏不再每次询问，主菜单第 9 项保留（用户处理掉预览里的原因后还能从菜单迁移）。已知限制：v3 安装 acme.sh 时自带的 `acme.sh --cron` 定时任务不属于 v3 脚本，迁移不动它；80 端口空着时它可能自己续期并改写 `/etc/v2ray-agent/tls`（这不是 srm 改的），所以预览里网站 / Xray 证书「不再自动续期」的提示偏保守。
- 理由：方案「迁移」一节和待办验收标准；正在用的客户端不用改是迁移对用户最重要的一点，所以凭据、端口、证书都原样保留，宁可把迁不了的列清楚。
- 备选/被否决的方案：读 `reality_key` 取公钥（文件可能过期或缺失）；把多用户拆成多个节点（同一端口只能有一个节点）；把 v3 的 DNS 分流转换成平台规则（geosite 规则集离线没法展开成域名列表）；迁移时立即重新申请证书（80/443 可能被 nginx 或节点占着，失败会卡住迁移）；导入证书按 `import` 处理（v3 续期停了以后没人续，最多 90 天后节点全断）。
- 没验证：没有在真实的 v3 服务器上跑过（用 5 份按 v3 源码写出的脱敏样本，加 CI 里真实 systemd 的替身服务）；Reality 的真实流量（握手要访问外网目标，只做了 `sing-box check` 和公钥核对）；v3 证书到期前的真实 Let's Encrypt 重新申请（只有单元测试）。
- 拍板人：Claude

## 2026-10-10 迁移安全修正：旧版定时任务保留与否、旧服务禁止启动、多用户
- 决定：
  - 读了 v3 `install.sh`：`RenewTLS` 只在证书剩 1 天时续期，续期时停 nginx 和核心、`acme.sh` 续期、`reloadCore`（Xray 在就重启 Xray；没有 Xray，或 sing-box 带 Hysteria2 / TUIC / socks5 时重启 `dodo258-sing-box`），最后才启动 nginx；`UpdateGeo` 下载 geo 后同样 `reloadCore`。重启 sing-box 用的是 `systemctl start dodo258-sing-box.service`，启动后 `pgrep` 不到进程就打印「sing-box重启失败」并 `exit 0`。
  - 有剩余 v3 服务（Xray 节点、网站，或 sing-box 节点一个都没迁走时的旧 sing-box）就**保留** `RenewTLS` / `UpdateGeo`，预览写明还有谁要靠它；没有剩余服务才注释。
  - 迁走节点的旧单元除了 stop + disable，再加一个 drop-in `/etc/systemd/system/<单元>.d/srm-migrated.conf`：`[Unit] AssertPathExists=!/var/lib/srm/migrated-v3.json`，`daemon-reload` 后 `systemctl start` 报 Assertion failed，v3 续期重启它会失败，不会和 srm 抢端口。迁移失败或中断时先删掉 drop-in 再恢复运行 / 自启。
  - **和待办推荐不同：没用 `systemctl mask`**。v3 的单元文件就在 `/etc/systemd/system`，`systemctl mask` 在那里已有同名文件时直接报「File … already exists」失败（mask 是在同一路径放指向 /dev/null 的链接）；要 mask 只能先挪走或删掉 v3 的单元文件。drop-in 不动 v3 的文件，效果一样（启动失败），而且条件挂在 srm 的迁移记录上：卸载 srm 时按迁移记录删掉这些 drop-in（旧单元仍是停用状态，卸载时提示怎么重新启用），就算 drop-in 留下，迁移记录随 /var/lib/srm 删除后它也不再起作用，不会把用户困住。独立审查后补充：nginx 提示不只看网站，装了 nginx 就提示（v3 续期总是先停 nginx，经 nginx 转发的 Xray 节点和伪装页也受影响）；`--apply --yes` 跳过预览时也列出连不上的用户；迁移记录写入失败会报错。
  - 已知后果，预览里写明：网站还在、且 v3 续期时会重启 sing-box（按 v3 `readInstallType` 判断：没有 Xray，或 sing-box 带 06 / 09 / 20 配置）时，续期那天 v3 会在重启 sing-box 失败后提前退出，nginx 停着，要用户手动 `systemctl start nginx`。不封住旧单元也一样会失败（srm 占着端口，旧 sing-box 起不来），还会每 10 秒重试，所以封住仍是更好的选择；v3 脚本冻结不改。
  - 多用户：v4 每个节点一个凭据，改成多用户要动 state、全部协议的配置生成、分享链接和客户端片段，不在这条里做。预览逐个列出不迁移的用户（name，没有就 username / email / 第 N 个用户），写「下面这些用户迁移后将无法连接」，确认前再提示一次总数，回车 = 返回。
- 理由：待办验收标准；续证书和不抢端口两个都要，旧版续期失败的影响比证书全部过期小。
- 备选/被否决的方案：`systemctl mask`（见上，对 /etc 里的单元文件无效）；挪走 v3 单元文件再 mask（改了 v3 的文件，卸载 srm 后还要用户自己恢复）；给旧单元换成空配置的 ExecStart 让 v3 重启「成功」、nginx 能正常启动（太绕，还要常驻一个空跑的旧 sing-box）；一律注释定时任务（Xray / 网站证书 90 天内过期）。
- 没验证：没在真实 v3 服务器上跑 v3 自己的 RenewTLS（CI 用真实 systemd 模拟它的 stop + start 两步）；mask 失败的说法来自 systemd 行为和公开报错帖，没有单独在 CI 里跑。
- 拍板人：Claude

## 2026-10-10 客户端导入修正：分享链接按规范、Surge 逐项列出、只走 UDP 的提示
- 决定：
  - 分享链接逐个对照规范（规范链接写在 `lib/protocols.sh` 每个 `share_uri` 上方），规范里没有的参数不加：
    - Hysteria2 按官方 https://v2.hysteria.network/docs/developers/URI-Scheme/ 改成 `hysteria2://密码@主机:端口/?sni=…[&insecure=1&pinSHA256=…]`：加上 `?` 前的 `/`，去掉规范没有的 `alpn`（主人实测这个格式能导入 Shadowrocket，带不带 pinSHA256 都行）。pinSHA256 用小写无冒号的 hex（规范没规定格式，官方客户端读取时会统一成小写并去掉冒号和连字符）。自签证书仍带 `insecure=1`（官方客户端先做正常校验再比对 pin）。
    - AnyTLS 按 anytls-go `docs/uri_scheme.md`（https://github.com/anytls/anytls-go/blob/main/docs/uri_scheme.md）同样加 `/`，参数只有 `sni`。
    - 其余格式已经符合规范，没有改动，只补了依据：VLESS Reality / VLESS TLS 按 Xray-core discussion #716（`alpn` 是其中的字段）；Trojan 用 trojan-gfw 的 `trojan://密码@主机:端口`（官方没有定义查询参数），查询参数沿用 v2rayN / mihomo 实际使用的 #716 字段 `security`、`sni`、`type`；VMess 按 v2rayN 分享链接 ver 2（JSON 的值全部是字符串）；SS2022 按 SIP002（AEAD-2022 不做 base64，method 和密码做百分号编码）；TUIC 没有官方格式，按事实标准 https://github.com/daeuniverse/dae/discussions/182（NekoBox、v2rayN、mihomo 都引用它）；Hysteria v1 按 https://v1.hysteria.network/docs/uri-scheme/；Naive 按 DuckSoft 的提案 https://gist.github.com/DuckSoft/ca03913b0a26fc77a1da4d01cc6ab2f1 。
    - `tests/clients.sh` 对每种有分享链接的协议做两类检查：一是精确比对整条链接；二是检查链接的整体形状、只用规范定义的参数、参数不重复、必填参数都在（Hysteria v1 的带宽是必填）。注册表新增协议却没有被这项检查覆盖时，测试会失败。
  - Surge：官方文档（https://manual.nssurge.com/tools/url-scheme.html ）的 URL scheme 只有 start / stop / toggle、`install-config?url=`（装一整份配置）、`install-module` 和授权相关的几个，**没有导入单个代理的方式**。manual 和 kb 里也找不到剪贴板、扫码或分享链接导入代理的说明。所以 Surge 段改成两部分：先逐项列出手机版新建代理要填的内容（名称、类型、服务器、端口，再加整行里的每个参数，true 显示为「开」），再给 Mac 版和文本编辑用的整行。手册没有写 iOS 新建代理界面上的字段名，所以每项写「中文名（Surge 配置参数名）」；中文名和参数名一样（PSK、SNI、UUID、ALPN、TLS）时只写一个。逐项列表是解析整行生成的（`SURGE_FORM_JQ`，引号里的逗号不拆开，v3 迁移来的密码可能带逗号），各协议不用另写。
  - 只走 UDP 的节点（Hysteria2、TUIC、Hysteria v1，按注册表的 transport 判断）在客户端配置最后加一句：TCP 延迟测试显示不出延迟属于正常；连不上多半是本地网络限制了 UDP，可以换 TCP 类协议（VLESS Reality、AnyTLS）。部署完成页和「节点管理 → 4. 客户端配置」都会显示。
- 理由：待办原文和验收标准；规范是各家客户端解析时的公约数，主人实测 Shadowrocket 认的也是规范格式。
- 备选/被否决的方案：
  - 用 `surge:///install-config?url=` 一键安装。要在 VPS 上开 HTTP 下载服务、把 PSK 放在 URL 后面，而且装进去的是整份新配置，会替换用户现有的配置，不符合「打开菜单和查看节点时不联网」的约定。
  - Shadowrocket 专用写法，比如第三方面板 Xboard 生成的 `peer=`、`obfs=none`。没有官方依据，规范格式主人已实测可用。
  - Hysteria2 链接继续带 `alpn=h3`。规范里没有这个参数，v2rayN 和 mihomo 的 alpn 本来就默认 h3。
- 没验证：Surge iOS 界面上字段的实际叫法（没有官方文档，也没有设备）；AnyTLS 和 TUIC 链接没有在 Shadowrocket 里实测；TUIC 规范要求 `udp_relay_mode`，但 v2rayN 导入时会忽略这个参数。
- 拍板人：Claude

## 2026-10-10 Reality / ShadowTLS 伪装目标改成海外候选，部署时检测并选最快的
- 实测结论（2026-10-10，洛杉矶的一台 VPS）：同一台服务器、同一个 sing-box 1.14.3、同一部手机（中国移动网络，Shadowrocket）。伪装目标是 `www.ctrip.com` 时，手机的每个连接在服务端都报 `REALITY: processed invalid connection`，完全打不开；只把目标换成 `www.seagate.com`，立刻正常（31 个连接成功转发）。在服务器本机用 sing-box 客户端连 ctrip 版是通的，所以问题出在国内网络到海外 IP 这一段：国内网站的 SNI 发往海外 IP 会被干扰。结论：内置候选不能用国内网站。
- 决定：
  - `lib/protocols.sh` 的 `REALITY_TARGETS` 换成 14 个海外网站（www.jetbrains.com、www.mozilla.org、addons.mozilla.org、www.python.org、www.cisco.com、www.mysql.com、www.oracle.com、www.adobe.com、www.mongodb.com、www.toyota.com、www.harvard.edu、www.stanford.edu、www.tesla.com、www.sony.com）。入选条件：2026-10-10 检查时 TLS 1.3、HTTP/2、证书有效，首页不跳转，`/cdn-cgi/trace` 没有 Cloudflare 的回答，并且分布在 Akamai、CloudFront、Fastly 等不同网络上。没选首页跳到中文站、或走 `cn.edgekey` 的（如 xbox、intel、sap），也没选在国内被封或 SNI 会被阻断的（Google、Wikipedia、Dropbox）。
  - 检测（`reality_target_check`）：openssl 检查 TLS 1.3、HTTP/2（ALPN h2）和证书，限时 10 秒；再用 curl 请求 `https://<目标>/cdn-cgi/trace`（最长 8 秒），同一个请求的 `time_appconnect` 就是握手耗时（DNS、TCP、TLS 合计）。回答里有 `visit_scheme=` 就说明经 Cloudflare 代理（mack-a 的 `checkRealityDest` 也这么判断）。
  - 部署时并行检测全部候选（总等待时间约等于一次检测），自动选握手最快的。快速部署不多问问题，仍然是两个问题、回车即可，结果页前会显示「伪装目标：自动选用 X（握手 N ms）」。
  - 菜单「2. 节点管理 → 选节点 → 10. 更换伪装目标」：列出通过检测的候选（按耗时排序，回车选最快的），也可以自己填域名（同样要通过检测）。换完重新显示分享链接、二维码和各客户端配置。ShadowTLS（Snell 节点）和 Reality 用同一份列表、同一个菜单。
  - `--sni` 和 `retarget` 接受任何通过检测的域名，不再限定在列表里。
  - **Cloudflare 的处理和待办写法不完全一样**：内置候选里经 Cloudflare 的网站不会被选中（按待办要求）。但用户自己填的域名如果经 Cloudflare，不拒绝，只给提示后照用。原因：主人实际在用、并且能连通的 4 个目标里，www.seagate.com、www.sennheiser.com、www.umich.edu 这 3 个都经 Cloudflare（2026-10-10 用 Google DNS 按洛杉矶网段查：都解析到 104.18/172.64/162.159 段，`/cdn-cgi/trace` 也有回答）。seagate 已经实测能用，拒绝它会挡住已经证明可用的选择。
  - 迁移 v3 节点时，伪装目标原样保留，不检测也不替换（`tests/migrate.sh` 断言了这一点）。
- 备选/被否决的方案：
  - 列表里直接放主人那 4 个：其中 3 个经 Cloudflare，自动检测会把它们排除，放进去也选不上。
  - 像 mack-a 那样随机选一个：随机选到的不一定是离服务器近的，按握手耗时选更好。
  - 快速部署时多问一题「选哪个目标」：违反「快速部署最多两个带默认值的问题」，自动选最快的已经够用，以后想换在节点管理里一键换。
  - 自定义域名经 Cloudflare 时也拒绝：见上，会挡住已经实测可用的 seagate。
- 没验证：
  - 新候选还没在中国移动网络下实测；只能确认它们满足技术条件，而且都是海外网站。
  - 本机检测走的是本地代理，耗时数字没有参考价值；真实 VPS 上的排序只在单元测试里用模拟数据验证过。
  - 自定义的国内网站（比如 ctrip）能通过技术检测，脚本识别不出它是国内网站，只能靠内置列表不用它们。
- 拍板人：Claude

## 2026-10-10 防火墙加 iptables / ip6tables 后端（没有 UFW / firewalld 的系统）
- 决定：
  - **什么时候用 iptables**：UFW 和 firewalld 都没在运行，且 `iptables -S INPUT`（或 ip6tables）里有「兜底拦截」——INPUT 链里不带地址、端口、状态条件的 `-j REJECT` / `-j DROP`（允许只限 `-p tcp/udp/all`），或者 INPUT 默认策略是 DROP。甲骨文镜像的 `-A INPUT -j REJECT --reject-with icmp-host-prohibited` 正是这种。只封某个 IP、只丢 INVALID 包的规则不算，拦截写在自定义链里（`-A INPUT -j 某链`）的也不认（UFW 关闭后留下的空链跳转就是这种），这时不加规则（加了也没用，还会多出「没有 netfilter-persistent」提示）。IPv4、IPv6 分开判断，哪边拦截就只改哪边。
  - **插在哪**：插在第一条兜底 REJECT/DROP 的正前方（只有默认策略 DROP 时追加到末尾），所以用户在它前面写的封 IP 等规则仍然先生效。mack-a 是 `iptables -I INPUT` 插到最前面，会跳过用户自己的封禁规则，没照抄。
  - **规则写法**：`-p <tcp|udp> -m <tcp|udp> --dport <端口> -m comment --comment srm -j ACCEPT`。增删都按这条完整规则（含注释）用 `-C` / `-D` 精确匹配，别人的规则（即使同端口、即使也写了 srm 注释但端口不同）不会被删；所有权记录照旧写在 `/var/lib/srm/firewall/iptables-<ipv4|ipv6>-both-<端口>-<协议>`。
  - **保存**：这次同步或清理确实改了规则，且有 `netfilter-persistent`，就执行一次 `netfilter-persistent save`（和 mack-a 一样，它会保存当前全部规则）；保存失败只报错不回滚节点（规则已经生效）。没有 netfilter-persistent 就提示「服务器重启后会失效；安装 iptables-persistent 时选「是」保存当前规则即可」，不自动安装（Ubuntu 上装 iptables-persistent 会卸掉 ufw）。
  - **出错时**：系统缺 comment 模块（部分 OpenVZ / LXC）时加规则失败，和 UFW / firewalld 失败一样回滚这次节点修改，报错里说明可能缺 comment 模块、可改用 UFW；查询成功后才写所有权记录，所以失败的机器不会留下删不掉的记录。删除时如果该协议族已不可用（命令不存在、IPv6 被禁用，`-S INPUT` 失败），视为规则已不存在、删掉记录，免得以后每次改节点都失败；但退出码 4（xtables 锁超时、没权限）算暂时失败，保留记录、报错，下次重试再删。
- 备选/被否决的方案：
  - 只要有 iptables 命令就加规则：普通 Debian/Ubuntu 的 INPUT 是空的、全放行，加规则没用，反而每次都提示「没有 netfilter-persistent」。
  - 只在装了 netfilter-persistent 时才用 iptables（mack-a 的判断）：规则来自别的方式（开机脚本 `iptables-restore`）的机器照样连不上；按待办「没有就提示」做。
- 没验证：没在真实甲骨文镜像上跑；CI 在隔离网络命名空间里用真实 iptables / ip6tables 加模拟的 netfilter-persistent（真包会把 runner 上的 ufw 卸掉）验证了放行、删节点、卸载复原和保存内容。原生 nftables 规则（不经 iptables-nft）仍不接管，照旧提示。
- 拍板人：Claude

## 2026-10-11 完整客户端配置与临时导入链接（替代旧订阅）
- 决定（方案 `docs/specs/2026-10-11-full-client-config.md`）：
  - 新模块 `lib/profiles.sh` 生成三种完整配置：mihomo（Clash Verge / Clash Meta for Android）、sing-box 官方 App、Surge。节点写法全部来自注册表已有的 `client_outbound` / `clash` / `surge`，App 不支持的协议跳过并列出。可选全部启用的节点或单个节点；重名节点（或和「节点选择」「DIRECT」撞名）自动加「 (2)」。
  - 基本分流统一为：局域网 / 私有地址直连，国内域名和国内 IP 直连，其余走「节点选择」策略组。mihomo 用 fake-ip + 阿里 / 腾讯 DoH、`GEOSITE,cn`、`GEOIP,CN`（两个 App 自带 geo 数据）；sing-box 用 tun 入站（官方 App 必须有）、国内域名走 223.5.5.5 DoH、其余走经代理的 1.1.1.1 DoH，官方 geosite-cn / geoip-cn 规则集经「节点选择」下载并用 cache_file 缓存；Surge 用 `RULE-SET,LAN`、`DOMAIN-SUFFIX,cn`、`GEOIP,CN`、`FINAL,节点选择,dns-failed`。
  - 「临时导入链接」：python3 起一个只服务随机路径（32 位十六进制）的临时端口，下载成功一次或 10 分钟后退出；python 自己按截止时间退出，bash 被杀也不会常驻。端口用 `firewall_sync "$STATE" 端口` 临时放行（第二个参数从「只能 80 / 443」放宽为任意端口），退出、Ctrl+C、SSH 断开时撤掉；被强杀留下的规则下次同步会删掉。服务器上有正式证书且域名解析到节点地址时用 HTTPS + 域名，否则 HTTP + IP 并提示「链接里带节点密码，用完即关」。前台等待并持有 srm 锁（最长 10 分钟）。
  - 一键导入链接只放有官方出处的：sing-box `sing-box://import-remote-profile?url=…#名称`（sing-box.sagernet.org/clients/general/，libbox remote_profile.go）；Surge `surge:///install-config?url=…`（manual.nssurge.com/tools/url-scheme.html）；Clash `clash://install-config?name=…&url=…`——查不到文档页，依据官方客户端源码：Clash Verge Rev `src-tauri/src/utils/resolve/scheme.rs`（2026-10-10 提交 63ee674）把第一个 `url=` 之后整段当地址，所以 name 必须在 url 前面；Clash Meta for Android `AndroidManifest.xml`（scheme clash / clashmeta、host install-config）和 `ExternalControlActivity.kt`（参数 url、name；提交 94ebfd6）。
  - 菜单「2. 节点管理」在节点列表后加「导出完整配置」「临时导入链接」（序号接在节点后面），先选节点（回车 = 全部）再选 App（回车 = Clash），临时链接再问端口（回车随机）。主菜单第 2 项改为「节点管理 · 链接 / 二维码 / 完整配置」，部署完成页和迁移预览里的「订阅」说明同步改了。命令行 `srm profile`、`srm profile-link`。
- 理由：待办原文；新手用 Clash Verge、sing-box App、手机版 Surge 时只能整份导入。和 2026-10-10「客户端导入修正」当时否决 install-config 的理由（要开下载服务、会替换整份配置）不冲突：这次下载服务只在用户主动选择时开、下载一次就关；Surge 的 install-config 装进去的是一份新配置。
- 备选/被否决的方案：
  - 常驻订阅服务（v3 / mack-a 的做法）：一直开端口、URL 带密码，违反「打开菜单不联网」，也要常驻 nginx 或别的服务。
  - 用 nc / socat / Bash 做下载服务：做不了 TLS、精确路径、超时和「只服务一次」；python3 在 Debian / Ubuntu 云镜像基本都有，缺了就 apt 装（和 Snell 装 unzip 一样）。
  - 一次同时提供三个 App 的文件：第一个下载就会把别的关掉，所以一次只服务一个 App。
  - mihomo 用远程 rule-providers（mack-a 的做法）：要从 GitHub 拉规则，国内常常拉不下来；两个 App 都自带 geo 数据。
  - sing-box 加 mixed 入站给电脑用：官方 App 在电脑上也用 tun，不需要。
- 没验证：三个 App 实际扫码导入（没有设备）；Surge 配置只做了格式断言（没有 Linux 版 Surge）；云安全组拦住临时端口时只能靠提示；sing-box App 里 Naive 节点要 App 自带 naive 支持。
- 拍板人：Claude
- 已知影响（审查提出）：临时链接等待下载时持有 srm 锁（最长 10 分钟），这期间每日证书续期 `srm renew` 会因「另一项操作尚未结束」退出，第二天再续（证书提前 30 天续期，影响小）。

## 2026-10-11 部署结果提示与客户端细节（对比 mack-a 后的四件小事）
- 决定：
  - **Shadowrocket 走 Vision 节点没有 UDP**：Reality 节点的部署结果、「客户端配置」页和 `srm add --json` 的 note 都写「Shadowrocket 走这个节点时 UDP 不可用，需要 UDP 请用 Hysteria2 / TUIC / AnyTLS」并说明原因。同类一起改：VLESS TLS 的 tcp（同样是 Vision 流控）也加；ws / grpc / httpupgrade 没有流控，不加。没在服务端放宽（sing-box 按 UUID 认用户，一个 UUID 只能有一种 flow；去掉 flow 又会让 Vision 失效）。
  - **没有 IPv6 时只解析 IPv4**：每次生成配置时看本机有没有到公网的 IPv6 路由（`ip -6 route get 2606:4700:4700::1111`，只查路由表、不发包；审查指出只看 main 表的 default 会把 WARP / wg-quick 这类策略路由补的 IPv6 当成没有）；没有就把 `route.default_domain_resolver` 写成 `{server:"local",strategy:"ipv4_only"}`，流媒体分流的 socks 出站 `domain_resolver` 同样处理（同一个问题）；有 IPv6 或没有 ip 命令时保持 `"local"`。mack-a 用 `curl -6` 访问 Cloudflare 判断，srm 生成配置时不联网所以没照抄。配置只在每次应用时生成，之后机器新增或失去 IPv6，要等下次修改节点、重新生成配置时才跟着变。
  - **AnyTLS 的 Clash Meta 片段**加 `client-fingerprint: chrome` 和 `alpn: [h2, http/1.1]`（mihomo 文档 Meta-Docs `config/proxies/anytls.md` 的示例，mack-a 输出相同）。同类：Trojan 的 Clash Meta 片段也加 `client-fingerprint: chrome`（mack-a 同样有）；服务端没设 ALPN，客户端发什么都能连，CI 的 mihomo 真实流量测试覆盖这两个协议。
  - **Naive 链接不加 `padding=true`**：NaiveProxy 现在自动协商 padding（USAGE.txt：「The last PROXY-URI is negotiated automatically for Naive padding」，已没有 `--padding` 参数）；sing-box 的 naive 入站要求请求带 Padding 头（protocol/naive/inbound.go「missing naive padding」），能连上的客户端本来就会发；v2rayN 解析 naive 链接只读通用参数和 `insecure-concurrency`，不读 padding（ServiceLib/Handler/Fmt/NaiveFmt.cs）。DuckSoft 的链接规范里 padding 默认 false、只对老版本客户端有意义，加了没用，链接保持原样。
- 备选/被否决的方案：用 `dns.strategy` 全局设置（会影响解锁 DNS 等已有的 resolve 规则，且待办点名 default_domain_resolver）；按「有没有全局 IPv6 地址」判断（有地址没路由时照样 unreachable）。
- 没验证：Shadowrocket 里看到这句提示的实际效果；提示里推荐的 AnyTLS 的 UDP 是 UDP over TCP，Shadowrocket 里实际能否用没测；没有 IPv6 的真机上 network unreachable 是否减少（只验证了生成的配置和 `sing-box check`）。
- 拍板人：Claude

## 2026-10-11 Hysteria2 端口跳跃
- 决定：
  - **部署**：Hysteria2 的「协议自己的那一个问题」是端口跳跃（回车 / 1 = 不开，2 = 开启并用默认范围，3 = 自己填），问完再问端口，节点名用默认值。默认范围是 20000 起第一段空闲的 1000 个端口（避开所有节点端口、Snell 本机端口、别的跳跃范围和本机正在监听的 UDP 端口，并留在 Linux 临时端口 32768 以下）；自己填的范围要在 1024–65535、起 < 止，同样检查。命令行 `srm add hysteria2 --hop off|auto|起-止`。节点数据新增可选字段 `hop {start,end}`，只有带 `port_hopping` 钩子的协议（现在只有 Hysteria2）能有；state 校验保证任何节点端口都不在跳跃范围里、范围之间不重叠。没升 schema（新字段可选，旧数据不变）。
  - **服务器转发**：范围内发给本机的 UDP 在 nat PREROUTING 里 REDIRECT 到节点端口，所以防火墙只放行节点端口（UFW / firewalld / iptables 过滤时看到的已是节点端口）。只转发目的地址是本机的包（iptables `-m addrtype --dst-type LOCAL`、nftables `fib daddr type local`），不劫持经本机转发的流量（如 Docker 容器访问外网的这段端口）。有 iptables 就用 iptables / ip6tables（规则注释 `srm-hop`，和系统其余规则同一后端，不在 iptables-legacy 机器上混用 nftables nat）；没有 iptables 时用 nftables 自己的表 `inet srm_hop`（一次事务整表替换，规则注释 `srm-hop`）；两样都没有时部署 / 开启前自动装 nftables。IPv6 失败只提示，不让整个操作失败。规则跟着 `firewall_sync` 走：停用节点、关闭跳跃、删节点、卸载都撤掉；从没用过端口跳跃的机器不碰 nat 表（以 `/var/lib/srm/port-hopping` 记录为准）。
  - **重启后补回**：这些都是运行时规则。srm.service 加 `ExecStartPre=-+/opt/srm/manager.sh hop-sync`（root 运行、失败也不挡服务启动、不加锁，只读当前那一代的节点数据），每次启动（含开机）先补回。旧版装好的服务器单元里没有这行：有节点开启端口跳跃时，应用配置会重写单元并 daemon-reload。有 netfilter-persistent 的机器也顺带保存一份。
  - **客户端**：分享链接保留数字端口、用 `mport=起-止` 带范围（`hysteria2://…@host:端口/?sni=…&mport=20000-20999#名称`）。Surge `port-hopping=端口;起-止`（manual.nssurge.com/policies/hysteria2.html）、Clash Meta `ports: "端口,起-止"`（mihomo 文档，本机 mihomo -t 通过）、sing-box `server_ports: ["端口:端口","起:止"]`（1.11 起；单写 "443" 会报 bad port range，本机 sing-box 1.14.1 check 通过），完整配置导出同样带上。「说明：」里写明范围、默认 30 秒换端口、不认 mport 的客户端只连节点端口，并给出 Hysteria2 官方多端口写法的链接 `…@host:端口,起-止/?…`。部署完成页的安全组提示加「以及端口跳跃的 UDP 起-止」。
  - **节点管理**：Hysteria2 节点多一项「10.端口跳跃（运营商限制 UDP 时用）」：关闭 / 开启默认范围 / 自己填，改完显示新的客户端配置；节点列表里写「端口 N（跳跃 起–止）」。命令行 `srm node ID hop off|auto|起-止`，`srm hop-sync` 供服务启动用。
- 和待办原文不同：待办写「分享链接按官方 `端口,起-止` 写法」。没照做，因为 v2rayN 用 .NET `System.Uri` 解析链接，端口不是数字就整条导入失败（v2rayN `ServiceLib/Handler/Fmt/Hysteria2Fmt.cs`：`Utils.TryUri` 失败返回 null，范围从 `mport` 读）；Shadowrocket 对官方写法没有文档，而主流面板 Xboard 给 Shadowrocket 的订阅（`app/Protocols/Shadowrocket.php`）和 mack-a（install.sh 5266 行）都用 `mport`。用 `mport` 时不认它的客户端仍能连节点端口，用官方写法则 v2rayN 直接导入失败。官方写法放在「说明：」里给按官方规范的客户端用。
- 备选/被否决的方案：
  - mack-a 的做法：只用 iptables DNAT、不限目的地址、范围限 30000–40000、firewalld 机器逐个端口加 forward-port（1000 个端口就是 1000 条）、靠 netfilter-persistent 保存——没装它的机器重启就失效。
  - 全部用 nftables：Ubuntu 20.04 这类 iptables-legacy 机器上和 legacy nat 混用；没装 nft 的机器（Ubuntu 默认装 iptables）还要多装包。
  - 客户端只跳范围、不含节点端口：和官方写法 `端口,起-止` 不一致；节点端口本身一直可连，混进去没有坏处。
  - TUIC 也加：待办只要 Hysteria2；注册表钩子已经通用，以后要加只需在 TUIC 块里加 `port_hopping` 和客户端字段。
- 没验证：真机上运营商限速时跳跃的效果；Shadowrocket 读 `mport` 只有 Xboard / mack-a 的做法作依据，没在 iPhone 上导入过；Surge 的 `port-hopping` 只做了格式断言（没有 Linux 版 Surge）。CI 在网络命名空间里用 veth + 真实 iptables / nftables 发 UDP 包，验证范围内端口转到节点端口、回包来自所问的端口、IPv4 和 IPv6 都通、关闭 / 停用 / 卸载后不再转发；install-live 用真实 systemd 验证旧单元被补上 hop-sync、删掉规则后重启服务能补回。
- 拍板人：Claude

## 2026-10-11 iptables 规则开机补回
- 决定：
  - srm.service 的 `ExecStartPre=-+/opt/srm/manager.sh hop-sync` 换成 `firewall-restore`（root 运行、失败不挡服务启动）。它不等待 srm 主锁：主锁空闲时按当前那一代的节点数据跑一遍完整的 `firewall_sync`（UFW / firewalld / iptables 端口规则和端口跳跃转发，失效的临时端口也一并撤掉）；主锁被占时（多半就是那个操作在重启服务，比如应用配置、恢复中断、更新核心）只补端口跳跃转发，端口规则留给持锁的操作在结尾同步——这样既不会死锁，也不会撤掉临时下载链接、证书验证正在用的临时端口。端口规则同步失败（防火墙读不出来等）时照样补端口跳跃转发。它不做 `recover_pending`（那会在服务自己的启动步骤里重启这个服务），输出只留报错（每次启动都打的提示不进日志）。
  - `hop-sync` 保留为同一功能的旧名，2392455 写出的单元重启后照样补回全部规则。
  - 应用配置时总是检查单元（`service_unit_write`，内容不同才重写并 daemon-reload），不再只在有端口跳跃时检查：比 2392455 更早的单元在下一次改节点时补上这一行，顺带补上 CAP_NET_BIND_SERVICE。
  - 没装 netfilter-persistent 时的提示改成「服务器重启后由 srm 服务启动时补回」，不再建议装 iptables-persistent。
- 备选/被否决的方案：
  - 单独的 oneshot 单元：多一个单元要注册、卸载和测试，且仍要和主服务排顺序；现有 ExecStartPre 已经在每次启动时运行。
  - 不管锁直接 `firewall_sync`：持锁的临时下载链接或证书验证期间 sing-box 崩溃重启，会把临时端口撤掉；两个同步并发还可能重复插规则。
  - 只补 iptables、不碰 UFW / firewalld：那两个自己会持久化，但完整同步也只是幂等地确认一遍，少一套只补不删的逻辑。
- 已知局限：系统自己的 REJECT 如果在 srm.service 之后才恢复（比如晚于 network-online.target 的自定义脚本），启动时检测不到拦截规则，要等下次改节点或在「4. 运行状态」里重新同步；netfilter-persistent、UFW、firewalld 都在网络就绪之前加载，不受影响。开机那一刻主锁若正被证书续期定时任务（`Persistent=true`，关机期间错过时开机补跑）占着，而那次续期又不需要开临时端口，端口规则也要等下次改节点或手动同步（审查推断，概率很低）。
- 拍板人：Claude

## 2026-10-11 UFW / firewalld 停用期间保留 srm 的放行规则
- 决定：
  - 同步时，UFW / firewalld 的记录只要它们不是当前活动的防火墙（停用、开机时还没起来、检测选了 iptables 或 none）就不按「多余」删除，重新启用后节点照常放行。iptables 记录照旧（运行时规则，失效就清）。
  - UFW 停用时仍能改规则文件，所以只保留还在用的端口；停用期间删掉或改了端口的节点，它的 UFW 规则照常删掉，免得重新启用后旧端口还开着。没装 ufw 命令（卸掉了）时记录全保留，不报错。
  - firewalld 停止时 `firewall-cmd` 什么都做不了（252），记录全保留，等它再运行后的第一次同步清掉不用的；以前这种情况每次同步都失败，改节点会被回滚。
  - 停用期间新加的节点不往停用的防火墙里加规则（Ubuntu 默认装了 UFW 但不启用，往里加会改动大量用户的 UFW 配置）；同步结果里提示「UFW 当前没有运行…启用后在菜单「4. 运行状态」里选「重新同步防火墙端口规则」」，srm 服务重启时也会补。
- 备选/被否决的方案：
  - 只在 backend 为 none 时保留（待办原文）：Oracle 这类镜像 UFW 停用后检测会选 iptables，同样会删掉 UFW 记录，一并覆盖。
  - 停用时连不用的端口也全保留：重新启用到下一次同步之间，删掉的节点端口仍开着。
- 已知局限：永久从 UFW 换到 firewalld（UFW 还装着）或卸掉 ufw 后，旧记录一直留着（停用的 UFW 规则文件里也有），卸载 srm 时才清；提示只在没有别的活动防火墙时显示。「没有 ufw 命令时全保留」这一支没有单独测试（CI 机器装着 ufw，非 root 调用会报错，不好模拟）。
- 拍板人：Claude

## 2026-10-11 firewalld 停着时卸载 srm：用 firewall-offline-cmd 清永久规则
- 决定：
  - 卸载（`firewall_clear`）遇到 firewalld 记录而 `firewall-cmd --state` 返回 252（没有运行）时，不再失败：运行时记录直接丢掉（firewalld 停止时运行时规则已经没了，再启动时只从永久配置加载），永久规则用 `firewall-offline-cmd --zone=… --query-port / --remove-port` 在它的配置文件里删掉，原来就有的端口不动。Debian / Ubuntu 的 firewalld 包自带 `firewall-offline-cmd`。
  - 同一端口的永久规则没删成功时，它的运行时记录也保留（永久记录排在前面先处理），否则 firewalld 一启动又从永久配置加回这条规则，srm 却已经没有记录可删。
  - 没有 `firewall-offline-cmd`（非标准安装）时一条记录都不丢，报错写「先启动 firewalld（systemctl start firewalld）再重试」，卸载仍停在「端口规则清理失败，保留数据以便重试卸载」。
  - 连 `firewall-cmd` 都没有（firewalld 已卸掉）时直接丢掉记录，和 iptables 协议族不可用时一样。
- 备选/被否决的方案：
  - 只提示先启动 firewalld（待办给的另一种做法）：新手要敲命令，和「只在菜单里选数字」的原则不符；离线工具在标准安装里一定有。
  - 卸载时临时启动 firewalld 再清：会改变用户特意停掉的防火墙状态，启动瞬间还可能挡住别的服务。
- 已知局限：日常同步（改节点）时 firewalld 停着照旧保留记录、不离线修改（见上一条决定）。firewalld 若是卡死而不是停止（推断：firewall-cmd 连不上它时可能同样返回 252），离线修改要等它重载才生效，运行时规则留到那时。firewalld 配了 `CleanupOnExit=no` 时停止后内核里还留着它的规则，srm 的端口要等重启或 firewalld 再启动才关上（推断，没实测）。
- 拍板人：Claude

## 2026-10-11 公开仓库真实 IP 检查：保留段 + 公共地址白名单
- 决定：
  - `tests/no-real-ip.sh` 用 `git grep` 扫已跟踪文件（工作区内容），取出恰好 4 段、每段不超过 255 的数字串；保留段（0/8、10/8、100.64/10、127/8、169.254/16、172.16/12、192.0.0/24、192.168/16、198.18/15、224/4 起的组播和保留段）、三个文档段和脚本里 `KNOWN` 列出的公共地址放过，其余报出文件、行号和地址，退出码 1。
  - `KNOWN` 是精确地址清单：公共 DNS、v3 `install.sh` 里的 Cloudflare WARP 端点、`128.0.0.0/1` 路由、v3 输入示例和一个测试占位地址。v3 `install.sh` 在切换发布前不能改，只能放进清单。
  - 脚本先自检一次：运行时拼出的公网地址必须被报出、保留和清单地址必须放过，防止扫描在某个平台上悄悄失效（macOS 的 BSD awk 和 CI 的 mawk 行为不同）。
  - PROGRESS.md 那条 Lisa 实测记录去掉 IP、v3 节点端口、所跑服务，以及对照节点的端口（和旧提交里的 IP 合起来就是一个开着的代理端口）。
- 备选/被否决的方案：
  - 按文件或按行写例外注释：例外散在各处不好审，而且 v3 `install.sh` 不能加注释。
  - 同时扫 IPv6：仓库里的 IPv6 都是文档段、ULA 或公共 NAT64 DNS，待办只要求 IPv4；IPv6 写法多、误报面大，先不做。
  - 扫 UUID / 域名：仓库里都是示例值和公共服务域名，没有通用规则能分出「真实」的，靠人工复核（本次全仓核过一遍）。
- 已知局限：没 `git add` 的新文件扫不到；写成 5 段以上数字串里的地址、被字母数字紧贴的地址（如 `v1.2.3.4` 会当成地址，`1.2.3.4.5` 不会）按规则处理。
- 拍板人：Claude

## 2026-10-11 生产机 IP 进了公开仓库：不改写历史
- 决定：不用 filter-repo 改写历史、不强推；当前文件里的 IP 已去掉（3597fee），CI 扫已跟踪文件里的真实 IPv4。
- 理由：IP 从 2026-10-10 22:35 起已公开约 8 小时，改写收不回已被抓取或 fork 的副本，GitHub 上旧提交按哈希也可能仍能打开；改写还会让所有提交号和 PR 记录对不上。
- 备选/被否决的方案：B 改写历史并强推（收益小、代价大）。
- 可选加固（会影响主人手上的客户端，由主人决定要不要做）：v3 节点换端口后重新扫码；确认 Lisa 的 SSH 只允许密钥登录。
- 拍板人：Claude（按推荐，主人 2026-10-10 要求选项一律按推荐直接定）

## 2026-10-11 srm 的定位：「绝不把你的服务器搞坏」，不追功能广度
- 决定：
  - 差异化定为三条底线，新功能过不了就不合并：改了不会坏、坏了能回去；不越界；装完就能连上，连不上知道为什么。
  - 明确不做：Web 面板和多用户计费、常驻订阅、Xray 双核、Argo / WARP / CDN 优选、Docker 形态、自动更新、默认装预发布核心、Serv00 / 无 root 环境、遥测和广告。
  - 和已合并设计冲突的一处是「新装取最新稳定版」，写成待办「核心大版本上限」，不在方案里直接改。
- 理由：
  - 12 个直接同类和 7 类相邻形态读了代码和 issues（`docs/research/2026-10-11-同类脚本调研.md`）。被骂得最多、最可信的是升级后坏了要卸载重装（mack-a、yg、fscarmen 合计 100 条以上），其次是动了用户的防火墙和系统（yg #283、fscarmen #290 #353、mack-a #1289）。
  - 没有一个同类在每次改配置时都做到校验加回滚。功能广度、社区规模上 srm 比不过 mack-a、yg、fscarmen，硬追只会变成缝合怪。
- 备选/被否决的方案：
  - 追功能全（一次装十几个协议 + Argo + 订阅，fscarmen、yg 的路线）：维护面爆炸，正是 v3 要摆脱的。
  - 做成 sing-box 面板（s-ui 的路线）：一台 VPS 自用的人背上常驻端口、凭据和数据库，s-ui 自己的内存和锁 issue 就是代价。
  - 零提问部署（233boy、eooce）：srm 现在是两次回车，差别不大，不为这一步删掉端口和节点名的选择。
- 拍板人：Claude（主人派活要求「做出别人没有的、把别人做得不好的做好」，取舍按推荐直接定）

## 2026-10-11 公开仓库扫描扩到 IPv6、UUID、私钥、short_id、域名、邮箱、本机路径
- 决定：`tests/no-real-ip.sh` 改名 `tests/no-private-info.sh`，一个 awk 程序逐行扫已跟踪文件，八类各有「放行的占位写法」和 `KNOWN_*` 公共清单（理由写在清单旁）：
  - IPv6：只看全球单播（第一组 2000–3fff），放过文档段 2001:db8::/32、3fff::/20；清单里是 Cloudflare DNS、v3 `install.sh` 里 nat64.net 的公共 NAT64 DNS 和 AliDNS 示例前缀。
  - UUID：除版本位、变体位和最后 4 位外全 0 的算占位（`00000000-0000-4000-8000-000000000001`），另放过全 0、全 f。测试样本里 18 个手编 UUID 按原顺序换成这种写法，fake core 生成的 UUID 前缀也换了。
  - Reality 私钥：只看紧跟在 private_key / privateKey / PrivateKey 后面的 43 位 base64url；前 39 位同一个字符的算占位（`AAAA…AAAE`）。迁移样本的 6 个私钥换成占位，公钥用 `reality_public_key` 重新推导，样本里 v3 存的公钥文件同步改，样本仍自洽。
  - short_id：只看 short_id / shortId / short-id / `?sid=` 后面的值；去掉最后一位后全 0 或是 `0123456789abcdef` 前缀的算占位。`6ba85179e30d4fc2` 进清单：mack-a/v2ray-agent 写死的 shortId，每台 v3 都一样。
  - 域名：只认常见顶级域（排除 .sh、.md、.py 这类同名扩展名），放过 example.com/.org/.net 和保留名（.example、.test、.invalid、.localhost）；其余要在 `KNOWN_DOMAINS` 里（按可注册域名列，含子域），分组写理由：代码托管与下载、协议和客户端文档、srm / v3 会查询的服务、分流规则里的流媒体域名、Reality / ShadowTLS 伪装目标候选（含 v3 的两份候选列表）。测试里用作输入的几个真实短域名（单字母 .com、一个中文 .cn 域名）换成 example.com 下的名字；`notexample.com` 进清单（测后缀匹配不能把它当成 example.com）。
  - 邮箱：只放过占位域名，不用公共清单。
  - 路径：`/Users/<名字>`、`/home/<名字>` 只放过 user、you、runner、ubuntu 这类通用名。
- 理由：主人要求公开仓库里这些地方一律是占位或文字描述。逐类找到能区分「占位」和「真值」的规则，测试样本改成占位；公共服务和伪装目标没有规则能和真实域名分开，只能列清单。
- 备选/被否决的方案：
  - 连公钥也扫：公钥本来就写在分享链接里，占位私钥推导出的公钥也是随机样子，扫它会逼着样本前后不自洽。
  - 把 v3 的 `install.sh`、`documents/` 整个文件排除：省掉一长串清单，但切换发布前文件里新增的东西就扫不到了；按域名列清单更准。
  - 用 Python 写扫描：CI 和本机都有，但项目只用 Bash + jq，awk 足够，和原脚本一致。
- 已知局限：私钥和 short_id 只认同一行里紧跟字段名的值（JSON 换行写法扫不到）；顶级域不在 `TLDS` 清单里的冷门后缀不报；非 ASCII 域名只看它的 ASCII 部分。
- 拍板人：Claude
