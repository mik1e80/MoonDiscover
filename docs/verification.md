# 当前验证证据

`0.2.0` 已实际发布；[发布记录](evidence/release-0.2.0-20261101.json)关联 `v0.2.0` / `aaf6ced`、两项成功 CI、服务器 200、注册表独立消费、六项新增 API、Native 开关及 187 个安装文件/归档核对。

2026-11-01 新增[实际十分钟资源循环](evidence/resource-soak-20261101.json)：19,298 轮服务解析、重复输入、TXT 更新、队列溢出后快照同步、TTL 与关闭清理均满足断言；进程 RSS 增加约 0.30 MiB，句柄始终为 122。工作负载和局限见[性能说明](performance.md)。

状态日期：2026-11-01。已发布 0.1.0 与 main（0.2.0）分别记录。验证按改动运行轻量用例与受控短时实验，不在每步全量运行所有后端。

提交 `5f246ea` 的轻量 CI 通过 54 项核心 JS 检查与 1 项独立解析器检查、Native 构建、两秒资源冒烟、消费与离线 CLI 检查。独立 Linux 工作流另已通过实际多包 UDP、取消/降级、Avahi 子类型/身份及隔离接口恢复；[专题说明](specialized-interop.md)关联原始报告与 CI。此前本机 Windows 组播探针没有收到自身副本，这次没有将其改记为成功；第二物理设备仍待后续环境可用时验证。

```powershell
.\scripts\moon.ps1 test tests/protocol_probe --target js --frozen --filter 'smoke:*'
```

## 纯核心与实际 CLI

截至录制实现 `f2baff7`，JS 有 29 个 `smoke:*` 用例：根 API 1、模型 5、wire 5、缓存 4、引擎/查询/resolve 11、回放 3。覆盖乱序、重复、范围隔离、goodbye/flush 宽限、到期、队列溢出、抖动/退避、剩余 TTL Known-Answer、resolve 超时、同毫秒更新和回放种子。部分引擎用例另外在 Wasm、Native 运行通过；没有全量运行所有后端。

`tests/interop/cli_smoke.py` 对实际 Windows CLI 二进制离线验证相同输入的两次回放、fixture 端口解析、TTL 到期的 unavailable/removed、移除后的 TTL=0/complete=false、非法参数退出、help/version 和完整 UInt32 种子恢复。构建通过不等于实网通过。

后续另补三项定向回归，验证同一 tick 中不同服务的移除原因和范围隔离；同时失效的 goodbye 与自然 TTL 到期不会互相覆盖。公开实网 fixture 的两次回放及完整服务事件对照也已纳入离线 CLI 冒烟。

提交前执行 `moon info` 和 `moon fmt`，检查公开 `.mbti`；复现命令见 [开发文档](development.md)。原始 zeroconf 报文来源见 [fixtures](../fixtures/README.md)。

浏览器示例的编译回调另有 Node 轻量检查，真实录制的六个服务事件与公开报告逐项一致。真实浏览器还检查了内置查询示例和实际报文产生的 seen/resolved/unavailable/removed 列表；页面仅展示待发查询，不把它们发往网络。

## Windows 实网闭环

公开报告：[windows-live-20261024.json](evidence/windows-live-20261024.json)。源提交为 `f2baff7786e6199bfae105a2f81de62313b30672`，实验开始时工作树干净。环境为 Windows 11、Python 3.12.14、python-zeroconf 0.148.0；发布者是同一台机器上的独立 Python 进程。

8 项检查全部通过：

1. MoonBit 主动发现独立实现发布的合成服务。
2. HTTP 示例使用发现的动态端口请求 `/moondiscover-demo` 并验证返回 token。
3. CLI 实时输出 TXT 属性更新事件。
4. 观察 goodbye 后服务移除。
5. browse、HTTP、doctor、cancel 进程均成功退出。
6. 异步取消关闭 Browser，随后可重开 socket。
7. 录制文件两次离线回放产生相同结果。
8. 回放的该服务事件序列与实网观察一致（比较时只移除观测时间字段）。

导出的 [live-20261024.jsonl](../fixtures/live-20261024.jsonl) 经过合成服务名称白名单检查，保留配置、时钟和命令帧。该次录制只有本项目合成服务的报文，实际排除数为 0；导出样本与原 trace 的 SHA256 相同，均在报告中记录。分享其他录制仍须逐次检查。报告中的 TTL/端口/IP 是该次实验观测值。

最初的 [M0 传输报告](transport-spike.md) 保留了单播未收到、整体退出码 1 的历史结果。当前 Browser 明确限定 IPv4 QM 组播，后续闭环成功不将该历史失败改成通过。

另有约两秒的[超长报文回归](evidence/windows-oversized-20261024.json)：发送 9001/16000 字节组播后，浏览器继续解析随后的自建合法响应并正常完成观察窗口。报告记录修复尚未提交时的工作树状态与二进制 SHA256，代码已保存为 `7b9ad71`。此测试验证传输鲁棒性，独立实现互通仍以前述 zeroconf 实验为证据。

## GitHub CI

[轻量工作流](../.github/workflows/ci.yml) 在 Linux 运行核心 JS 冒烟并编译 Native 入口；Windows 编译入口并运行离线 CLI 冒烟。该默认流程不依赖组播。另有下节单独的受控 Linux 实网工作流，不将一般构建成功当成实网通过。

发布源码 `2b922d6` 的 [40077915645](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40077915645) 两项检查成功，涵盖新增移除原因回归、仓库外公开 API 消费和浏览器回放回调。该链接证明对应发布源码的检查成功；后续文档更新以各自 Actions 记录为准。

## main 的 Linux/Avahi 实网

[成功任务 40645501957](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40645501957)对应干净提交 `a8703bec8acfa70ab2804e8b5859ee4f6eaacb93`，完整报告保存于 [linux-avahi-20261028.json](evidence/linux-avahi-20261028.json)。环境为 GitHub Ubuntu VM、Avahi 0.8，绑定活动 eth0 的 IPv4，与独立守护进程通过真实 UDP 组播互通。

八项均通过：独立发布解析、使用动态端口完成 HTTP、TXT 更新、goodbye、受控进程退出、取消关闭、重复回放一致、实网与回放服务事件一致。浏览器退出 0、stderr 空、stdout 未截断、读线程无错误；录制实际存在，110118 字节，其散列随报告保存。IPv6 地址出现在解码结果中不代表 IPv6 传输或连接经过验证。

此前 [40110599383](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40110599383) 的失败仍保留。脚本修复创建录制目录，并在读取 trace 前保存进程结果；缺文件将带明确诊断失败。工作流现在随核心、CLI、示例、工具链和相关配置变化自动运行，默认不进行跨设备或长时间实验。

## 本轮针对性回归

容量与 PTR 问题在旧实现上由三个新用例复现为失败，修复后相关 12 个 JS 轻量用例通过；公开接口未变。另四项 wire/engine 测试检查多包 TC 链、问题位置、300 个答案完整性、实际仍有待发分包时取消、子类型排除非成员及共享身份。一般实网报告不会自动升级这些扩展的专项网络验证状态。

2026-11-01 另对 50/200/500 个合成服务各重复三轮，在干净提交 `8a7f1ab` 和同一 Native release 二进制上记录中位数、范围、采样 RSS 及缓存/事件计数。完整数据见 [三轮报告](evidence/performance-multiround-20261101.json) 和 [分析说明](performance.md)。这仍是单机观察，不代表更大规模、wire 解码、跨平台或长时间实网压力证明。此前故障注入另见 [单次报告](performance.md)；审查处理与验证入口见 [修复记录](review-fixes-20261028.md)。

Known-Answer 第一阶段回归：默认 16383 条可完整编码，16384 条及自定义包预算的越界明确拒绝；单条答案过大时仍发送合法 QM，后续查询和恢复路径正常；无效问题单独诊断，Replay 在当前帧输出诊断。相关 9 项 JS 检查、Native CLI 编译和 6 项离线 CLI 检查通过，API 未变。

代码提交 `82a5297` 的[轻量检查](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654335009)45 项 JS smoke 全部通过，其他轻量步骤成功；[Avahi 闭环](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654334969)8 项通过。具体用例和复现命令见[阶段记录](development-roadmap.md)。

## 结论的范围

Windows 为同机独立进程，Linux 为同 VM 独立 Avahi 守护进程；均没有第二设备证据。没有完整 RFC 审计、所有后端全量测试或长时间实网压力验证。main 的新功能与修复不属于已发布 0.1.0，0.2.0 注册表发布与消费的执行状态见 release-0.2.0.md。

## Mooncakes 与独立消费

`mik1e80/dnssd@0.1.0` 发布命令返回 `200 OK`，源码为干净提交 `2b922d6ac0db5c6261aea917545776dfc488b1ec`，GitHub 标签为 `v0.1.0`。[发布记录](evidence/release-0.1.0-20261024.json)保存工具链、归档散列、文件数和对应 CI。

[注册表消费报告](evidence/consumer-registry-20261024.json)来自新建的仓库外工程，无 `moon.work` 覆盖，依赖固定版本 0.1.0。它从官方注册表下载后，JS 核心 API、Native 编译和实际 socket 打开/关闭三项均通过。下载 ZIP 的 SHA256 为 `817c7abe72ca359cfac067e751db30a4f17c4fef8c76fa02b77dcd31f668a71b`，与发布归档相同，安装的 116 个文件逐一匹配。

复现：`python tests/interop/consumer_smoke.py --mode registry --version 0.1.0 --interface <活动IPv4> --output .tools/consumer-registry.json`。索引过旧时先运行 `moon update`。本地 source 模式与注册表模式仍分别记录，前者不代替后者。

标签与发布归档固定在发布源码提交；本页及发布完成后才产生的消费证据位于其后的文档提交中，不改写已发布版本。
