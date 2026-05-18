# sing-box-reality-manager

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

Language: [简体中文](README.md) | [English](README_EN.md)

This is an AGPL-3.0 modified branch focused on `sing-box`-first deployment, multi-instance Reality / AnyTLS / Snell+ShadowTLS management, node-level DNS routing, and lightweight website management.

## Recommended Flow

For normal stable usage, start with:

```text
3. One-click Domainless Reality
```

For multiple independent nodes, use:

```text
6. Multi-instance Reality
7. Multi-instance AnyTLS
8. Multi-instance Snell+ShadowTLS
```

Common management entries:

```text
9. Account / Subscription Management   View main-node accounts
10. Node Management                    View and manage nodes
11. Routing Tools                      Configure DNS / streaming routing
12. Website Management                 Deploy a normal static website
15. Update Script                      Update to the latest version
18. Uninstall Script
```

## What To Choose

* Stability first: use `Reality`. It uses a random port by default and does not require your own domain.
* Need a domain certificate: use `AnyTLS`.
* Need Snell: use `Snell+ShadowTLS`. It uses a random public port by default; use 443 only when it is free.
* Streaming routing: prefer `sing-box + 11. Routing Tools -> DNS Routing`.
* Normal website: use `12. Website Management`. Websites use normal `80/443 + HTTPS`; nodes continue to use random ports.

## Current Capabilities

* `sing-box`-first deployment with retained `Xray-core` compatibility.
* VLESS Reality, AnyTLS, Snell v4/v5 + Shadow-TLS v3.
* Independent multi-instance nodes for Reality, AnyTLS, and Snell+ShadowTLS.
* Node-level DNS routing for the main `sing-box` node and multi-instance `sing-box` nodes.
* Website management for Chinese tech blogs, Chinese tool sites, custom static uploads, and archived legacy templates.
* `systemd` managed services with automatic startup after reboot.

## Key Boundaries

* Multi-instance means independent nodes, not extra entry ports for old nodes.
* `Xray-core` is kept for compatibility; prefer `sing-box` for per-node DNS routing.
* AnyTLS requires a domain and uses the free `acme.sh` auto-renewal certificate chain.
* In Snell+ShadowTLS mode, Shadow-TLS listens publicly while Snell listens only on a local backend port.
* Reality and Shadow-TLS target domains depend on the external network environment and may need future re-testing.

## Installation

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/dodo258/sing-box-reality-manager/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

After installation:

```bash
vasma
```

## Documentation

* [Reality Target Domain Recommendations](documents/reality_target_domains.md)
* [Shadow-TLS Target Domain Recommendations](documents/shadowtls_target_domains.md)
* [Multi-instance Reality Guide](documents/multi_instance_reality.md)
* [Backup and Restore Guide](documents/backup_and_restore.md)

## Modified Branch Notes

* Maintainer: [dodo258](https://github.com/dodo258)
* Baseline: stable `dodo258-v2ray-agent` copy
* Attribution: upstream source and license notes are retained in [NOTICE.md](NOTICE.md)

## License

This project is licensed under [AGPL-3.0](LICENSE) and retains upstream attribution and license requirements.
