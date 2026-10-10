# 完整客户端配置与临时导入链接（替代旧订阅）

属于待办「v4 完整客户端配置与一键导入」。一个分支做完，不再拆。

## 要解决的问题
Clash Verge、sing-box 官方 App（SFI / SFA / SFM）、手机版 Surge 都不能只导入一段节点片段，新手需要一份能直接导入的完整配置。v3 靠 nginx 长期订阅给出；v4 删掉了订阅（方案 2026-10-10），所以要换一种不常驻的方式。

## 做法
- 新模块 `lib/profiles.sh`（不出现协议类型名，节点写法全部来自注册表的 `client_outbound` / `clash` / `surge`）：
  - `profile_render 客户端 STATE [节点ID]`：客户端是 `clash`（mihomo）、`sing-box`、`surge`；不写节点 = 全部启用的节点。客户端不支持的节点跳过并在 stderr 列出；一个都不支持就失败。
  - 节点名重复或和策略组名撞车时自动加「 (2)」。
  - 基本分流（三家一致）：局域网 / 私有地址直连，国内域名和国内 IP 直连，其余走「节点选择」。
    - mihomo：fake-ip DNS（阿里 / 腾讯 DoH），`GEOSITE,cn`、`GEOIP,CN`（Clash Verge、Clash Meta for Android 自带 geo 数据）。
    - sing-box：tun 入站（官方 App 必需），DNS 国内域名走 223.5.5.5 DoH、其余走 1.1.1.1 DoH 经代理；官方 `geosite-cn` / `geoip-cn` 规则集（SagerNet 仓库，经「节点选择」下载，cache_file 缓存）。
    - Surge：`dns-server`、`RULE-SET,LAN`、`GEOIP,CN`、`FINAL,节点选择,dns-failed`。
  - `profile_link 客户端 [节点ID] [端口] [秒数]`：临时下载服务。
    - 文件放在随机路径 `/<32 位十六进制>/srm.<扩展名>`，其它路径 404。
    - 下载成功一次或到时间（默认 600 秒）就退出；python3 自己也按截止时间退出，bash 进程被杀也不会常驻。
    - 防火墙：`firewall_sync "$STATE" 端口` 临时放行，退出（含 Ctrl+C、断开 SSH）时 `firewall_sync "$STATE"` 撤掉；进程被强杀留下的规则，下一次任何同步都会删掉（不在期望集合里）。
    - 有通过解析检查的域名证书（Let's Encrypt / 导入的证书，且域名解析到节点地址）就用 HTTPS + 域名；否则 HTTP + 节点地址，并提示「链接里带节点密码，用完即关」。
    - 前台等待，期间持有 srm 锁（最长 10 分钟），按 Ctrl+C 提前关闭。
- 一键导入链接（`profile_import_link`），只放有官方出处的：
  - sing-box：`sing-box://import-remote-profile?url=<编码的地址>#<编码的名称>`（sing-box.sagernet.org/clients/general/，libbox `remote_profile.go`）。
  - Clash：`clash://install-config?name=<名称>&url=<编码的地址>`。没有文档页，依据是官方客户端源码：Clash Verge Rev `src-tauri/src/utils/resolve/scheme.rs`（把 `url=` 之后整段都当地址，所以 name 必须放在 url 前面）、Clash Meta for Android `AndroidManifest.xml` + `ExternalControlActivity.kt`（scheme clash / clashmeta，host install-config，参数 url、name）。
  - Surge：`surge:///install-config?url=<编码的地址>`（manual.nssurge.com/tools/url-scheme.html）。
- 菜单：「2. 节点管理」的节点列表后面加「导出完整配置」「临时导入链接」两项（序号接在节点后面），各自先选节点（回车 = 全部），再选 App（回车 = Clash）。临时链接再问一次端口（回车随机）。
- 命令行（进阶）：`srm profile 客户端 [节点ID]`、`srm profile-link 客户端 [节点ID] [--port 端口] [--minutes 分钟]`。

## 取舍
- 不做长期订阅：常驻 HTTP 服务要一直开端口、URL 带密码，和「打开菜单不联网」「不常驻多余服务」冲突。
- 下载服务用 python3（Debian / Ubuntu 云镜像基本自带，缺了就 apt 装）而不是 nc / socat：要 TLS、精确路径、超时和「只服务一次」，Bash 做不了监听。
- 一次只服务一个 App 的文件：第一次下载就关，多个文件会互相关掉。
- Surge 完整配置：manual 有 install-config，所以也生成（只含 Surge 支持的节点），不能在 CI 里校验，只做格式断言。

## 验收
- `tests/profiles.sh`：三种配置的内容、跳过不支持的节点、重名处理、导入链接格式（注明出处）；临时链接下载一次后关闭、超时关闭、错误路径 404，都断言防火墙规则先加后撤。
- CI（TEST_CORE / TEST_MIHOMO）：`sing-box check`、`mihomo -t` 校验全协议生成的完整配置。
- `tests/firewall-live.sh`：真实 iptables 下临时端口放行、下载后规则消失。
