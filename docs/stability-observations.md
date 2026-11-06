# Native 稳定性观测与故障注入

2026-11-06，main / 0.2.1-dev，未发布。所有本轮执行均为短时检查；没有执行 1h/6h 测试。

`tests/native_fault` 在测试专用编译单元中包含真实 socket shim，仅拦截 OS 调用；生产包没有环境变量后门或故障开关。验证 reuse、packet-info、bind、加入组播、出站接口、组播 TTL 六个初始化失败路径，以及 receive/send 两个失败路径。每次检查创建/关闭句柄平衡、另一个生产 Browser 仍可 poll，最后能重新打开。它不证明每一种 OS 错误均已覆盖。

`tests/native_cancel` 另验证异步取消、参数/回调错误释放、共享 Browser、重复关闭，以及 run 中重入 poll/第二 run 被 DriverBusy 拒绝且不误关原驱动者。通知网络变化停止后须重新 open/browse。Native 纯函数用例模拟时钟 -1/倒退，分类为 socket_error；close 采用最后有效时间收尾，没有实际修改系统时钟。

`tests/native_ttl` 用生产 receive 函数从临时端口的 IPv4 **单播回环**实际收取 TTL 255/254/1，两平台均有对应 CI；这检查真实 ancillary 解码，不证明 Windows 的 mDNS 组播路径或第二设备。Browser 的单播接纳仍未支持。Linux protocol_live/ingress 则单独验证实际 mDNS 组播、限速、来源拒绝与录制队列满后继续浏览。

`tests/live_soak` 同时驱动两个 Browser，每十分钟采样 RSS、句柄/FD、缓存、服务、查询、丢事件、速率和接口状态，结束后检查两者缓存为空及句柄回到预热基线。运输错误会结束这次观察，不伪装自动迁移成功。没有观察到服务时只证明对象/资源生命周期，不证明服务发现完整。

```powershell
.\scripts\moon.ps1 build tests/live_soak --target native
.\_build\native\debug\build\tests\live_soak\live_soak.exe 192.168.1.23 3600
# 或：将最后一个参数改为 21600，执行六小时观察
```

替换为受控测试接口；最好准备独立 `_mdprobe._tcp.local.` 发布者和预先声明的网络变化步骤。输出在 `.tools/live-soak-report.json`，途中样本在 `.tools/live-soak-progress.json`。启动时写入 passed=false，只有正常闭环结束才改为 true。CI 仅运行 2 秒冒烟；本轮不把它算作小时级压力报告，也没有 Wi-Fi 真实断连/同地址换网或 Bonjour 证据。

本轮流程：`scripts/native-local-smoke.mbtx [IPv4]`。省略地址时，测试专用 UDP connect 查询路由地址，不发送应用报文、不修改网卡，避免依赖慢启动的 Windows CIM。实际接口验证仍在 Browser.open 内执行。该辅助能力不意味着生产 Browser 自动枚举所有网卡或自动切换。
