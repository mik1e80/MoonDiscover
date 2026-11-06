# 高频输入与资源退化

2026-11-06，main / 0.2.1-dev，未发布。容量限制、时间速率和进程预算是三层不同约束，不代表认证或网络不丢包。

| 层 | 默认 | 发生限制时 |
| --- | --- | --- |
| Native 全局接收 | 256 包/s，突发 256 | 预算用尽停止本轮读取 OS 队列，仍推进缓存/查询时间；receive_pauses 增长 |
| Native 单来源 IPv4 | 64 包/s，突发 64；最多 128 个来源桶，可配到 256 桶 | 来源超额或满表的新来源静默拒绝，source_rate_dropped 增长；闲置一秒才移除，不因伪造新 IP 无限建表 |
| Engine ingest/ingest_message | 256 次/s，突发 256 | 解码/缓存重建前抛 RateLimited，rate_dropped 增长；不逐包生成 Diagnostic |
| 离线 Replay | 保留文件/帧/字节/输出预算 | 不套用实时速率，以保证合法同时间戳 burst 可回放；需要硬预算时使用 replay_guard |

限额可设 0..65536；0 显式关闭相应速率保护。Browser.open 的 packet_limit 同时传给内部 Engine；source_limit=0 仅关闭来源桶，source_capacity 默认 128。CLI browse/resolve 支持 `--packet-rate 256 --source-rate 64`。单个浏览对象最多读取 64 包/poll，只有一个驱动者；多个 Browser/Engine 的配额独立，不是整个进程或全网的总限额。

PacketBudget 使用注入单调毫秒和整数千分令牌，任意间隔的接纳量上界为初始突发 B 加 `rate * elapsed / 1000`。长时间暂停最多补满一个突发，不积累无限信用；时间倒退拒绝，不因极大时间差乘法溢出。失败输入也消耗已分配的尝试预算，时间应对所有尝试保持单调。Engine 的 ingest_message 也受限，不能以 DTO 绕过保护。

Browser.stats 区分 received（已从 socket 读到）、accepted（提交 Engine 成功，不等于新增缓存记录）、policy_dropped、source_rate_dropped、receive_pauses、packet_rejected 与 core_rate_dropped。暂停读取的 OS 丢包无法可靠计数，不能把 receive_pauses 当丢包数。来源桶在路径过滤前计费，错误报文同样有成本，且可能占用合法发送者额度。

限速可能漏掉 TTL 更新和 goodbye；不会伪造“已收到”或优先信任某个 goodbye。缓存仍正常老化，应用应处理 Unavailable/Removed、重试发现并认证连接。队列中的包也可能延迟处理；这些保护不保证硬实时或特定 CPU 百分比。攻击者可伪造来源 IP，单来源桶不提供公平身份。高安全部署还需 OS、网络设备与应用层策略。

对应回归：model/budget_test、engine/rate_test、native/rate_wbtest，以及 Linux protocol_live/ingress 的实际 UDP 全局/来源限额、录制溢出后继续发现。缓存/查询/事件组合压力与异步恢复见[行为契约](behavior-contract.md)。
