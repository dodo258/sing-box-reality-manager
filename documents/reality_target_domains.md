# Reality 目标域名推荐

更新日期: `2026-05-02`

复测环境:

*   服务器: `103.103.245.68`
*   工具: `/etc/v2ray-agent/xray/xray tls ping domain:443`
*   口径: 这一轮优先保留在该服务器上实测能协商出 `X25519MLKEM768` 的域名

整理目标:

*   扩充脚本默认随机池，不再只靠十几个老域名
*   优先保留大厂、长期运营站点、常见下载站、旅游站、学术站、技术站
*   行业尽量打散，不全压在 Apple/Google/AWS 一类高频热门域名上

注意:

*   这是 `2026-05-02` 这台服务器的快照，不是永久真相
*   中国大陆不同地区和运营商下，直连表现仍然会有差异
*   `301/302/403/404` 不等于不能用，Reality 更看重 TLS/ALPN 和整体握手指纹
*   真正长期上机前，建议你仍然对自己常用的 3 到 8 个域名做抽样复测

## 默认随机池内置域名

这一组就是这次已经塞进脚本默认随机池的域名:

```text
gateway.icloud.com
swdist.apple.com
swcdn.apple.com
updates.cdn-apple.com
download-installer.cdn.mozilla.net
addons.mozilla.org
www.mozilla.org
dl.google.com
www.booking.com
www.visitcalifornia.com
www.kayak.com
www.japan.travel
www.tripadvisor.com
www.lonelyplanet.com
www.viator.com
www.nintendo.com
store.epicgames.com
www.ubisoft.com
www.aniplex.co.jp
www.gundam.info
www.crunchyroll.com
arxiv.org
www.nature.com
www.berkeley.edu
www.caltech.edu
www.princeton.edu
www.columbia.edu
www.ucla.edu
www.umich.edu
www.ox.ac.uk
www.cam.ac.uk
www.nyu.edu
www.python.org
react.dev
redis.io
www.mongodb.com
www.asus.com
www.ibm.com
www.cloudflare.com
www.atlassian.com
www.figma.com
www.notion.so
vercel.com
www.jetbrains.com
www.docker.com
www.postman.com
gitlab.com
s0.awsstatic.com
d1.awsstatic.com
m.media-amazon.com
www.century21.com
www.sothebysrealty.com
www.zillow.com
www.redfin.com
www.realtor.com
www.ericsson.com
www.netgear.com
www.tp-link.com
www.synology.com
www.qnap.com
www.digitalocean.com
www.linode.com
www.logitech.com
www.razer.com
www.seagate.com
www.vmware.com
www.sennheiser.com
```

## 最推荐

如果你就想先抓一把更稳妥的，我建议优先从这 18 个里选:

*   `gateway.icloud.com`
*   `swdist.apple.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `dl.google.com`
*   `www.booking.com`
*   `www.kayak.com`
*   `www.nintendo.com`
*   `store.epicgames.com`
*   `www.aniplex.co.jp`
*   `arxiv.org`
*   `www.nature.com`
*   `react.dev`
*   `www.python.org`
*   `www.cloudflare.com`
*   `www.atlassian.com`
*   `www.jetbrains.com`
*   `gitlab.com`

## 分类扩展池

### Apple / 浏览器 / CDN

*   `gateway.icloud.com`
*   `swdist.apple.com`
*   `swcdn.apple.com`
*   `updates.cdn-apple.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `www.mozilla.org`
*   `dl.google.com`
*   `s0.awsstatic.com`
*   `d1.awsstatic.com`
*   `m.media-amazon.com`

### 旅游 / 目的地

*   `www.booking.com`
*   `www.visitcalifornia.com`
*   `www.kayak.com`
*   `www.japan.travel`
*   `www.tripadvisor.com`
*   `www.lonelyplanet.com`
*   `www.viator.com`

### 游戏 / 动漫 / 娱乐

*   `www.nintendo.com`
*   `store.epicgames.com`
*   `www.ubisoft.com`
*   `www.aniplex.co.jp`
*   `www.gundam.info`
*   `www.crunchyroll.com`

### 学术 / 研究 / 高校

*   `arxiv.org`
*   `www.nature.com`
*   `www.berkeley.edu`
*   `www.caltech.edu`
*   `www.princeton.edu`
*   `www.columbia.edu`
*   `www.ucla.edu`
*   `www.umich.edu`
*   `www.ox.ac.uk`
*   `www.cam.ac.uk`
*   `www.nyu.edu`

### 技术 / 云 / 开发工具

*   `www.python.org`
*   `react.dev`
*   `redis.io`
*   `www.mongodb.com`
*   `www.ibm.com`
*   `www.cloudflare.com`
*   `www.atlassian.com`
*   `www.figma.com`
*   `www.notion.so`
*   `vercel.com`
*   `www.jetbrains.com`
*   `www.docker.com`
*   `www.postman.com`
*   `gitlab.com`
*   `www.digitalocean.com`
*   `www.linode.com`
*   `www.vmware.com`

### 网络 / 设备 / 存储

*   `www.asus.com`
*   `www.ericsson.com`
*   `www.netgear.com`
*   `www.tp-link.com`
*   `www.synology.com`
*   `www.qnap.com`
*   `www.logitech.com`
*   `www.razer.com`
*   `www.seagate.com`
*   `www.sennheiser.com`

### 房地产

*   `www.century21.com`
*   `www.sothebysrealty.com`
*   `www.zillow.com`
*   `www.redfin.com`
*   `www.realtor.com`

## 暂不建议继续塞进默认随机池

这些域名在 `2026-05-02` 这台服务器的实测里没有协商出 `X25519MLKEM768`，或者直接超时，我先不往默认随机池里放:

*   `itunes.apple.com`
*   `images-na.ssl-images-amazon.com`
*   `www.playstation.com`
*   `www.stanford.edu`
*   `www.oracle.com`
*   `www.cisco.com`
*   `www.marriott.com`
*   `www.hilton.com`
*   `academy.nvidia.com`
*   `www.airbnb.com`
*   `www.expedia.com`
*   `www.agoda.com`
*   `www.hotels.com`
*   `www.ea.com`
*   `www.blizzard.com`
*   `www.rockstargames.com`
*   `www.toei-anim.co.jp`
*   `www.cmu.edu`
*   `www.cornell.edu`
*   `www.ucsd.edu`
*   `www.sap.com`
*   `www.adobe.com`
*   `www.salesforce.com`
*   `www.tesla.com`
*   `www.toyota-global.com`
*   `support.apple.com`
*   `music.apple.com`
*   `www.samsung.com`
*   `www.amd.com`
*   `www.sony.com`
*   `www.nokia.com`
*   `www.mit.edu`
*   `www.yale.edu`
*   `www.imperial.ac.uk`
*   `www.uchicago.edu`
*   `www.toronto.edu`
*   `www.ihg.com`
*   `www.hyatt.com`
*   `www.heroku.com`
*   `github.com`
*   `www.nvidia.com`
*   `developer.nvidia.com`
*   `www.acer.com`
*   `www.msi.com`
*   `www.westerndigital.com`
*   `www.arm.com`
*   `www.paloaltonetworks.com`
*   `www.fortinet.com`
*   `www.redhat.com`
*   `www.bose.com`
*   `www.sonos.com`
*   `www.oneplus.com`
*   `www.mi.com`
*   `www.oppo.com`
*   `www.vivo.com`
*   `www.lenovo.com`
*   `www.hp.com`
*   `www.dell.com`
*   `www.intel.com`

## 使用建议

*   不要全压一个厂商，尤其别全是 Apple / Google / AWS
*   大厂热门域名和相对冷一点的行业域名混着用更稳
*   默认随机池现在已经够大，适合快速安装；长期使用的机器仍然建议手动挑常用目标域名
*   如果某一类域名在你的线路上连续异常，就整类替换，不要只盯一个域名死磕
