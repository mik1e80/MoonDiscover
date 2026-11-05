# 当前协议矩阵

参考：[RFC 6762](https://www.rfc-editor.org/rfc/rfc6762)、[RFC 6763](https://www.rfc-editor.org/rfc/rfc6763)、[RFC 8553](https://www.rfc-editor.org/rfc/rfc8553)。状态日期：2026-11-05。本表描述 main（0.2.1-dev，未发布）的代码和证据，不是完整规范符合性审计；与发布包差异及四种状态定义见[范围矩阵](SCOPE.md)，条款、偏差与对应测试见 [RFC 对照](rfc-conformance.md)。

| 事项 | 实现与验证 | 状态与限制 |
| --- | --- | --- |
| 标签字节与实例内点 | `src/model/name.mbt`、模型和文本用例 | 标签边界保留；仅 ASCII 大小写折叠；展示文本可逆 |
| mDNS 名称上限 | `name_length_test.mbt`、wire 解码 | 256 wire 字节含根终止字节，依据 RFC 6762 附录 C |
| TXT | `src/model/txt.mbt`、模型用例、实网 binary 属性 | 二进制、flag/empty 区分、重复键第一项；无效键保留但不查询 |
| 压缩名称 | `src/wire/decode.mbt`、损坏报文用例 | 后向指针、边界/步数限制；不是任意 DNS 报文 codec |
| PTR/SRV/TXT/A/AAAA | wire 用例与独立 zeroconf 响应 | 未知 RR 保留为 opaque bytes；AAAA 解码不等于 IPv6 传输 |
| QU 与 cache-flush 位 | 独立 Question/Record 字段，query/cache 用例 | 当前发 QM，Known-Answer 清除 class 高位；不请求 QU |
| 缓存接纳 | `src/cache/cache.mbt` | 只缓存 ID=0、完整成功响应中的受支持 IN RR；查询中的 Known-Answer 不进缓存 |
| TTL 与范围隔离 | cache/engine 虚拟时钟用例 | UInt32 TTL、单调毫秒、范围键；重复刷新不制造内容更新事件 |
| goodbye 与 flush | cache 用例与实网 goodbye | goodbye 一秒可救回；flush 对旧成员宽限一秒、保护近期分包成员 |
| 共享 PTR 异常 flush | cache/engine 的 shared_ptr_test.mbt | 忽略错误高位，保留同组其他实例及常规 PTR 查询；此缓存不实现反向 PTR 唯一性 |
| 服务聚合 | `src/engine/engine.mbt`、乱序/事件用例 | PTR→SRV/TXT→A/AAAA；部分状态、可用性变化、明确移除原因 |
| SRV 候选 | `src/engine/srv.mbt`、`srv_test.mbt`、`srv_weight_wbtest.mbt`、`srv_rrset_test.mbt`、[选择契约](srv-selection.md) | priority 升序、固定 seed 派生加权顺序；跨响应包汇集未过期 RRSet，遵守 flush 宽限和救回；调用方负责连接与失败重试 |
| 服务容量 | capacity_test.mbt 的两种订阅回归 | 优先保留仍有效的已公布实例；省略新实例只诊断，真实移除后可填入候选 |
| 唯一记录更新顺序 | `update_order_test.mbt`、实网更新 | 按报文到达序号识别新旧，避免同毫秒误冲突；同批冲突保持未完成 |
| QM 查询调度 | `src/engine/query.mbt`、注入时钟/种子用例 | 初始 20..120ms 抖动、1s..1h 指数退避、按范围/名称/类型去重 |
| 刷新与 Known-Answer | query、multipacket、known_answer_limits/fallback、replay 与 `tests/protocol_probe` | 剩余 TTL 至少半寿命；独立测试解析器检查 Engine 实际出站字节、首包问题、后续答案、TC 链和 260 条答案顺序；最多 64 包/16383 条，另受字节上限约束；超限退化为普通 QM 并当帧诊断；取消中途已验证；Linux 实际 UDP 与独立测试解析器专项通过，见 specialized-interop.md |
| 服务子类型 | subtype_test.mbt | 只接受对应 subtype PTR 的实例，沿用基础 SRV/TXT/身份；基础/子类型重叠不重复事件；Avahi 独立发布者专项通过，见 specialized-interop.md |
| 指定实例 resolve | `src/engine/resolve.mbt`、resolve 用例 | 不依赖 PTR；初次超时 1..3600000ms，成功后持续观察至取消/关闭 |
| 订阅与取消 | Engine 与 Native cancel 实验 | 重复订阅共享状态；取消清理关联待发查询；异步退出释放 socket |
| 网络接纳与发送 | Native、Windows zeroconf、Linux Avahi 与本轮 ingress 报告 | 显式 IPv4 接口，源5353/目标组播/接口匹配；发送 TTL=255；main 新增可选来源 CIDR/严格 TTL 和接收元数据。Linux 实网通过，Windows 本轮 TTL 实收仍 Untested；单播排除 |
| 确定性回放 | `src/replay`、CLI 冒烟、实网录制 | 严格 JSON、时间与种子恢复、同输入同事件/待发报文；网络 I/O 在核心之外 |
| NSEC、发布者 | 无 | 未实现负缓存、发布/探测/重命名；未知 RR 仍作 opaque bytes |

工程上限为单包 9000 字节、问题与 RR 合计 256、单名称解码 256 步。这些是实现限制，不是 RFC 统一规定。资源容量和平台状态见 [范围文档](SCOPE.md)。

SRV 候选支持跨多个响应包的存活 RRSet，不替调用方执行连接与失败重试。TXT 冲突仍保守保持未完成。单播、接口自动切换、跨子网和 IPv6 组播不在当前适配层范围；不存在完整 RFC 支持的声明。RFC 8553 涉及下划线名称注册模板更新，不是设备冲突处理规范。
