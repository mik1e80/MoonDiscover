# Native IPv4 生命周期与错误

状态：2026-11-06，main / 0.2.1-dev（未发布）。最新运行证据见[第四轮记录](security-review-20261106.md)。

`MulticastSocket::open` 显式选择本机 IPv4，Browser 为本次接口运行生成 scope。单个对象由一个调用方驱动；不要并发运行 poll/run 或在回调中重入 poll。多个独立 Browser 可以共享 5353 绑定。

main 的 scope 含独立随机 nonce、接口地址/索引和本次运行原点，固定 seed 仅控制调度，不控制身份。每次重开或已知网络变化都应使用新 scope。地址和索引未变的换网需宿主主动通知；不保证自动识别。完整定义和事件/容量契约见[行为契约](behavior-contract.md)。

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
| DriverBusy | `browser_driver_busy` | run 已有驱动者；第二个 run 或公开 poll/browse/resolve/cancel 被拒绝，不关闭原驱动者 |
| InvalidArgument | `invalid_transport_argument` | 接口值、时长、收发长度等参数非法 |
| InterfaceUnavailable | `interface_unavailable` | 打开时接口不可用，或运行检查发现原接口失效/索引变化 |
| SocketError | `socket_error` | 系统收发/绑定或必要元数据故障，保留操作上下文与 OS 数值 |

Engine 诊断事件（例如 `packet_rejected`、`event_overflow`）与此处的传输异常是不同通道。完整代码目录见[diagnostics.md](diagnostics.md)。

格式错误的入站 DNS 报文产生 `packet_rejected`，接收循环继续。截断/超长 UDP 按已有适配层规则丢弃；它们不等同于真实 socket 失败。

入站来源策略先于录制与 Engine 执行。错误接口、目标、源端口或不满足可选 CIDR/TTL 策略的包静默丢弃，不为每个拒绝包产生诊断。接收 IP TTL 缺失时 Datagram.ip_ttl=None，严格模式拒绝。默认不按子网或 TTL=255 增加硬性限制；身份认证边界见[安全模型](security-model.md)。

## 接口恢复边界

当前仍不自动迁移。应用遇到接口变化后，应关闭旧 Browser、确认新活动 IPv4、打开新 Browser 并重新建立业务订阅。新对象使用新 scope，旧接口缓存不跨网络混合。检测当前约每秒检查一次所选 IPv4 的接口索引，不宣称覆盖所有操作系统链路状态通知。

宿主可调用 notify_network_changed 主动结束旧代次，即使地址和索引没变也会关闭；重建与恢复订阅仍由宿主执行。只支持单一协作式驱动者，DriverBusy 不是多线程锁。回调内读快照/版本可用，不能重入变更方法；close/通知允许用于停止运行。

操作中的单调时钟不可用或倒退归类为 socket_error；elapsed 显示值不倒退。关闭时若时钟异常，用最后有效时间结束录制并照常释放资源，不生成负时间帧。该分类有注入原始时间值的纯函数测试；没有声称改写或破坏实际 OS 单调时钟。

Linux CI 已在独立 network namespace 的 dummy 网卡上删除并恢复地址，验证错误分类、旧缓存清理、新 scope 与订阅重建；报告见 specialized-interop.md。实验复现并修复了周期接口检查前 I/O 失败被误分类的问题。物理 Wi-Fi、IPv6、单播与系统原生异步事件源仍待后续；用户网卡未被修改。

## 已执行的短时检查

`tests/native_cancel` 在 Windows 活动物理 IPv4 上验证取消后关闭并重开、两个共享 Browser、重复 close、无效 run 的关闭、on_tick 回调失败后的关闭，以及稳定错误代码。Linux CI 使用同一程序。此检查不代表长时间资源泄漏审计。
