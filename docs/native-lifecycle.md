# Native IPv4 生命周期与错误

状态：2026-11-01，main / 0.2.0-dev。

`MulticastSocket::open` 显式选择本机 IPv4，Browser 为本次接口运行生成 scope。单个对象由一个调用方驱动；不要并发运行 poll/run 或在回调中重入 poll。多个独立 Browser 可以共享 5353 绑定。

## 关闭与取消

- 同步 `poll` 不拥有对象的最终关闭责任。调用方在打开后设置 `defer browser.close()`，在错误、换网或结束时关闭。
- `run` 在正常结束、参数错误、收发错误、回调错误和异步取消时关闭对象；再次运行需要新建 Browser。
- `close` 幂等，不保留后台收包任务。一个 Browser 关闭不应影响其他共享绑定 Browser；关闭后 poll/browse/resolve/cancel 返回关闭错误。
- `cancel(id)` 仅撤销该订阅；其他活动订阅仍可使用 Browser，剩余待发分包按引擎契约清理。

## 稳定错误分类

调用方可匹配 `TransportError`，或对该类型调用 `diagnostic_code()`，无需解析 Show 文案。

| 分类 | 代码 | 行为 |
| --- | --- | --- |
| BrowserClosed | `transport_closed` | 已关闭的 Browser 或底层 socket 被调用 |
| InvalidArgument | `invalid_transport_argument` | 接口值、时长、收发长度等参数非法 |
| InterfaceUnavailable | `interface_unavailable` | 打开时接口不可用，或运行检查发现原接口失效/索引变化 |
| SocketError | `socket_error` | 系统收发/绑定或必要元数据故障，保留操作上下文与 OS 数值 |

Engine 诊断事件（例如 `packet_rejected`、`event_overflow`）与此处的传输异常是不同通道。完整代码目录见[diagnostics.md](diagnostics.md)。

格式错误的入站 DNS 报文产生 `packet_rejected`，接收循环继续。截断/超长 UDP 按已有适配层规则丢弃；它们不等同于真实 socket 失败。

## 接口恢复边界

当前仍不自动迁移。应用遇到接口变化后，应关闭旧 Browser、确认新活动 IPv4、打开新 Browser 并重新建立业务订阅。新对象使用新 scope，旧接口缓存不跨网络混合。检测当前约每秒检查一次所选 IPv4 的接口索引，不宣称覆盖所有操作系统链路状态通知。

Linux CI 已在独立 network namespace 的 dummy 网卡上删除并恢复地址，验证错误分类、旧缓存清理、新 scope 与订阅重建；报告见 specialized-interop.md。实验复现并修复了周期接口检查前 I/O 失败被误分类的问题。物理 Wi-Fi、IPv6、单播与系统原生异步事件源仍待后续；用户网卡未被修改。

## 已执行的短时检查

`tests/native_cancel` 在 Windows 活动物理 IPv4 上验证取消后关闭并重开、两个共享 Browser、重复 close、无效 run 的关闭、on_tick 回调失败后的关闭，以及稳定错误代码。Linux CI 使用同一程序。此检查不代表长时间资源泄漏审计。
