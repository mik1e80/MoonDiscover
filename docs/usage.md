# 库接入与命令行

在 MoonBit 工程执行 `moon add mik1e80/dnssd@0.3.0` 可安装含受限 NSEC、端点筛选和版本化事件的版本。构建和可运行示例见 [README](../README.md#安装与构建)。

纯核心由调用方提供网络报文、不会倒退的毫秒时间和 scope。按已知本地服务类型调用 browse，或按绝对实例名调用 resolve，保存返回的订阅 ID。推进时间后取尽待发数据包，读取事件和快照。每个链路和网络代次使用独立 scope。取消订阅用原 ID，结束时关闭 Engine。

Native Browser 绑定一个活动 IPv4 接口。选择 poll 或 run 作为唯一驱动，及时处理诊断。网络变化时关闭旧代次、打开新 Browser 并重新订阅。异步消费者使用快照水位和事件版本重新同步。处理部分结果时以 missing 和 complete 为准。连接前按应用策略验证地址、端口及服务身份，TXT 只作业务元数据。完整示例见 [Native 入门](../README.md#native订阅真实网络事件)。

CLI 的 doctor 检查接口和绑定。browse 订阅类型并输出 JSONL，resolve 查询已知实例，replay 离线读取录制。先用各命令的 --help 查看当前二进制参数，以 [CLI 手册](../README.md#命令行使用)为示例。默认把原始录制当作可能含本地服务属性的数据，仅分享已检查内容或脱敏输出。不可信录制在独立资源预算内运行。详见 [回放隔离](replay-isolation.md)。
