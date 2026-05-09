# Reality 目标域名推荐

更新日期: `2026-05-09`

这次结果只以一台**中国大陆阿里云服务器**的复测为准。

## 筛选标准

基础条件:

* 不使用跳转到其他域名的目标站
* 支持 `TLS 1.3`
* 支持 `X25519`
* 支持 `HTTP/2`
* 证书 `SNI` 与目标域名匹配

进一步收口:

* 在国内机上补测 `connect` / `appconnect`
* 优先保留握手更快的一批
* 尽量移除明显过热的大厂站、跳转站和高延迟站
* `IP 相近` 这项这次用国内机的低连接时延作为实用代理指标

说明:

* 这页现在只保留上面这套标准下通过且进一步收口后的域名
* 当前脚本默认随机池已经和这份页面同步
* 这是一份 `2026-05-09` 的中国大陆网络快照，后续如果网络环境变化，结果也可能变化

## 默认随机池内置域名

这组就是当前已经写进脚本默认随机池的域名:

```text
www.japan.travel
www.aniplex.co.jp
www.caltech.edu
www.princeton.edu
www.columbia.edu
www.ucla.edu
www.umich.edu
www.ox.ac.uk
www.nyu.edu
www.asus.com
www.ibm.com
www.ericsson.com
www.tp-link.com
www.synology.com
www.logitech.com
www.seagate.com
www.vmware.com
www.sennheiser.com
www.sothebysrealty.com
www.century21.com
```

## 最推荐

如果你想先从更稳的一批里挑，我建议优先这 10 个:

* `www.caltech.edu`
* `www.princeton.edu`
* `www.japan.travel`
* `www.aniplex.co.jp`
* `www.ericsson.com`
* `www.seagate.com`
* `www.vmware.com`
* `www.sennheiser.com`
* `www.sothebysrealty.com`
* `www.synology.com`

## 分类池

### 旅游 / 动漫

* `www.japan.travel`
* `www.aniplex.co.jp`

### 高校 / 学术

* `www.caltech.edu`
* `www.princeton.edu`
* `www.columbia.edu`
* `www.ucla.edu`
* `www.umich.edu`
* `www.ox.ac.uk`
* `www.nyu.edu`

### 技术 / 企业

* `www.asus.com`
* `www.ibm.com`
* `www.ericsson.com`
* `www.vmware.com`

### 网络 / 设备 / 存储

* `www.tp-link.com`
* `www.synology.com`
* `www.logitech.com`
* `www.seagate.com`
* `www.sennheiser.com`

### 房地产

* `www.sothebysrealty.com`
* `www.century21.com`

## 这次被移出默认池的典型域名

基础条件没过:

* `download-installer.cdn.mozilla.net`
  `HTTP/2` 复测未通过
* `www.gundam.info`
  会跳到 `gundam-official.com`
* `www.zillow.com`
  `X25519` 复测未通过

进一步收口后移出:

* `gateway.icloud.com`
* `www.booking.com`
* `www.kayak.com`
* `store.epicgames.com`
* `www.cloudflare.com`
* `www.atlassian.com`
* `www.postman.com`
* `s0.awsstatic.com`
* `d1.awsstatic.com`
* `m.media-amazon.com`
* `www.netgear.com`
* `www.qnap.com`

这些并不一定代表它们完全不能用，而是这次为了让默认池更保守，优先让位给:

* 通过基础条件
* 国内机握手更快
* 相对不那么热门
* 更适合长期放进随机池

## 使用建议

* 当前默认随机池已经不是“尽量大”，而是“尽量稳”
* 想继续扩池，也必须继续按同一台国内机复测
* 如果后续要进一步做 `RealiTLScanner` 的 IP 邻近筛选，建议把它作为下一轮补强，而不是和当前白名单混用
