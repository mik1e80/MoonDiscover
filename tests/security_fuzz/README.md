# 有界恶意输入 fuzz

这是一项在每次轻量 CI 中运行的 Native 语法变异检查，不是 libFuzzer/AFL 的覆盖引导 fuzz，也不保证穷尽状态空间。每次固定 seed=20261105 与 CI run_number 各 192 个案例；脚本总超时 30 秒，单次最多 10000 个案例。手工可选择种子和样本量。

```powershell
.\scripts\moon.ps1 build tests/security_fuzz --target native
.\scripts\moon.ps1 run scripts/security-fuzz.mbtx -- _build/native/debug/build/tests/security_fuzz/security_fuzz.exe 20261105 192
```

语法种子覆盖 PTR、SRV 极值、TXT 的 flag/empty/重复键/255 字节条目、A、AAAA 和最大 UInt32 TTL。变异涉及随机字节、header 数量/ID/flags、名称指针自环和尾部截断。每个案例都把正常 fixture 先写入独立 Engine，再处理变异包：拒绝时验证缓存/快照原子性并重送正常包；任意路径检查容量并关闭。Replay 另检查重复键、非法时间、非法 hex 后的可恢复性；累计预算的边界见 `src/replay/limits_test.mbt`，永久畸形名称/RDATA 回归见 `src/wire/adversarial_test.mbt`。

子进程在每个案例前输出 seed/case 和 wire 的 packet_hex 或状态目标的 action/slot/time；runner 保存为 `.tools/security-fuzz-<target>-last-case.json`。stdout 缓冲未送达时，该文件可能早于失败点，应以相同源码/seed/cases/target 重放整个运行。启动前覆盖旧成功摘要为 passed=false，正常摘要为 `security-fuzz-<target>-report.json`。CI 上传这些文件；失败后把最小复现加入对应 `_test.mbt`。Replay 断言由 seed/case 复现，packet_hex 本身不代表 Replay 输入。

两个 CI 种子使用相同输出文件，artifact 保存最后一组；固定组结果还保存在步骤日志。没有发现新失败样本时，不应编造漏洞或宣称完成安全审计。运行时钟和进程内存预算由宿主另行设置。

2026-11-06 增加独立 `wire`、`cache`、`engine` 三个目标；runner 最后可传目标名称，每组 192 例，最多 10000。Cache 在同一缓存上持续组合 scope、TTL=0/最大 TTL、flush、时间推进、容量和坏记录；Engine 持续组合订阅、跨包更新、取消、关闭/重建、队列压力与版本快照，不再只为每包创建新状态。

`scripts/minimize-fuzz.mbtx <可信 oracle 程序> <输入 hex> <全新输出 hex>` 按字节块删除样本，只保留相同非零退出签名，要求初始两次一致、最终复核，最多约 128 次尝试/15 秒。oracle 接口为 `--oracle <hex文件>`，Wire fuzzer 可作该 oracle；格式拒绝是正常行为，不是失败。工具不覆盖既有输出。`minimizer-smoke` 使用特制 BUG 哨兵检查算法，未声称发现漏洞。状态失败按 seed/动作序列先人工缩减，不声称 wire 最小化器能自动缩减任意状态序列。

CI 还只对选定安全回归做覆盖率观察，报告在 `security-coverage.txt`，不是全库覆盖率承诺，也没有用反馈自动搜索新路径。完整覆盖引导 fuzz 仍未提供。
