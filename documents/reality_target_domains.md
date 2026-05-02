# Reality 目标域名推荐

更新日期: `2026-05-02`

筛选标准:

*   测试网络: 一台中国大陆云服务器
*   PQ 测试: `xray tls ping domain:443`
*   直连测试: `curl -I https://domain/`
*   通过条件: `连续 3 轮都能协商出 X25519MLKEM768`，并且 `连续 3 轮 curl 直连都不返回 000`

说明:

*   这页现在只保留上面这套标准下通过的域名
*   不通过的域名，不再出现在推荐页，也不再进入脚本默认随机池
*   这是一份 `2026-05-02` 的中国大陆网络快照，后续如果网络环境变化，结果也可能变化

## 默认随机池内置域名

这组就是当前已经写进脚本默认随机池的域名:

```text
gateway.icloud.com
download-installer.cdn.mozilla.net
addons.mozilla.org
www.mozilla.org
www.booking.com
www.kayak.com
www.japan.travel
store.epicgames.com
www.aniplex.co.jp
www.gundam.info
www.berkeley.edu
www.caltech.edu
www.princeton.edu
www.columbia.edu
www.ucla.edu
www.umich.edu
www.ox.ac.uk
www.cam.ac.uk
www.nyu.edu
redis.io
www.mongodb.com
www.asus.com
www.ibm.com
www.cloudflare.com
www.atlassian.com
www.jetbrains.com
www.postman.com
s0.awsstatic.com
d1.awsstatic.com
m.media-amazon.com
www.century21.com
www.sothebysrealty.com
www.zillow.com
www.realtor.com
www.ericsson.com
www.netgear.com
www.tp-link.com
www.synology.com
www.qnap.com
www.logitech.com
www.seagate.com
www.vmware.com
www.sennheiser.com
```

## 最推荐

如果你想先用一批更稳的，我建议优先从这 12 个里挑:

*   `gateway.icloud.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `www.mozilla.org`
*   `www.booking.com`
*   `www.kayak.com`
*   `www.japan.travel`
*   `www.aniplex.co.jp`
*   `www.gundam.info`
*   `www.cloudflare.com`
*   `www.atlassian.com`
*   `www.jetbrains.com`

## 分类池

### Apple / 浏览器 / CDN

*   `gateway.icloud.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `www.mozilla.org`
*   `s0.awsstatic.com`
*   `d1.awsstatic.com`
*   `m.media-amazon.com`

### 旅游 / 目的地

*   `www.booking.com`
*   `www.kayak.com`
*   `www.japan.travel`

### 游戏 / 动漫

*   `store.epicgames.com`
*   `www.aniplex.co.jp`
*   `www.gundam.info`

### 学术 / 高校

*   `www.berkeley.edu`
*   `www.caltech.edu`
*   `www.princeton.edu`
*   `www.columbia.edu`
*   `www.ucla.edu`
*   `www.umich.edu`
*   `www.ox.ac.uk`
*   `www.cam.ac.uk`
*   `www.nyu.edu`

### 技术 / 企业 / 工具

*   `redis.io`
*   `www.mongodb.com`
*   `www.ibm.com`
*   `www.cloudflare.com`
*   `www.atlassian.com`
*   `www.jetbrains.com`
*   `www.postman.com`
*   `www.vmware.com`

### 网络 / 设备 / 存储

*   `www.asus.com`
*   `www.ericsson.com`
*   `www.netgear.com`
*   `www.tp-link.com`
*   `www.synology.com`
*   `www.qnap.com`
*   `www.logitech.com`
*   `www.seagate.com`
*   `www.sennheiser.com`

### 房地产

*   `www.century21.com`
*   `www.sothebysrealty.com`
*   `www.zillow.com`
*   `www.realtor.com`

## 使用建议

*   这页只保留国内服务器 3 轮全通过的域名
*   想继续扩池，也必须继续按这套标准复测
*   当前脚本默认随机池已经和这份页面同步
