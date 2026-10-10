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
  - 自签证书只给客户端能固定证书的 TUIC、Hysteria v1、Hysteria2（方案的协议表也要求 Hysteria2 无域名时自签 + pin，同一套代码一起做了）。服务器地址是 IP 时默认选自签，SNI 默认 `www.bing.com`（可用 `--sni` 改）。每个节点一份，放 `/var/lib/srm/selfsigned/<节点ID>/`（root:srm 640），有效期十年，不参与续期，证书页单独提示。state 里记 `cert_sha256`（证书 DER 的 SHA-256 十六进制，Surge `server-cert-fingerprint-sha256`、mihomo `fingerprint`、Hysteria2 链接 `pinSHA256` 用）和 `pubkey_sha256`（公钥 SPKI 的 SHA-256 base64，sing-box `certificate_public_key_sha256` 用，实测不需要 insecure 就能连自签证书，指纹不对就连不上）。
  - 自签节点的分享链接：Hysteria2 写 `insecure=1&pinSHA256=…`（官方客户端的 pinSHA256 只在常规校验通过后才检查，自签必须同时 insecure，见 v2.hysteria.network 客户端文档）；TUIC、Hysteria v1 的链接格式没有指纹参数，只能写 `allow_insecure=1` / `insecure=1`。客户端配置页会提示「只导入链接的客户端会跳过证书校验」，并给出指纹让能填的客户端填上；sing-box、Clash Meta、Surge 片段都带指纹，不跳过校验。
  - 证书提问顺序改为先选证书方式、再问域名；服务器地址是 IP 时域名不再默认填 IP（以前会拿 IP 去申请证书）。
  - Shadowsocks 只提供 `2022-blake3-aes-128-gcm`（Surge 和 mihomo 都支持，密钥 16 字节），不让用户选加密方式。链接按 SIP002：2022 方法的 userinfo 不做 base64，方法和密码百分号编码。
  - VLESS TLS：tcp 用 Vision 流控；ws / httpupgrade 的 ALPN 只给 http/1.1（ws 不能走 h2），grpc 给 h2；路径和 gRPC 服务名随机生成。VMess 只用 alterId 0（AEAD），链接用 v2rayN 的 base64 JSON 格式。
  - Naive 只开 TCP（HTTP/2），不开 QUIC；链接主机用证书域名（Naive 客户端按域名连接和校验证书）。Clash Meta 和 Surge 没有 Naive 客户端。
  - Hysteria v1 服务端上下行上限 1000 Mbps；客户端片段和链接写上行 30、下行 100 Mbps（v1 客户端必须填带宽），用户可在客户端里调高。
  - 客户端配置片段：注册表新增可选钩子 `clash`（mihomo 代理，一行 JSON 流式写法，可直接放进 YAML 的 proxies 列表）和 `surge`（Surge 代理行）；Surge 不支持 VLESS、Naive、Hysteria v1（manual.nssurge.com/policies/overview 的协议表）。节点管理「4. 客户端配置」一屏列出 sing-box / Clash Meta / Surge，Shadowrocket、v2rayN 用原始链接或二维码。命令行 `srm export ID clash|surge|clients`。
  - CI 下载固定哈希的 mihomo v1.19.32，用它把每个 Clash Meta 片段实际跑一遍流量。
- 理由：方案「协议」表；验收要求每个协议的配置过 `sing-box check`、真实流量走通、链接格式有单元测试。参数名和格式都对照了官方文档或客户端源码（Surge 手册、mihomo 文档、SIP002、Hysteria v1/v2 URI 文档、v2rayN/NekoBox 源码），出处写在代码注释里。
- 备选/被否决的方案：自签证书节点的链接不写 insecure（TUIC、Hysteria v1 的链接客户端会直接连不上）；自签证书和域名证书放同一目录（同名 SNI 会和 Let's Encrypt 证书冲突，续期逻辑也会误判）；Shadowsocks 让用户选 128/256（多一个问题，安全性差别对代理场景不大）；Naive 同时开 QUIC（要多管一个 UDP 端口，Naive 客户端默认也走 HTTP/2）。
- 没验证：Surge 配置行只做了格式单元测试（Surge 没有 Linux 版，CI 跑不了）；只测了 TCP 流量，各协议的 UDP 转发没有单独测；curl 不能当 Naive 客户端（sing-box 的 naive 入站要求 naive padding，实测报 `missing naive padding`），所以 Naive 只用 sing-box 自带的 naive 客户端验证，核心编译时不带它的话测试会打印跳过原因。
- 拍板人：Claude
