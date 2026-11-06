# Engine 与 Browser 行为契约

状态：2026-11-06，main / 0.2.1-dev（未发布）。0.2.0 归档不包含本轮来源、预算、版本化事件和恢复 API；最新验证见[第四轮记录](security-review-20261106.md)。服务完整性的具体条件见[解析契约](dnssd-resolution-contract.md)，不可信输入见[安全模型](security-model.md)。

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
| 查询任务 | 256 / 8192 | 超额进入 deferred_queries；每 1000ms 轮换容量窗口，next_deadline 包含轮换。稳定集合在 ceil(N/capacity) 个窗口中获得排期；持续任意增删无无条件延迟保证 |
| 订阅 | 64 / 64 | 新增失败，旧兴趣保留 |
| 待发问题 | 64 / 64 | outbound_limit；到期任务延后 1000ms；不丢弃订阅 |
| 一组 Known Answers | 64 包、16383 答案，另受字节预算限制 | 编码错误；Engine 对有效问题退化为普通 QM 并诊断 known_answer_limit；无效问题诊断 query_invalid |
| 事件 | 256 / 16384，最小 2 | 清除旧队列，增加 dropped_events，插入 event_overflow 再继续入队；快照状态独立保留 |
| Browser 录制队列 | 256 帧 | 丢最旧帧并累计 dropped_captures；Browser 可继续浏览；CLI 拒绝保存有丢帧的 trace |
| CLI trace 累积 | 8 MiB / 10000 帧 | 超限结束该 CLI 操作并释放 Browser，不保存不完整录制 |
| 单次 Replay | 10000 帧、8 MiB 输入 UTF-8、4 MiB 解码包、65536 个输出、8 MiB 输出 UTF-8 | 累计计数含多次 step_line；预算耗尽关闭 Engine，该 Replay 后续调用均失败；当前帧不返回部分结果 |
| 实时包速率 | Engine/Browser 默认 256 包/s，来源 64 包/s；上限 65536，0 显式关闭 | 令牌桶突发等于每秒速率，Native 用尽全局预算暂停收包；来源满表拒绝新来源，1 秒闲置后回收。无逐包限速诊断，见资源保护说明 |

Replay.new 可降低预算，不能突破硬上限；每帧限 32768 个 UTF-16 代码单元、JSON 深度 16、重复键拒绝，packet_hex 在解码前限 18000 字符。输入/输出字节预算含每行一个换行。通过单行长度检查的非法命令仍消耗帧和输入预算；普通格式错误可继续输入有效帧，预算耗尽则必须创建新 Replay。不能自行向其公开的 engine 注入额外工作再宣称遵守回放预算。

这些是逻辑容量与有限工作量约束，多个最大值可以同时占用资源，不是整个进程的固定字节/CPU 上限。组合回归见 `src/engine/resource_pressure_test.mbt`；长时间核心循环与实网证据分别见[性能记录](performance.md)和[专题验证](specialized-interop.md)。

## 恢复

Engine.poll_envelope 返回 EventEnvelope(epoch, sequence, event)，溢出时 epoch 增长，sequence 为该 Engine 的事件水位。state_view 原子返回同一时刻的 epoch/sequence/快照。异步消费者用新 view 整体替换后，丢弃旧 epoch 或 sequence <= view.sequence 的已复制事件；不要在替换快照后再逐条应用这批旧事件。poll_event 仍兼容，但不会携带版本信息；两种 poll 消费同一队列。版本仅在同一 Engine/Browser scope 内比较，不跨重开和进程比较。

Browser.poll_batch 返回事件与完整 StateView，适合异步界面整体替换；state_view 和 engine_stats 也可单独读取。读取之后的时间与状态可能继续变化；宿主跨线程共享这些对象不受支持。记录观察来源变化本身不作为服务内容更新事件。

同步 Browser.poll 报错时由调用方关闭；异步 run 使用 defer，在正常结束、回调抛错或取消时关闭。接口失效报告 InterfaceUnavailable；新建 Browser、恢复订阅并重建视图。不会自动重试连接或转移接口。录制在关闭后仍可取走；原始录制和脱敏摘要均按[隐私约束](security-model.md)分享。

Native 操作检测单调时钟不可用/倒退时报告 socket_error；elapsed 显示值不倒退。close 即使检测到时钟失败，仍使用最后有效时间结束录制并释放 socket/Engine。不要用系统 UTC 时间代替注入单调时间；长期暂停最多补满一个速率突发，但缓存和 resolver 到期仍按实际推进时间处理。

run 活动期间，另一个 run、公开 poll、browse/resolve/cancel 抛 DriverBusy；检查发生在第二个 run 的关闭 defer 之前，不会误关第一个驱动者。只允许一个协作式驱动者；这不是多线程互斥锁。外部 close 或 notify_network_changed 可用于停止，run 在下一协作边界退出；关闭幂等。地址/索引未变的换网由宿主调用 notify_network_changed，旧对象立即关闭，重新 open/browse 后使用新 scope。库不自动恢复业务订阅。

查询容量压力中的轮换只保留当前窗口任务，重新进入窗口的任务重新建立退避/刷新安排；不宣称压力状态与无限容量时的发送时刻完全相同。query_limit 在进入压力状态时诊断一次，退出后再进入可再次诊断。按 next_deadline 推进时钟，否则任何定时公平性都无法执行。
