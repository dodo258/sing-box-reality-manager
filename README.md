# sbox-deploy-tool

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

这是一个 AGPL-3.0 魔改版分支仓库。它以稳定的 `dodo258-v2ray-agent` 单实例脚本为基线，单独演进“多实例 Reality 节点管理”能力，避免影响原仓库里已经稳定的单实例安装流程。

## 魔改说明

*   当前维护: [dodo258](https://github.com/dodo258)
*   基线来源: `dodo258-v2ray-agent` 当前稳定版本副本
*   改造方向: 多实例 Reality 节点管理、自更新地址切换、新仓库文档与菜单文案
*   保持不变: 原有单实例 `3/7/12/14` 主流程继续保留，方便回退和对照
*   合规说明: 原项目出处与许可证说明见 [NOTICE.md](NOTICE.md)

## 功能

*   支持 Xray-core 和 sing-box
*   支持 VLESS、VMess、Trojan、Hysteria2、Tuic、NaiveProxy 等协议
*   自动申请与续订 TLS 证书
*   提供菜单式安装、管理、订阅与分流配置
*   保留域名黑名单、BT 下载限制等能力
*   新增 `19.多实例Reality`，可在当前核心下部署多个独立端口的 Reality 节点

## 多实例说明

*   这里的“多实例”是独立节点，不是 `12.添加新端口` 那种端口映射入口
*   当前版本先覆盖最常用的 `VLESS+Reality+Vision` 多实例管理
*   按当前已安装核心工作：你装的是 Xray，就管理 Xray 多实例；你装的是 sing-box，就管理 sing-box 多实例
*   不引入双核心同时托管逻辑，优先保证稳定性

## 安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/dodo258/sbox-deploy-tool/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

## 使用

安装完成后执行:

```bash
vasma
```

## 附加文档

*   [Reality 目标域名推荐](documents/reality_target_domains.md)
*   [多实例 Reality 使用说明](documents/multi_instance_reality.md)

## 反馈

*   仓库: [github.com/dodo258/sbox-deploy-tool](https://github.com/dodo258/sbox-deploy-tool)
*   问题反馈: [提交 issue](https://github.com/dodo258/sbox-deploy-tool/issues)

## 许可证

本项目按 [AGPL-3.0](LICENSE) 授权，并保留上游项目的许可证要求与出处说明。
