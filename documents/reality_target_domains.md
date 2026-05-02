# Reality 目标域名推荐

更新日期: `2026-05-01`

这份清单面向 `Xray-core + VLESS + Reality + Vision` 场景整理，重点考虑以下方向:

*   国内常见网络环境下更像正常网站流量
*   域名本身长期稳定，偏大厂或长期运营站点
*   行业尽量分散，不全压在 Apple/Google/AWS 一类热门站点
*   本次整理优先保留在线检查中 `443/TLS` 正常且大多可协商 `HTTP/2` 的站点

注意:

*   这是一份 `2026-05-01` 的快照，不是永久真相
*   不同地区、运营商、出入口网络环境下结果会变化
*   `301/302/403/404` 不一定不能用，Reality 更看重 TLS/ALPN 和整体指纹是否正常
*   真正上机前，建议你仍然抽样复测

## 最推荐

这 12 个更适合直接作为你的常用默认池:

*   `gateway.icloud.com`
*   `itunes.apple.com`
*   `download-installer.cdn.mozilla.net`
*   `s0.awsstatic.com`
*   `images-na.ssl-images-amazon.com`
*   `dl.google.com`
*   `www.booking.com`
*   `www.nintendo.com`
*   `www.aniplex.co.jp`
*   `www.century21.com`
*   `arxiv.org`
*   `www.stanford.edu`

## 第一梯队

适合拿来做主要域名池，按行业分散混用:

### Apple / 浏览器 / CDN

*   `gateway.icloud.com`
*   `itunes.apple.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `s0.awsstatic.com`
*   `d1.awsstatic.com`
*   `images-na.ssl-images-amazon.com`
*   `m.media-amazon.com`
*   `dl.google.com`

### 旅游

*   `www.booking.com`
*   `www.visitcalifornia.com`

### 游戏

*   `www.nintendo.com`
*   `www.playstation.com`

### 二次元

*   `www.aniplex.co.jp`
*   `www.gundam.info`

### 房地产

*   `www.century21.com`
*   `www.sothebysrealty.com`

### 学术 / 研究

*   `arxiv.org`
*   `www.nature.com`
*   `www.stanford.edu`
*   `www.berkeley.edu`
*   `www.caltech.edu`

### 技术 / 企业

*   `www.python.org`
*   `react.dev`
*   `www.oracle.com`
*   `www.mongodb.com`
*   `redis.io`
*   `www.cisco.com`
*   `www.asus.com`

## 默认混合池

如果你只想复制一份“够稳、够分散、够像正常站点”的池子，直接用下面这组:

```text
gateway.icloud.com
itunes.apple.com
download-installer.cdn.mozilla.net
addons.mozilla.org
s0.awsstatic.com
d1.awsstatic.com
images-na.ssl-images-amazon.com
m.media-amazon.com
dl.google.com
www.booking.com
www.visitcalifornia.com
www.nintendo.com
www.playstation.com
www.aniplex.co.jp
www.gundam.info
www.century21.com
www.sothebysrealty.com
arxiv.org
www.nature.com
www.stanford.edu
www.berkeley.edu
www.caltech.edu
www.python.org
react.dev
www.oracle.com
www.mongodb.com
redis.io
www.cisco.com
www.asus.com
```

## 使用建议

*   不要全用一个厂商的域名，尤其别全是 Apple/Google/AWS
*   每台机器尽量从不同类别里混着挑 3 到 8 个
*   热门域名和相对小众域名混搭更稳
*   如果某一批在你的线路上连续握手异常，就整类替换，不要只盯一个域名死磕
