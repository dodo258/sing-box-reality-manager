# Shadow-TLS v3 目标域名池

这个列表用于 `Snell + Shadow-TLS v3` 部署时的默认随机目标域名池。

筛选方向：

* 国内网络可直连访问
* 支持 TLS 1.3
* 域名与 SNI 匹配
* 优先正常大厂站点、旅游、教育、硬件、企业官网
* 尽量避免过热、明显 CDN 中转或跳转链很长的网站

当前脚本部署时仍会做一次 TLS1.3 探测；如果现场网络超时，建议手动换一个目标域名。

## 推荐池

```text
www.apple.com:443
www.microsoft.com:443
www.bing.com:443
www.nvidia.com:443
www.intel.com:443
www.oracle.com:443
www.cisco.com:443
www.samsung.com:443
www.asus.com:443
www.dell.com:443
www.hp.com:443
www.ibm.com:443
www.adobe.com:443
www.cloudflare.com:443
www.cloudflarestatus.com:443
www.mozilla.org:443
addons.mozilla.org:443
www.python.org:443
www.java.com:443
www.mysql.com:443
www.mongodb.com:443
redis.io:443
www.booking.com:443
www.trip.com:443
www.marriott.com:443
www.hyatt.com:443
www.hilton.com:443
www.ritzcarlton.com:443
www.nintendo.com:443
www.playstation.com:443
www.xbox.com:443
www.unrealengine.com:443
www.autodesk.com:443
www.vmware.com:443
www.salesforce.com:443
www.sap.com:443
www.umich.edu:443
www.caltech.edu:443
www.stanford.edu:443
```

## 使用建议

* 默认随机即可；如果部署时 TLS1.3 探测失败，换一个域名。
* 不建议和网站管理共抢 `443`。脚本默认随机公网端口，手动填 `443` 时会先检查端口是否空闲。
* Snell 的节点级 DNS 是“整个 Snell 节点使用该 DNS”，不是 sing-box 那种按 geosite 规则分流。
