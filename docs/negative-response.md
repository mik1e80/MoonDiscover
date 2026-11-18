# NSEC 查询端与否定响应契约

2026-11-18，0.3.0-dev，未发布。NSEC 是最终查询端目标内的必要行为，不能再作为未来可选项排除。规范依据：[RFC 6762 §6.1](https://www.rfc-editor.org/rfc/rfc6762.html#section-6.1)、[RFC 4034 §4.1](https://www.rfc-editor.org/rfc/rfc4034.html#section-4.1)。不是 DNSSEC 验证，不信任未认证的链路发布者身份。

## 处理链

Type 47 解码为 `RData.Nsec(next_name, bitmap)`；window=0、长度 1–32、单窗口、NSEC 自身位不置位。next name 不同仍接纳位图。不能解析的 NSEC 保留 Unknown，Engine 输出 `nsec_ignored`，同包合法 RR 继续接纳；RR 外层截断仍是整包错误。DTO 接口对无效 NSEC 位图也忽略，不使其他正常 RR 失败。

独立 negatives 数组每个 scope/name/IN 保存一个有界位图，在查询时按 rrtype 判断，不展开 256 个对象。容量与正缓存各为 cache_capacity（默认各 2048、各最多 16384），独立上限；同一事务的任一容量失败都不提交正负缓存或时间变化。否定类型当前限 1..255，排除共享 DNS-SD PTR 和 NSEC 本身，不表示 NXDOMAIN。相同名称的新有效 NSEC 替换旧位图；TTL=0 撤销该名称否定证据。否定证据不会删除正向 RR；已有或同包有效正向 RR 优先，并在该 NSEC 生命周期内记住冲突，避免正记录过期后旧否定复活。正向 cache-flush 的一秒宽限保持不变。

Engine 在收包和到期时重建问题集合，取消有效否定类型的待发查询和续包；其他类型、KA 和 PTR 仍继续。否定到期通过 cache.next_deadline 唤醒，引擎恢复正常查询抖动。关闭或重建网络代次清空全部负缓存。纯 Engine 的 scope 由调用方提供；Native 负证据通过普通 ingress 策略和收包限额，不能绕过来源检查。

`Engine.is_negative(scope,name,type)` / `Browser.is_negative(name,type)` 仅表示有效 IN 证据；false 同时可能是 Positive 或 Unknown，结合正向快照/记录判断。快照 complete 不降低 TXT 要求：有 A、否定 AAAA 可完整；AAAA-only 可完整但默认 IPv4 endpoints 为空；两种地址都否定、SRV/TXT 缺失仍部分状态。NSEC 本身不是服务，不能生成假服务或宣布设备离线。

## 八类验收案例

| 场景 | 可执行证据与预期 |
| --- | --- |
| A 有、AAAA 无 | engine/negative_response_test：完整快照，AAAA 查询被抑制，A 保留 |
| Additional NSEC | 同测试：附加区位图与服务记录同时接纳 |
| 负 TTL 到期 | 同测试：2 秒虚拟 TTL 后重新发送 AAAA，不等待物理时间 |
| 正向推翻否定 | cache/negative_cache_test、engine/negative_response_test：AAAA 接纳、冲突否定撤销 |
| 共享记录 | 同测试：PTR 仍查询，不能否定整个服务类型 |
| 畸形 NSEC | wire/nsec_test：异常单条 Unknown，同包 A 正常；外层损坏仍拒绝 |
| 多名称/类型/范围与容量 | cache/negative_cache_test：隔离、原子容量失败；后续专项扩展见测试源码 |
| cache-flush 与救回 | 正向优先、宽限内仍保留正记录；见 cache 专项与既有 flush 回归 |

独立来源：现有 `fixtures/zeroconf-0.148.0-response.hex` 是独立 zeroconf 的实际抓包，SHA 和来源不变，现已检查 NSEC 位图。该报文的 owner 是服务实例，位图包含 AAAA；不能将它谎称为 host 的 IPv4-only 实验。`tests/protocol_live/nsec.mbt` 另向独立 Avahi 发布的唯一 IPv4 名称查询 AAAA，要求实际 UDP NSEC，报告在 `.tools/protocol-live-nsec.json`；脚本失败不能标为通过。

轻量命令：`moon test src/wire src/cache src/engine src/replay --target js --filter 'smoke:*'`。Linux 使用现有 `moon run scripts/protocol-live.mbtx -- avahi`。Windows 同类独立发布者 NSEC 专项、第二物理设备、物理时间到期后发布者变更、长时间压力尚无新证据。部分验收未满足时不声称八类完整实网互操作或完整查询端 RFC 合规，也不发布稳定 0.3.0。
