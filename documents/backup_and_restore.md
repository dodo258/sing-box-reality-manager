# 备份与恢复说明

这份脚本当前主要依赖 `systemd + /etc/v2ray-agent`。

## 建议备份的内容

优先备份这些目录和文件：

```bash
/etc/v2ray-agent/
/etc/systemd/system/dodo258-sing-box.service
/etc/systemd/system/dodo258-xray.service
```

如果机器上还有你以前手动维护的旧节点，也建议单独备份对应配置目录。

## 最简单备份方式

```bash
mkdir -p /root/sing-box-reality-manager-backup
cp -a /etc/v2ray-agent /root/sing-box-reality-manager-backup/
cp -a /etc/systemd/system/dodo258-sing-box.service /root/sing-box-reality-manager-backup/ 2>/dev/null || true
cp -a /etc/systemd/system/dodo258-xray.service /root/sing-box-reality-manager-backup/ 2>/dev/null || true
```

如果你想打包成单文件：

```bash
tar -czf /root/sing-box-reality-manager-backup-$(date +%F-%H%M%S).tar.gz \
  /etc/v2ray-agent \
  /etc/systemd/system/dodo258-sing-box.service \
  /etc/systemd/system/dodo258-xray.service
```

## 恢复思路

恢复时优先做这几步：

1. 还原 `/etc/v2ray-agent/`
2. 还原 `dodo258-sing-box.service` 或 `dodo258-xray.service`
3. 执行 `systemctl daemon-reload`
4. 执行 `systemctl restart dodo258-sing-box` 或 `systemctl restart dodo258-xray`
5. 用 `systemctl status` 确认服务正常

示例：

```bash
cp -a /root/sing-box-reality-manager-backup/v2ray-agent /etc/
cp -a /root/sing-box-reality-manager-backup/dodo258-sing-box.service /etc/systemd/system/ 2>/dev/null || true
cp -a /root/sing-box-reality-manager-backup/dodo258-xray.service /etc/systemd/system/ 2>/dev/null || true
systemctl daemon-reload
systemctl restart dodo258-sing-box 2>/dev/null || true
systemctl restart dodo258-xray 2>/dev/null || true
```

## 升级前建议

每次大改前建议至少备份一次：

* `/etc/v2ray-agent/sing-box/conf/config/`
* `/etc/v2ray-agent/xray/conf/`
* 当前正在使用的订阅链接或客户端配置

这样即使升级后不满意，也能快速回滚。
