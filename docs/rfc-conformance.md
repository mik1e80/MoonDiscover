# RFC 条款与实现对照

状态：2026-11-05，main / 0.2.1-dev。这是有限浏览/解析实现的可追踪对照，不是完整 RFC 符合性或独立安全审计。测试结果与提交依据见[本轮验证记录](security-review-20261105.md)。

状态统一使用 Supported（对应子项已实现且有证据）、Partial（有限行为/有简化）、Unsupported（未实现）、Untested（缺少所列环境的验证）。状态仅修饰该行的范围，不代表整份 RFC。

| 条款与范围 | 状态、实现与测试 | 限制或选择理由 |
| --- | --- | --- |
| [RFC 1035 §4.1.1–4.1.3](https://www.rfc-editor.org/rfc/rfc1035.html#section-4.1.1)：header、question、RR 区域及长度 | Partial；wire/decode.mbt、cache/cache.mbt；wire_test、invalid_record_test、security_fuzz | 解码保留 Answer/Authority/Additional；成功响应的受支持 IN 数据可来自这些区域。只缓存 ID=0、QR=1、opcode=0、TC=0、rcode=0；AA 不作为身份/接纳条件。不是通用 DNS resolver |
| [RFC 1035 §4.1.4](https://www.rfc-editor.org/rfc/rfc1035.html#section-4.1.4)：压缩名称 | Partial；wire/decode.mbt；adversarial_test、wire_test、security_fuzz | 只接纳后向指针，检测循环；名称最多 256 步。输出查询不做压缩；不实现所有 DNS RR |
| [RFC 6762 §18、附录 C](https://www.rfc-editor.org/rfc/rfc6762.html#section-18)：mDNS 字段、class 高位与名称 | Supported；wire/decode/query、model/name；name_length_test、wire_test | mDNS 名称工程上限 256 wire 字节含终止；问题 QU 和记录 flush 独立建模。发 QM，不请求 QU。未知 RR 保留 opaque bytes，不缓存为受支持记录 |
| [RFC 6762 §5.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-5.2)：持续查询 | Partial；engine/query.mbt；query_test | 初始 20..120ms、1s..1h 退避、80..82/85..87/90..92/95..97% 刷新。注入种子与时钟；没有多个独立本机 responder 的协调机制 |
| [RFC 6762 §7.1–7.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.1)：Known Answers 与 TC | Partial；wire/query、engine/query；multipacket、known_answer_limits、fallback、protocol_probe、protocol_live | 剩余 TTL 至少半寿命；首包问题、后续仅答案，非尾包 TC=1，尾包 TC=0。有界序列、可诊断中断/回退。独立解析器+实际 UDP 已测；完整独立 responder 抑制/等待行为仍 Untested |
| [RFC 6762 §10.1–10.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-10.1)：goodbye、flush 和救回 | Partial；cache/cache.mbt；cache_test、shared_ptr_test、srv_rrset_test | 一秒宽限与最近分包保护；共享 DNS-SD PTR 忽略异常 flush 位。不实现反向 PTR 唯一 RRSet；TXT 使用最新批次保守策略 |
| [RFC 6762 §11、§14](https://www.rfc-editor.org/rfc/rfc6762.html#section-11)：本地链路和多接口 | Partial；native/ingress、socket.c、browser；ingress_wbtest、protocol_live/ingress、interface | 所选接口、mDNS 组播目标、源5353；默认允许叠加子网。可选来源白名单/TTL=255，TTL 缺失时严格策略拒绝。单播、IPv6 组播和自动迁移 Unsupported；地址/索引不变的换网需宿主通知 |
| [RFC 2782：Priority/Weight/Target](https://www.rfc-editor.org/rfc/rfc2782.html)：SRV 候选 | Partial；engine/srv.mbt；srv_test、srv_weight_wbtest、srv_rrset_test | priority 升序；同组固定 seed 派生加权排列、闭区间抽票。零权重和根目标有专项回归；这是可复现候选顺序，应用负责连接和重试，不是每次连接重新抽样的调度器 |
| [RFC 6763 §4–6、§7.1](https://www.rfc-editor.org/rfc/rfc6763.html#section-4)：实例、解析、TXT、子类型 | Partial；model/txt、engine/engine/resolve；model_test、subtype_test、resolve_test、lifecycle_contract_test | 只浏览显式 local 类型/实例；TXT 缺失或冲突保持部分状态。细节见[解析契约](dnssd-resolution-contract.md)。Avahi 子类型同 VM 已测 |
| [RFC 6763 §9–12](https://www.rfc-editor.org/rfc/rfc6763.html#section-9)：类型/域枚举、发布与附加记录生成 | Unsupported；无发布者 | 可接纳已有附加记录，不能据此声称实现枚举、服务发布、探测、重命名或域注册 |
| [RFC 8553 §3.1](https://www.rfc-editor.org/rfc/rfc8553.html#section-3.1)：SRV `_Proto` 下划线注册模板 | Partial；engine/engine.mbt 的类型校验、subtype_test | 该 RFC 更新下划线命名与 IANA 注册说明，并非设备冲突处理协议；本库限 `_tcp`/`_udp`，不实现注册表查询，也不替应用注册新名称 |
| [RFC 6763 §15](https://www.rfc-editor.org/rfc/rfc6763.html#section-15)：安全考虑 | Partial；[安全模型](security-model.md) | 发现不等于认证；来源策略不约束广告端点，不防同链路伪造；应用认证是独立责任 |

工程限制（9000 字节、256 个问题/RR、缓存/事件/回放总量）属于实现预算，不是 RFC 对所有实现统一规定。DNS TCP、通用单播 DNS、NSEC 负缓存、发布者和跨子网反射不在当前支持范围。没有通过所有平台、所有 RFC 条款、第二物理设备或 Bonjour 的声明。
