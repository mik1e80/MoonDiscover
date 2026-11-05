# DNS-SD 解析契约

状态：2026-11-05。此契约以当前 Engine 实现为准，基础解析与 SRV RRSet 行为已在 0.2.0 发布。它不认证服务，不保证端点可连接。

1. browse 接受 `_service._tcp.local.`、`_service._udp.local.` 或一个 subtype 标签加 `_sub` 的选择性浏览。基础服务标识采用本实现的字母/数字/连字符和长度校验；不自动枚举类型或访问广域 DNS。实例名由一个原始字节标签加基础类型组成，标签内的点不拆分。
2. browse 由对应 PTR 建立成员资格；子类型 PTR 必须指向同一基础类型实例。只有基础 PTR 不满足子类型浏览。resolve 直接观察已知实例，无需 PTR，但至少有 SRV 或 TXT 证据后才产生 Seen。相同 scope、基础类型和实例只公开一个身份。
3. complete=true 需要：至少一个 SRV 候选、首选目标非根且端口非零、唯一可用 TXT、首选目标至少一个 A 或 AAAA。TXT 缺失为 `txt`；最新接纳批次有多个不同 TXT 为 `ambiguous_txt`；空 TXT 可以满足 TXT 存在条件。其他 missing 值为 `srv`、`unavailable_srv`、`addresses`。完整状态是本库选择的保守策略，不能推导可达性、认证或“所有 RFC 行为已支持”。
4. SRV 汇集同 scope 未过期 RRSet，包括跨响应包、一秒 flush/goodbye 宽限和分包救回；排序和固定 seed 规则见 [SRV 契约](srv-selection.md)。平面 target/port/addresses 对应首选候选，首选缺地址时不自动跳到备用。每个候选保存它自己的地址；应用负责连接失败后的尝试、超时和认证。
5. A 和 AAAA 保留为 4/16 字节地址数组并排序。多个实例可共享主机地址；撤销一个 PTR 不删除其他实例。地址变化、SRV 候选或 TXT 内容变化会触发相应 Updated/Unavailable/Resolved，TTL 刷新不单独触发内容事件。AAAA 解码和显示不代表 IPv6 组播、地址作用域管理或 IPv6 连接支持。
6. remaining_ttl_ms 取成员证据、所选 SRV、所选 TXT 及所选主机所有已接纳地址中的最小到期时间。缓存 TTL=0 goodbye 保留一秒，可被重公告救回。TXT 使用最新到达批次，不把早期仍在宽限中的 TXT 一概视为冲突；这与 SRV 的完整 RRSet 汇集不同，是当前有限策略。

名称与 TXT 的细节见[模型说明](model.md)。无效键仍保留于原始 TXT 中但不参与 lookup；键 ASCII 不区分大小写、重复键第一项胜出、flag 与空值区分。不要将任意值隐式当作 UTF-8 或可信配置。

对应验证：`engine_test.mbt`、`subtype_test.mbt`、`srv_rrset_test.mbt`、`lifecycle_contract_test.mbt`、`update_order_test.mbt`、`resolve_test.mbt`、`removal_reason_test.mbt`、`model_test.mbt`。它们验证可观察行为；独立实现、平台及实网范围见[协议矩阵](protocol-matrix.md)，不合并成完整 RFC 认证。
