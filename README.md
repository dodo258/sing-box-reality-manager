# sing-box-reality-manager

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

语言: [简体中文](README.md) | [English](README_EN.md)

这是一个 AGPL-3.0 魔改版分支仓库。它以 `sing-box` 优先，围绕 Reality、AnyTLS、Snell+ShadowTLS 多实例节点管理、节点级 DNS 分流和轻量网站管理做了整理。

## 推荐用法

新手或日常稳定使用，优先走：

```text
3.一键无域名Reality
```

需要多个独立节点时，再用：

```text
6.多实例Reality
7.多实例AnyTLS
8.多实例Snell+ShadowTLS
```

常用管理入口：

```text
9.账号/订阅管理      查看主节点账号
10.节点管理          查看和管理节点
11.分流工具          配置 DNS / 流媒体分流
12.网站管理          部署普通静态网站
15.更新脚本          更新到最新版
18.卸载脚本
```

## 怎么选

* 稳定优先：选 `Reality`，默认随机端口，不需要自备域名。
* 需要自备域名证书：选 `AnyTLS`。
* 想用 Snell：选 `Snell+ShadowTLS`，默认随机公网端口，443 只在空闲时使用。
* 流媒体分流：优先使用 `sing-box + 11.分流工具 -> DNS分流`。
* 普通网站：用 `12.网站管理`，网站走正常 `80/443 + HTTPS`，节点继续走随机端口。

## 当前能力

* 支持 `sing-box` 优先部署，也保留 `Xray-core` 兼容入口。
* 支持 VLESS Reality、AnyTLS、Snell v4/v5 + Shadow-TLS v3。
* 支持 Reality / AnyTLS / Snell+ShadowTLS 多实例独立节点。
* `sing-box` 下支持主节点和多实例节点的节点级 DNS 分流。
* 网站管理支持中文技术博客、中文小工具站、自定义静态站和旧模板兼容入口。
* 服务由 `systemd` 托管，机器重启后会自动拉起。

## 关键边界

* 多实例是“独立节点”，不是给旧节点补入口。
* `Xray-core` 目前只保留兼容能力，按节点 DNS 分流优先使用 `sing-box`。
* AnyTLS 需要域名，证书走免费 `acme.sh` 自动续期链路。
* Snell+ShadowTLS 中 Shadow-TLS 对外监听，Snell 只监听本机后端端口。
* Reality / Shadow-TLS 目标域名依赖外部网络环境，必要时需要重新筛选。

## 安装

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/dodo258/sing-box-reality-manager/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

安装完成后执行：

```bash
vasma
```

## 文档

* [Reality 目标域名推荐](documents/reality_target_domains.md)
* [Shadow-TLS 目标域名池](documents/shadowtls_target_domains.md)
* [多实例 Reality 使用说明](documents/multi_instance_reality.md)
* [备份与恢复说明](documents/backup_and_restore.md)

## 魔改说明

* 当前维护: [dodo258](https://github.com/dodo258)
* 基线来源: `dodo258-v2ray-agent` 稳定版本副本
* 合规说明: 原项目出处与许可证说明见 [NOTICE.md](NOTICE.md)

## 许可证

本项目按 [AGPL-3.0](LICENSE) 授权，并保留上游项目的许可证要求与出处说明。
