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
  - `srm install` 在终端里运行完会直接打开菜单（没有节点就是快速部署）；非终端（自动化、CI）不进菜单。
  - 已有启用的节点时，添加节点前显示一句「应用新配置会重启服务，已有节点的连接会断开几秒」，不再二次确认（方案「更新」一节）。
- 理由：方案「交互原则」「部署流程」；主人要新手只用选、不用填。
- 备选/被否决的方案：每个协议都问端口和节点名、Snell 版本另问（Snell 会有 3 个问题，超过方案的上限）；用第三方 GeoIP 接口查地区（多一个请求，Cloudflare trace 一次就带国家代码）；域名解析不对直接拒绝（开了 CDN 代理的用户也能用 http-01 申请证书，所以菜单留「仍然申请」，命令行留 webroot/import）；Shadowrocket 按协议全部列出（没有官方清单，不确定的宁可不列）。
- 没验证：Shadowrocket、v2rayN 的实际导入（没有 iOS/Windows 环境，只按源码和链接格式）；真实 Cloudflare trace 和 `getent` 只在代码里调用，测试里用替身；真实 Let's Encrypt 申请仍没有在测试里跑。
- 拍板人：Claude
