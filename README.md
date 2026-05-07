# sing-box-reality-manager

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

这是一个 AGPL-3.0 魔改版分支仓库。它以稳定的 `dodo258-v2ray-agent` 单实例脚本为基线，单独演进 `sing-box` 优先的多实例 Reality 节点管理能力，避免影响原仓库里已经稳定的单实例安装流程。

当前这版已经可以作为长期使用的稳定版：

* 主节点部署、账号管理、节点管理可正常使用
* 多实例 Reality 节点可独立部署、查看、删用户、删节点
* `sing-box` 下主节点和多实例节点都支持节点级 DNS 分流
* `9.网站管理` 可部署中文静态站，网站与节点功能解耦
* 服务由 `systemd` 托管，机器重启后会自动拉起

## 魔改说明

*   当前维护: [dodo258](https://github.com/dodo258)
*   基线来源: `dodo258-v2ray-agent` 当前稳定版本副本
*   改造方向: 多实例 Reality 节点管理、按节点 DNS 分流、自更新地址切换、新仓库文档与菜单文案
*   保持不变: 原有单实例主流程继续保留，方便回退和对照
*   合规说明: 原项目出处与许可证说明见 [NOTICE.md](NOTICE.md)

## 功能

*   支持 Xray-core 和 sing-box
*   支持 VLESS、VMess、Trojan、Hysteria2、Tuic、NaiveProxy 等协议
*   自动申请与续订 TLS 证书
*   提供菜单式安装、管理、订阅与分流配置
*   保留域名黑名单、BT 下载限制等能力
*   新增 `7.多实例Reality`，可在当前核心下部署多个独立端口的 Reality 节点
*   `12.分流工具 -> 5.DNS分流` 支持 `sing-box` 主节点和多实例节点的节点级 DNS 分流
*   `9.网站管理` 支持中文技术博客、中文小工具站、自定义静态站和旧模板兼容入口

## 当前建议

*   多实例优先推荐 `sing-box`
*   `Xray-core` 保留兼容旧功能时使用
*   多实例 Reality 需要先安装一个主节点，再继续部署其他独立节点
*   流媒体专用节点优先用 `sing-box + 节点级 DNS 分流`
*   网站功能按需使用即可，默认走正常 `80/443 + HTTPS`

## 多实例说明

*   这里的“多实例”是独立节点，不是 `13.添加新端口` 那种端口映射入口
*   当前版本先覆盖最常用的 `VLESS+Reality+Vision` 多实例管理
*   按当前已安装核心工作：你装的是 Xray，就管理 Xray 多实例；你装的是 sing-box，就管理 sing-box 多实例
*   不引入双核心同时托管逻辑，优先保证稳定性
*   `7.多实例Reality` 只负责独立节点，不和旧的 `8.账号/订阅管理` 混用

## DNS 分流说明

*   `12.分流工具 -> 5.DNS分流` 现在分成“全局”和“Reality 节点”两类入口
*   `sing-box` 支持先选节点，再只给该节点绑定 DNS 分流
*   可直接录入 `netflix,disney,hulu,openai` 这类关键词，脚本会自动转成对应规则集
*   `Xray-core` 目前仍然只有核心级全局 DNS 分流，不支持在同一进程里按多个 Reality 节点分别指定不同上游 DNS

## 网站管理说明

*   `9.网站管理` 面向正常静态站部署，和节点功能解耦
*   网站默认使用真实域名、正常 `80/443` 和可信 HTTPS 证书
*   网站证书沿用 `10.证书管理` 同一套 `acme.sh` 免费证书与自动续期链路
*   网站场景默认走 `Let's Encrypt` 免费证书，不再要求选择 DNS API 提供商

## 已知边界

*   `Xray-core` 不支持像 `sing-box` 那样按不同 Reality 节点分别指定不同上游 DNS
*   Reality 目标域名、流媒体规则集、上游解锁 DNS 都依赖外部环境，后续若外部策略变化，仍可能需要调整域名池或 DNS
*   `13.添加新端口` 是给已有节点补入口，不是新建独立节点

## 安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/dodo258/sing-box-reality-manager/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

## 使用

安装完成后执行:

```bash
vasma
```

常用入口:

```text
3.一键无域名Reality
7.多实例Reality
8.账号/订阅管理
9.网站管理
12.分流工具
13.添加新端口
15.节点管理
```

## 附加文档

*   [Reality 目标域名推荐](documents/reality_target_domains.md)
*   [多实例 Reality 使用说明](documents/multi_instance_reality.md)
*   [备份与恢复说明](documents/backup_and_restore.md)

## 反馈

*   仓库: [github.com/dodo258/sing-box-reality-manager](https://github.com/dodo258/sing-box-reality-manager)
*   问题反馈: [提交 issue](https://github.com/dodo258/sing-box-reality-manager/issues)

## 许可证

本项目按 [AGPL-3.0](LICENSE) 授权，并保留上游项目的许可证要求与出处说明。
