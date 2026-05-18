# sing-box-reality-manager

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

Language: [简体中文](README.md) | [English](README_EN.md)

This repository is the multi-instance branch of the user's maintained deployment script. It keeps the stable single-instance baseline separate while focusing on `sing-box`-first multi-instance Reality node management, AnyTLS, Snell + Shadow-TLS, node-level DNS routing, and lightweight website deployment.

## Highlights

* Stable main-node deployment, account management, and node management
* Independent multi-instance Reality deployment, viewing, user deletion, and node deletion
* AnyTLS one-click and multi-instance deployment with per-node domains
* Snell v4/v5 + Shadow-TLS v3 one-click and multi-instance deployment
* Node-level DNS routing for both the main `sing-box` node and multi-instance `sing-box` nodes
* `12. Website Management` for normal static websites, separated from node functions
* `systemd` managed services with automatic startup after reboot

## Notes

* Maintainer: [dodo258](https://github.com/dodo258)
* Baseline: stable single-instance script branch maintained separately by the same owner
* Focus: multi-instance Reality management, AnyTLS, Snell + Shadow-TLS, per-node DNS routing, website management, and repo-specific documentation/menu flow
* Compliance: original project attribution and license notice are retained in [NOTICE.md](NOTICE.md)

## Features

* Supports Xray-core and sing-box
* Supports VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy, and more
* Handles TLS certificate issuance and renewal
* Provides menu-driven install, routing, subscription, and management flows
* Adds `6. Multi-instance Reality` for deploying multiple independent-port Reality nodes on the current core
* Adds `7. Multi-instance AnyTLS` for independent-domain AnyTLS nodes
* Adds `8. Multi-instance Snell+ShadowTLS` for independent-port Snell v4/v5 nodes wrapped by Shadow-TLS v3
* `11. Routing Tools -> 5. DNS Routing` supports node-level DNS routing for `sing-box`
* `12. Website Management` supports Chinese tech-blog sites, Chinese tool sites, custom static uploads, and archived legacy templates

## Current Recommendations

* Prefer `sing-box` for multi-instance usage
* Use `Xray-core` only when you specifically need older compatibility paths
* Install one main node first, then add more nodes through `6. Multi-instance Reality`, `7. Multi-instance AnyTLS`, or `8. Multi-instance Snell+ShadowTLS`
* For streaming-specific nodes, prefer `sing-box + node-level DNS routing`
* For Snell, use the default random public port unless you are sure `443` is free
* Use website management only when needed; it follows normal `80/443 + HTTPS` behavior

## Multi-instance Notes

* “Multi-instance” here means independent nodes, not the old port-forward style of adding an extra entry port
* This branch focuses on `VLESS + Reality + Vision`, AnyTLS, and Snell + Shadow-TLS multi-instance workflows
* It works on the currently installed core only: Xray manages Xray instances, sing-box manages sing-box instances
* Dual-core concurrent hosting is intentionally avoided to keep the script stable

## Snell + Shadow-TLS Notes

* `5. One-click Snell+ShadowTLS` and `8. Multi-instance Snell+ShadowTLS` use the same independent-node logic
* Shadow-TLS v3 listens on the public port, while Snell only listens on a random local `127.0.0.1` backend port
* Snell v5 is the default; Snell v4 is available for compatibility
* The Shadow-TLS target domain is selected from `documents/shadowtls_target_domains.md` by default and is probed for TLS 1.3
* Snell DNS is whole-node upstream DNS, not `sing-box` geosite-style per-domain routing

## DNS Routing Notes

* `11. Routing Tools -> 5. DNS Routing` is split into global routing and Reality-node routing
* `sing-box` can select a specific node and attach DNS routing only to that node
* You can enter rule keywords such as `netflix,disney,hulu,openai`, and the script converts them to the proper rule-set form
* `Xray-core` still only supports core-level global DNS routing, not per-Reality-node upstream DNS selection
* Snell + Shadow-TLS DNS is whole-node upstream DNS, so it is managed inside the Snell + Shadow-TLS menu

## Website Management Notes

* `12. Website Management` is for normal static websites and is decoupled from node functions
* Website deployment uses real domains, normal `80/443`, and trusted HTTPS certificates
* Website certificates reuse the same `acme.sh` free-certificate and auto-renew chain from `13. Certificate Management`
* Website mode defaults to standard `Let's Encrypt` issuance and does not require choosing a DNS API provider
* The main recommended site types are Chinese tech-blog sites and Chinese tool sites; legacy disguise templates are kept only as compatibility entries

## Known Boundaries

* `Xray-core` does not support per-node upstream DNS selection the way `sing-box` does
* Reality target domains, streaming rule sets, and unlock DNS providers still depend on external environments and may need adjustment later
* The old extra-port flow only adds entry ports for an existing node; it does not create a new independent node

## Installation

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/dodo258/sing-box-reality-manager/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

## Usage

After installation:

```bash
vasma
```

Common entries:

```text
3. One-click Domainless Reality
4. One-click AnyTLS
5. One-click Snell+ShadowTLS
6. Multi-instance Reality
7. Multi-instance AnyTLS
8. Multi-instance Snell+ShadowTLS
9. Account / Subscription Management
11. Routing Tools
12. Website Management
10. Node Management
```

## Extra Docs

* [Reality Target Domain Recommendations](documents/reality_target_domains.md)
* [Shadow-TLS Target Domain Recommendations](documents/shadowtls_target_domains.md)
* [Multi-instance Reality Guide](documents/multi_instance_reality.md)
* [Backup and Restore Guide](documents/backup_and_restore.md)

## Support

* Repository: [github.com/dodo258/sing-box-reality-manager](https://github.com/dodo258/sing-box-reality-manager)
* Issues: [Submit an issue](https://github.com/dodo258/sing-box-reality-manager/issues)

## License

This project is licensed under [AGPL-3.0](LICENSE) and retains upstream attribution and license requirements.
