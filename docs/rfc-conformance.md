# RFC 条款与实现对照

状态：2026-11-20，main / 0.3.0-dev（未发布）。本表按 IPv4 QM 查询端角色记录已实现条款和仍有差异的建议。历史安全证据见[第四轮验证](security-review-20261106.md)，当前证据见[预发布验收](release-acceptance-0.3.0.md)。

状态统一使用 Supported（对应子项已实现且有证据）、Partial（有限行为/有简化）、Unsupported（未实现）、Untested（缺少所列环境的验证）。状态仅修饰该行的范围，不代表整份 RFC。

| 条款与范围 | 状态、实现与测试 | 限制或选择理由 |
| --- | --- | --- |
| [RFC 1035 §4.1.1–4.1.3](https://www.rfc-editor.org/rfc/rfc1035.html#section-4.1.1)：header、question、RR 区域及长度 | Partial；wire/decode.mbt、cache/cache.mbt；wire_test、invalid_record_test、cache/section_test、engine/section_test、security_fuzz | 保留 Answer/Authority/Additional；三种响应 RR 区域均可提供受支持 IN 断言，按名称/类型/RDATA 去重。只接纳 QR=1、opcode=0、rcode=0；关联性由服务记录链判断，不把不相关附加记录直接变成服务。不是通用 DNS resolver |
| [RFC 6762 §18.1、18.4–18.11](https://www.rfc-editor.org/rfc/rfc6762.html#section-18.1)：接收忽略字段 | Supported；cache/cache.mbt；cache/section_test | 接收时忽略 ID、AA、TC、RD/RA/Z/AD/CD，修复此前额外的 ID=0/TC=0 接纳限制；opcode/rcode 非零仍忽略。真正结构截断先被 decoder 拒绝。发送行为与接收规则分开；DTO header 仍必须可表示为 16 位 |
| [RFC 1035 §4.1.4](https://www.rfc-editor.org/rfc/rfc1035.html#section-4.1.4)：压缩名称 | Partial；wire/decode.mbt；adversarial_test、wire_test、security_fuzz | 只接纳后向指针，检测循环；名称最多 256 步。输出查询不做压缩；不实现所有 DNS RR |
| [RFC 6762 §18、附录 C](https://www.rfc-editor.org/rfc/rfc6762.html#section-18)：mDNS 字段、class 高位与名称 | Supported；wire/decode/query、model/name；name_length_test、wire_test | mDNS 名称工程上限 256 wire 字节含终止；问题 QU 和记录 flush 独立建模。发 QM，不请求 QU。未知 RR 保留 opaque bytes，不缓存为受支持记录 |
| [RFC 6762 §5.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-5.2)：持续查询 | Partial；engine/query.mbt；query_test | 初始 20..120ms、1s..1h 退避、80..82/85..87/90..92/95..97% 刷新。注入种子与时钟；没有多个独立本机 responder 的协调机制 |
| [RFC 6762 §7.1–7.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.1)：Known Answers 与 TC | Partial；wire/query、engine/query；multipacket、known_answer_limits、fallback、protocol_probe、protocol_live、tc_interop | 剩余 TTL 至少半寿命。首包含问题，后续仅答案，非尾包 TC=1。同机双响应器实测覆盖立即续包、连续 TC、主动省略及重排续包，以及两个至十三个查询器。zeroconf 两轮共六次从最后一个带 TC 包重设定时器，Avahi 六次在第一续包前已回包。隔离 veth 已验证单个及五至十二个查询器的 zeroconf 指定续包丢包或乱序场景，另有普通 QM 的响应方向丢包、恢复后重新查询、固定延迟、随机丢包及生产 Browser 自动重试证据。十二查询器的响应方向已测定向丢包、恢复后重新查询、固定延迟和生产 Browser 在随机丢包下自动重试。已验证受控响应报文的链路乱序，并用生产 Browser 核对 PTR 与 SRV、TXT、IPv4 地址在乱序时的缓存和聚合。另有普通 QM 的查询方向随机丢包证据，以及单个和十二个生产 Browser 的自动重试及恢复证据。另有双向各 50% 随机丢包的 Browser 发包和解析观测。另实测单 Browser 30s 内的双向随机丢包与十二 Browser 的重叠突发丢包。60s 复测记录了单 Browser 30s 后的重发与解析，另有十二 Browser 的 5s 重叠突发恢复证据。120s 复测观测到单 Browser 在 60s 后仍重发，十二 Browser 的 10 秒重叠突发丢包三轮均完整解析。240s 复测记录了单 Browser 在 120s 后的重发与恢复，十二 Browser 的 20 秒重叠突发丢包三轮均完整解析。480s 复测在独立随机样本中观测到 240s 后重发，固定种子补充轮记录了完整解析，十二 Browser 的 40 秒重叠突发丢包三轮均完整解析。960s 复测在独立随机样本中观测到 480s 后重试，固定种子补充轮记录了完整解析。十二 Browser 的 80 秒重叠突发丢包三轮均完整解析。Avahi 的同类链路实验和跨设备仍待验证。见[实测证据](tc-interop.md) |
| [RFC 6762 §7.3](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.3)：重复问题抑制 | Partial；engine/peer_query、native/ingress；peer_query_test、ingress_wbtest、Linux peer-query | 同 scope 单问题 IN QM，peer 的 Known-Answer 必须是本端计划发送集合的子集，且 peer TTL 不高于本端。临近的普通任务最多延期一次，再次送出后恢复资格。TC、多问题、刷新任务和同源回环不参与 |
| [RFC 6762 §7.4](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.4)：重复回答抑制 | Unsupported；属于 responder 角色 | 接收侧按记录去重不能推导响应端抑制能力 |
| [RFC 6762 §10.1–10.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-10.1)：goodbye、flush 和救回 | Partial；cache/cache.mbt；cache_test、shared_ptr_test、srv_rrset_test | 一秒宽限与最近分包保护；共享 DNS-SD PTR 忽略异常 flush 位。不实现反向 PTR 唯一 RRSet；TXT 使用最新批次保守策略 |
| [RFC 6762 §11、§14](https://www.rfc-editor.org/rfc/rfc6762.html#section-11)：本地链路和多接口 | Partial；native/ingress、socket.c、browser；ingress_wbtest、protocol_live/ingress、interface | 所选接口、mDNS 组播目标、源5353；默认允许叠加子网。可选来源白名单/TTL=255，TTL 缺失时严格策略拒绝。单播、IPv6 组播和自动迁移 Unsupported；地址/索引不变的换网需宿主通知 |
| [RFC 2782：Priority/Weight/Target](https://www.rfc-editor.org/rfc/rfc2782.html)：SRV 候选 | Partial；engine/srv.mbt；srv_test、srv_weight_wbtest、srv_distribution_wbtest、srv_rrset_test | priority 升序；固定 seed 派生加权排列、闭区间无模偏抽票；4096 种种子的宽容分布区间、排列完整性与优先级回归。不是统计证明、密码学随机源或每次连接重抽的负载均衡器 |
| [RFC 6763 §4–6、§7.1](https://www.rfc-editor.org/rfc/rfc6763.html#section-4)：实例、解析、TXT、子类型 | Partial；model/txt、engine/engine/resolve；model_test、subtype_test、resolve_test、lifecycle_contract_test | 只浏览显式 local 类型/实例。TXT 未知或冲突保持部分状态。明确否定、零长度及单空字符串语义等效，测试见 negative_response_test。Avahi 子类型同 VM 已测 |
| [RFC 6763 §9–11](https://www.rfc-editor.org/rfc/rfc6763.html#section-9)：类型/域枚举与服务命名约定 | Partial；仅本地显式类型和实例 | 自动枚举与域注册超出当前实现 |
| [RFC 6763 §12](https://www.rfc-editor.org/rfc/rfc6763.html#section-12)：附加记录 | Supported（接收及消费子项）；cache/cache、engine/query、protocol_live/nsec_expiry | 同一链路作用域内按名称、类型与实例关系聚合。附加信息缺失时安排依赖问题，发布方生成规则不属于本库角色 |
| [RFC 8553 §3.1](https://www.rfc-editor.org/rfc/rfc8553.html#section-3.1)：SRV `_Proto` 下划线注册模板 | Partial；engine/engine.mbt 的类型校验、subtype_test | 该 RFC 更新下划线命名与 IANA 注册说明，并非设备冲突处理协议；本库限 `_tcp`/`_udp`，不实现注册表查询，也不替应用注册新名称 |
| [RFC 6763 §15](https://www.rfc-editor.org/rfc/rfc6763.html#section-15)：安全考虑 | Partial；[安全模型](security-model.md) | 发现不等于认证；来源策略不约束广告端点，不防同链路伪造；应用认证是独立责任 |

工程限制（9000 字节、256 个问题/RR、缓存/事件/回放总量）属于实现预算，不是 RFC 对所有实现统一规定。DNS TCP、通用单播 DNS、发布者和跨子网反射不在当前支持范围。没有通过所有平台、所有 RFC 条款、第二物理设备或 Bonjour 的声明。

## 0.3.0-dev 整改增量（2026-11-18）

本节记录受限 NSEC 查询端新增行为，状态仅覆盖所列能力。

| 条款 | 实现与验收 | 状态 |
| --- | --- | --- |
| RFC 6762 §6.1 / RFC 4034 §4.1 | wire/nsec/decode、cache/negative_cache、engine/query；窗口 0、1–32 字节、忽略不同 next name、无 NSEC 自身位；异常单条忽略 | 实现已接入；专项测试见 negative-response.md |
| RFC 6762 §6.1、§10 | 否定 TTL、作用域、正向优先、到期恢复、共享 PTR 不整体否定，容量原子接纳 | 本轮专项回归；不是 DNSSEC 认证 |
| RFC 6763 §12 | Answer/Authority/Additional NSEC 同样处理，正常服务记录继续聚合 | 本轮 Additional 回归；缺失继续查询 |
| RFC 6762 §5.2、§7.1–7.2 | 原抖动/退避/KA 回归保留；仅取消被否定的问题，不影响 A/其他类型和共享 PTR | 有界实现；多 responder 等待/抑制完整实测仍待完成 |
| RFC 6762 §18.1、§18.5 | 保留忽略接收 ID/TC，真实结构截断仍拒绝，响应 Question 不作缓存 | 顾问概述与原文不同时以原文为准 |
