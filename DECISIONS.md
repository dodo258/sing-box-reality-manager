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
