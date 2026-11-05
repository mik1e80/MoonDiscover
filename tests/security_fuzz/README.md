# 有界恶意输入 fuzz

这是一项在每次轻量 CI 中运行的 Native 语法变异检查，不是 libFuzzer/AFL 的覆盖引导 fuzz，也不保证穷尽状态空间。每次固定 seed=20261105 与 CI run_number 各 192 个案例；脚本总超时 30 秒，单次最多 10000 个案例。手工可选择种子和样本量。

```powershell
.\scripts\moon.ps1 build tests/security_fuzz --target native
.\scripts\moon.ps1 run scripts/security-fuzz.mbtx -- _build/native/debug/build/tests/security_fuzz/security_fuzz.exe 20261105 192
```

语法种子覆盖 PTR、SRV 极值、TXT 的 flag/empty/重复键/255 字节条目、A、AAAA 和最大 UInt32 TTL。变异涉及随机字节、header 数量/ID/flags、名称指针自环和尾部截断。每个案例都把正常 fixture 先写入独立 Engine，再处理变异包：拒绝时验证缓存/快照原子性并重送正常包；任意路径检查容量并关闭。Replay 另检查重复键、非法时间、非法 hex 后的可恢复性；累计预算的边界见 `src/replay/limits_test.mbt`，永久畸形名称/RDATA 回归见 `src/wire/adversarial_test.mbt`。

子进程在每个案例前输出完整 packet_hex、seed 和 case；runner 将最后收到的案例保存为 `.tools/security-fuzz-last-case.json`。若崩溃前 stdout 缓冲尚未送达，该文件可能早于实际失败点，应以相同源码/seed/cases 重放整个运行。启动前还会保存 seed/cases，并覆盖旧成功摘要为 passed=false，避免第二组中断后误读第一组成功。正常完成的摘要位于 `.tools/security-fuzz-report.json`。CI 上传这些文件；失败后把定位的最小样本加入对应 `_test.mbt`。如果失败在 Replay 断言，seed/case 复现该次命令选择；packet_hex 本身不代表 Replay 输入。

两个 CI 种子使用相同输出文件，artifact 保存最后一组；固定组结果还保存在步骤日志。没有发现新失败样本时，不应编造漏洞或宣称完成安全审计。运行时钟和进程内存预算由宿主另行设置。
