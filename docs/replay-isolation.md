# 独立进程回放预算

2026-11-06，main / 0.2.1-dev，未发布。`replay_guard` 启动一个**可信的本地 Native CLI** 处理不可信 trace；不在当前进程里直接解析文件。它丢弃子进程 stdout/stderr，只输出资源检查结果，不导出事件。需要保留事件的应用须自行提供受控输出通道和上限。

```powershell
.\scripts\moon.ps1 build cmd/moondiscover cmd/replay_guard --target native
.\_build\native\debug\build\cmd\replay_guard\replay_guard.exe .\_build\native\debug\build\cmd\moondiscover\moondiscover.exe trace.jsonl 3000 256 2
```

参数依次为可信 CLI 路径、trace 路径、墙钟毫秒（10..60000）、内存 MiB（32..1024）、CPU 秒（1..60）。正常退出 child_exit=0；超时 child_exit=124，CPU 终止一般为 125 或平台信号码。工具自身也以非零退出报告失败。超限子进程被终止，不能继续使用半运行的 Replay；父进程可重新启动一个全新任务。

- Windows：子进程先挂起创建，加入带 kill-on-close/进程提交内存/用户 CPU 约束的 Job，再恢复。监督器约每 10ms 比较累计用户+内核 CPU 和墙钟；只继承显式 NUL 句柄，不向子进程传递任意父句柄。作业配置失败不会回退到无保护运行。
- Linux：子进程先设置独立进程组和 RLIMIT_AS/RLIMIT_CPU，再 exec 可信 CLI；墙钟超时杀死该组并回收子进程，不留下后台任务，关闭 core dump。内存指标为该平台的峰值 RSS。

两平台的内存语义不同：Windows 限提交内存，Linux 限虚拟地址空间；报告的 peak_rss_or_commit_bytes 也不同，不能当作相同 RSS 指标直接比较。CPU 限制存在采样/OS 秒级粒度，不保证精确到一个 CPU 指令。限制 CLI 子进程不限制监督器本身；所有 Browser/Engine 也不会自动获得这些 OS 约束。

这不是通用代码/文件系统/网络沙箱；必须信任所指定的可执行文件，文件权限仍由宿主账户控制。不要运行第三方未知程序来处理 trace。源文件本身仍受 CLI 的有界读取和 Replay 累计预算限制，离线回放不会因为高密度虚拟时间戳被实时包速率误限。

`scripts/guard-smoke.mbtx` 检查正常 fixture，以及特制的等待、分配内存和忙循环子进程；这些故意失败仅用于验证预算执行，**不是发现的协议漏洞**。结果见本轮证据。该工具没有自动把所有文件处理阶段的 CPU 细分；墙钟/CPU 覆盖整个子进程，不能据此归因某个解析阶段。
