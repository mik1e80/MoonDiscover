# 名称、TXT 与事件模型

常用类型由根包 `mik1e80/dnssd` 暴露；详细接口见仓库中的 `pkg.generated.mbti` 与各包生成接口。

## 名称与 TXT

- `DnsName::from_utf8_labels` 接收已划分的标签。实例名 `中文.服务` 可以是一个标签，不能先按点拆分。
- `from_labels` 和 `labels()` 保留任意原始字节，数组在 API 边界复制。每个标签 1..63 字节，完整 mDNS 名称最多 256 wire 字节（含根终止字节，RFC 6762 附录 C）；空标签数组表示根。
- `same_name` / `canonical_key` 只折叠 ASCII 大小写，保留标签边界。`to_presentation()` 生成可逆的绝对 ASCII 转义文本；`parse()` 支持 UTF-8、转义点/反斜杠及 `\DDD` 原始字节。
- `TxtRecord` 保留条目顺序、二进制值、无值与空值。单条最多 255 字节，总 RDATA 最多 65535 字节。
- `lookup` 区分 Missing、Flag、Value；键按 ASCII 不区分大小写，重复键第一项胜出。无效键保留在原始条目中但不参与查询。

JSON 保留 `txt_entries_hex`，避免把任意 TXT 字节强行转换为 UTF-8；端口、目标和原因使用标量或 `null`。实例展示名与原始标签字节不是同一种表示。

## 服务快照与生命周期

`ServiceSnapshot` 包含 `scope`、服务类型、实例、可选 target/port/TXT、地址、`missing`、`complete` 与 `remaining_ttl_ms`。缺少 SRV、TXT、地址或遇到冲突时仍能提供部分状态。完整状态表示当前记录链满足本实现的要求，不保证连接一定成功。

Engine 的 `Seen` 表示首次观察实例，`Resolved` 表示成为完整状态，`Updated` 表示内容变化，`Unavailable` 表示已观察实例的完整性丢失，`Removed` 表示不再属于当前观察结果。TTL 刷新或重复包不单独产生内容更新。移除快照保留最后已知字段便于识别，但 `complete=false`、剩余 TTL 为 0。

多个订阅可共享同一范围的服务；同名实例在不同 scope 中互不合并。Native Browser 将指定接口与本次运行关联为 scope，纯核心调用者负责提供有意义的范围标识。scope 是观察范围，不是服务的永久全局 ID。

事件、服务和缓存均有上限。事件队列溢出会发出 `event_overflow` 诊断并计数；消费者应调用 `snapshots()` 重新同步。返回数组复制以避免消费者修改内部状态。

Engine 和 Native transport 的诊断代码、触发条件及调用方处理建议见[诊断目录](diagnostics.md)。诊断代码供程序分类，detail 仅用于说明，不应作为分支条件。

## 时间与输入

纯核心使用调用者注入的单调 `Int64` 毫秒时间，不读取系统时钟。报文到达另有顺序号，避免同一毫秒内的新旧唯一记录被误当成冲突。Native 层提供系统单调时钟；Replay 保存命令时间与随机种子，使同一输入可重现。

模型轻量用例覆盖中文标签内点、二进制/空值/重复键、损坏输入、转义文本及 256 字节名称边界。引擎用例覆盖乱序、重复、更新、到期、范围隔离、队列溢出和同毫秒更新，见 [验证记录](verification.md)。
