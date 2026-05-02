# dodo258-v2ray-agent

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

This repository is an AGPL-3.0 modified fork. It keeps the Xray-core/sing-box installation and management workflow, while removing upstream promotional, donation, and community redirect content and switching update sources to this repository.

## Fork Notes

*   Maintainer: [dodo258](https://github.com/dodo258)
*   Changes: README cleanup, issue template cleanup, menu branding updates, self-update source updates, helper script source updates
*   Compliance: original license and upstream attribution are retained; see [NOTICE.md](../../NOTICE.md)

## Features

*   Supports Xray-core and sing-box
*   Supports VLESS, VMess, Trojan, Hysteria2, Tuic, NaiveProxy, and more
*   Handles TLS certificate issuance and renewal
*   Keeps the original menu-driven install and management workflow
*   Preserves subscription, routing, blacklist, and P2P blocking capabilities

## Installation

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/dodo258/dodo258-v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

## Usage

```bash
vasma
```

## Extra Docs

*   [Reality target domain recommendations](../reality_target_domains.md)

## Support

*   Repository: [github.com/dodo258/dodo258-v2ray-agent](https://github.com/dodo258/dodo258-v2ray-agent)
*   Issues: [Submit an issue](https://github.com/dodo258/dodo258-v2ray-agent/issues)

## License

This fork remains licensed under [AGPL-3.0](../../LICENSE).
