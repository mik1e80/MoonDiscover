# Engine 与 Browser 行为契约

状态：2026-11-05，main / 0.2.1-dev。0.2.0 发布归档不包含新增来源策略、TTL 元数据、Replay 总量预算和脱敏导出。服务完整性的具体条件见[解析契约](dnssd-resolution-contract.md)，不可信输入见[安全模型](security-model.md)。

## 分层与调用顺序

| 责任 | Engine | Native Browser |
| --- | --- | --- |
| 报文、缓存、聚合、查询调度 | 执行；不会创建 socket | 调用 Engine；发送其待发报文 |
| 时间 | 接收调用方注入的单调毫秒 | 系统单调时钟，以 open 为原点 |
| 网络路径与来源策略 | 不检查真实接口或 IP 元数据 | 显式活动 IPv4、入站接口/组播目标/源端口检查、可选 CIDR 和 TTL 策略 |
| 隔离范围 | 使用调用方提供的 scope | 每次 open 生成新的 scope |
| 关闭 | 清空缓存、订阅、查询与分包；发出有限的移除事件 | 同时关闭 socket；幂等 |
| Replay | 输入来自文件，不访问网络 | 无需 Browser |

自定义适配器先接纳网络来源，再调用 ingest；根据 deadline 推进时间；每次状态变化后处理事件。必须连续取尽并发送 poll_outbound 的 TC 分包，再修改输入、订阅或时间。接收报文、取消等会清除旧尾包并产生 `outbound_batch_interrupted`。不要并发或从回调重入修改同一个 Engine/Browser。

时间范围为 `0..9223367741887480807` 毫秒，允许相同时间，禁止倒退；同毫秒报文按接纳顺序区分。TTL 为 UInt32 秒并转为毫秒。Replay 还要求 JSON 时间为 `0..9007199254740991` 的整数。无效报文/DTO、时间或容量导致的缓存接纳失败不提交半更新。适配层可另行 advance，已有记录仍会随实际时间过期。

## Scope 生命周期

scope 是一次接口/网络代次的隔离标识，长度 1..256 字符，不是设备身份或持久 ID。同 scope、基础类型、实例名构成服务身份；同名实例在不同 scope 保持独立。基础浏览与子类型共享这个身份；子类型只过滤 PTR 成员资格。

Browser 的 scope 含接口地址、索引、单调时钟和独立随机 nonce。固定调度 seed 不会强制复用 scope；不同进程不得借此共享/合并缓存。纯核心调用者自行生成 scope。每次重开、地址变化、网卡重连或已知网络变化都应使用新 scope 并创建新的 Engine/Browser。地址和索引未变的 Wi-Fi 换网无法由当前轮询可靠识别，宿主须通知并重建；不要据此宣称自动迁移。

## 事件与状态

事件以共享服务身份为单位，不是按订阅各发一份。下面是无溢出时的逻辑事件；队列容量可能使中间事件被丢弃。

| 原状态 → 新状态 | 事件 | 调用方含义 |
| --- | --- | --- |
| 无 → 部分 | Seen | 首次进入当前观察集合 |
| 无 → 完整 | Seen，然后 Resolved | 首包已满足记录链 |
| 部分 → 完整 | Resolved | 初次完成或关键数据恢复 |
| 完整 → 部分 | Unavailable | 实例仍有成员/解析证据，但完整性丢失 |
| 部分 → 部分、完整 → 完整，内容变化 | Updated | 可用内容、候选、地址或 missing 变化；并非只针对完整服务 |
| 任意已观察状态 → 无 | Removed | 最后成员证据失效、最后关联订阅取消、超时移除或关闭 |
| 初次 resolve 截止仍未完成 | ResolveTimedOut(id) | 移除该 resolver；无其他兴趣时可同时导致 Removed |
| 资源限制或协议异常 | Diagnostic | 使用稳定 code 分类；不要解析 detail 做程序分支 |

Seen 仅在当前身份从无变有时出现；被 Removed 后再发现会再次 Seen。Resolved 可在每次部分→完整时再次出现。部分→部分不会产生 Unavailable。TTL 递减、重复包、相同内容刷新不单独产生 Updated。一次 reconcile 先处理移除，再处理剩余/新增身份；不要把跨服务的事件排序当作网络发生顺序。

取消一个重复/重叠订阅时，若其他订阅仍观察该身份，不产生 Removed；取消不存在的 ID 抛 UnknownSubscription。初次 resolve 默认 5000ms，可设 1..3600000ms；成功后取消初始截止并持续观察。close 幂等；关闭后的变更调用抛 Closed/BrowserClosed，仍可取完最终事件。

Removed 快照保留最后已知识别和内容字段，但 complete=false、remaining_ttl_ms=0；不能据此发起新连接。正常 snapshots() 返回的数组、地址数组和候选数组被复制，修改它们不改变内部状态。remaining_ttl_ms 是当前所选记录链的最小剩余证据寿命，不是连通性租约。

## 资源退化矩阵

| 资源 | 默认 / 硬上限 | 达到限制后的行为 |
| --- | --- | --- |
| 单包 | 9000 字节；问题+RR 合计 256；单名称 256 步 | 整包拒绝，不能半写入缓存 |
| 缓存记录 | 2048 / 16384 | 新包无法完整接纳则抛 CapacityExceeded，原状态不提交；不逐出有效旧记录 |
| 服务 | 512 / 4096 | 保留仍有效旧服务；新实例省略并诊断 service_limit，实际空位出现后可接纳 |
| 查询任务 | 256 / 8192 | 诊断 query_limit，省略超额查询；订阅保留，下一次重建再评估；没有公平服务保证 |
| 订阅 | 64 / 64 | 新增失败，旧兴趣保留 |
| 待发问题 | 64 / 64 | outbound_limit；到期任务延后 1000ms；不丢弃订阅 |
| 一组 Known Answers | 64 包、16383 答案，另受字节预算限制 | 编码错误；Engine 对有效问题退化为普通 QM 并诊断 known_answer_limit；无效问题诊断 query_invalid |
| 事件 | 256 / 16384，最小 2 | 清除旧队列，增加 dropped_events，插入 event_overflow 再继续入队；快照状态独立保留 |
| Browser 录制队列 | 256 帧 | 丢最旧帧并累计 dropped_captures；Browser 可继续浏览；CLI 拒绝保存有丢帧的 trace |
| CLI trace 累积 | 8 MiB / 10000 帧 | 超限结束该 CLI 操作并释放 Browser，不保存不完整录制 |
| 单次 Replay | 10000 帧、8 MiB 输入 UTF-8、4 MiB 解码包、65536 个输出、8 MiB 输出 UTF-8 | 累计计数含多次 step_line；预算耗尽关闭 Engine，该 Replay 后续调用均失败；当前帧不返回部分结果 |

Replay.new 可降低预算，不能突破硬上限；每帧限 32768 个 UTF-16 代码单元、JSON 深度 16、重复键拒绝，packet_hex 在解码前限 18000 字符。输入/输出字节预算含每行一个换行。通过单行长度检查的非法命令仍消耗帧和输入预算；普通格式错误可继续输入有效帧，预算耗尽则必须创建新 Replay。不能自行向其公开的 engine 注入额外工作再宣称遵守回放预算。

这些是逻辑容量与有限工作量约束，多个最大值可以同时占用资源，不是整个进程的固定字节/CPU 上限。组合回归见 `src/engine/resource_pressure_test.mbt`；长时间核心循环与实网证据分别见[性能记录](performance.md)和[专题验证](specialized-interop.md)。

## 恢复

处理 event_overflow 后，取尽当前批事件，并用 snapshots() 整体替换应用视图。若把状态复制到异步下游，应再比较 dropped_events；这些同步 API 的调用之间不要重入 Engine。

同步 Browser.poll 报错时由调用方关闭；异步 run 使用 defer，在正常结束、回调抛错或取消时关闭。接口失效报告 InterfaceUnavailable；新建 Browser、恢复订阅并重建视图。不会自动重试连接或转移接口。录制在关闭后仍可取走；原始录制和脱敏摘要均按[隐私约束](security-model.md)分享。
