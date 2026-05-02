# Reality 目标域名推荐

更新日期: `2026-05-02`

这份清单面向 `Xray-core + VLESS + Reality + Vision` 场景整理，重点考虑以下方向:

*   国内常见网络环境下更像正常网站流量
*   域名本身长期稳定，偏大厂或长期运营站点
*   行业尽量分散，不全压在 Apple/Google/AWS 一类热门站点
*   本次整理优先保留在 `2026-05-02` 实测中支持 `X25519MLKEM768` 的站点

注意:

*   这是一份 `2026-05-02` 的快照，不是永久真相
*   不同地区、运营商、出入口网络环境下结果会变化
*   `301/302/403/404` 不一定不能用，Reality 更看重 TLS/ALPN 和整体指纹是否正常
*   真正上机前，建议你仍然抽样复测
*   默认随机池现在已经优先剔除了这次实测里明显不带 `X25519MLKEM768` 的域名

## 默认随机池优先组

这组适合直接作为脚本内置随机池优先候选。它们在这次实测中：

*   支持 `X25519MLKEM768`
*   大多数证书链长度相对更短
*   更少触发额外的附加验证分支

```text
gateway.icloud.com
download-installer.cdn.mozilla.net
addons.mozilla.org
dl.google.com
www.booking.com
www.visitcalifornia.com
www.kayak.com
www.nintendo.com
store.epicgames.com
www.aniplex.co.jp
www.gundam.info
www.crunchyroll.com
arxiv.org
www.nature.com
www.berkeley.edu
www.python.org
react.dev
redis.io
```

## 最推荐

这 12 个更适合直接作为你的常用默认池:

*   `gateway.icloud.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `dl.google.com`
*   `www.booking.com`
*   `www.kayak.com`
*   `www.nintendo.com`
*   `store.epicgames.com`
*   `www.aniplex.co.jp`
*   `arxiv.org`
*   `react.dev`
*   `redis.io`

## 第一梯队

适合拿来做主要域名池，按行业分散混用。这里分成两组：

*   `默认优先组`：支持 `X25519MLKEM768`，而且更适合直接进入脚本随机池
*   `扩展备选组`：同样支持 `X25519MLKEM768`，但证书链通常更长，更适合人工挑着用

### Apple / 浏览器 / CDN

默认优先组:

*   `gateway.icloud.com`
*   `download-installer.cdn.mozilla.net`
*   `addons.mozilla.org`
*   `dl.google.com`

扩展备选组:

*   `s0.awsstatic.com`
*   `d1.awsstatic.com`
*   `m.media-amazon.com`

### 旅游

默认优先组:

*   `www.booking.com`
*   `www.visitcalifornia.com`
*   `www.kayak.com`

扩展备选组:

*   `www.japan.travel`
*   `www.tripadvisor.com`

### 游戏

默认优先组:

*   `www.nintendo.com`
*   `store.epicgames.com`

### 二次元

默认优先组:

*   `www.aniplex.co.jp`
*   `www.gundam.info`
*   `www.crunchyroll.com`

### 房地产

扩展备选组:

*   `www.century21.com`
*   `www.sothebysrealty.com`
*   `www.zillow.com`
*   `www.redfin.com`

### 学术 / 研究

默认优先组:

*   `arxiv.org`
*   `www.nature.com`
*   `www.berkeley.edu`

扩展备选组:

*   `www.caltech.edu`

### 技术 / 企业

默认优先组:

*   `www.python.org`
*   `react.dev`
*   `redis.io`

扩展备选组:

*   `www.mongodb.com`
*   `www.asus.com`

## 默认混合池

如果你只想复制一份“够稳、够分散、够像正常站点”的池子，直接用下面这组:

```text
gateway.icloud.com
download-installer.cdn.mozilla.net
addons.mozilla.org
dl.google.com
www.booking.com
www.visitcalifornia.com
www.kayak.com
www.nintendo.com
store.epicgames.com
www.aniplex.co.jp
www.gundam.info
www.crunchyroll.com
arxiv.org
www.nature.com
www.berkeley.edu
www.python.org
react.dev
redis.io
```

## 这次实测里不建议继续放进默认随机池

这些域名在 `2026-05-02` 这台服务器的实测里没有协商出 `X25519MLKEM768`，所以我已经先从脚本默认随机池里移走了:

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

## 使用建议

*   不要全用一个厂商的域名，尤其别全是 Apple/Google/AWS
*   每台机器尽量从不同类别里混着挑 3 到 8 个
*   热门域名和相对小众域名混搭更稳
*   默认随机池适合“先装再说”，你自己长期用的机器仍然建议手动挑 1 到 3 个常用目标域名做复测
*   如果某一批在你的线路上连续握手异常，就整类替换，不要只盯一个域名死磕
