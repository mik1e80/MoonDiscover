# 后续开发路线

更新：2026-11-01。依据用户指定顾问对话中的检查建议；本项目尚未报名，用户计划报名 11 月赛。按阶段逐项验收，不把路线表当作已完成的功能声明。继续采用与变化相关的轻量测试，0.1.0 标签与归档保持原样。

| 阶段 | 交付与验收 | 当前状态 |
| --- | --- | --- |
| 1 Known-Answer 边界 | 数量/包数/字节限制一致，超限保留合法 QM，明确诊断，边界回归与 CI | 已完成；9 项相关本地检查及代码提交的两项 CI 成功，见下方记录 |
| 2 输入与状态机 | 畸形指针/截断、重复和分批乱序、TXT/SRV 顺序、goodbye 救回/同时到期、多类容量同时受压、取消、共享主机地址；检查状态/事件/待发报文/计数 | 已新增针对性回归；仍需持续按缺陷补样本，不宣称随机模糊测试覆盖 |
| 3 专项互操作 | 独立解析器检查多包 TC/问题/答案；独立发布者验证子类型过滤/身份去重；实际待发分包取消 | Engine 实际出站字节已由独立测试解析器验收；专项 UDP/独立发布者互通仍待完成，第二设备暂无 |
| 4 SRV 解析 | 明确优先级、权重、零权重及候选信息契约，处理多记录/缺失/异常路径 | 已实现并有文档与确定性核心测试；跨响应批次 RRSet 重组及独立互操作仍未验收 |
| 5 Native IPv4 可靠性 | 接口失效与地址变化、多 socket 开关、收发错误/截断/取消语义、poll/run/close 契约与资源释放 | 关闭、取消和稳定错误分类已有实现及定向检查；接口失效/恢复仍未实测 |
| 6 性能与资源 | 同工具链与输入，多轮测量首次解析/重复/更新/到期，中位数和波动、峰值资源，并检查结果正确性 | 50/200/500 个合成服务已各测三轮；更大规模与长时间压力仍待后续 |
| 7 稳定 0.2.0 | 前述关键验收、API/文档一致、固定标签/归档、Mooncakes 与无源码映射的独立消费证据 | 未发布，main 保持 0.2.0-dev |

第二设备目前不可用，跨设备证据继续待验证。本机组播探针未捕获到自己发出的组播副本，因此不把失败实验记作专项实网互操作成功。IPv6、NSEC、发布者、接口自动切换保留后续版本，不插入当前阶段。

## 出站报文独立解析检查

`tests/protocol_probe/independent_parser_test.mbt` 直接读取 Engine 的实际待发 `Bytes`，使用不调用生产 `wire.decode` 的小型解析器检查 260 条 PTR Known-Answer 的顺序、TC 链、首包问题、后续答案、取消后无残留分包，以及超大 TXT Known-Answer 退化为普通 QM 并产生诊断。该检查在 JS 后端通过；它验证编码后的报文字节，不代表 UDP 传输或独立实现间的实网互操作。

## Known-Answer 阶段实现记录

- `e36fe07`：`query_packets` 先校验包预算，再使用 `max_packets * 256 - 1` 的记录数量上限。首包 255、后续 256，默认 16383；每包字节上限可能提前耗尽容量，错误不返回部分 burst。
- `5eea5a9`：Known-Answer 编码失败后验证普通 QM，合法则发送并输出 `known_answer_limit`；问题无效则输出 `query_invalid`，继续处理后续问题。后续轮次可以恢复携带正常 Known Answers。
- `82a5297`：回放在每次 poll 后和退出发送循环时排空事件，诊断随当前帧返回，最后一帧也不会漏掉。

新增复现中，旧实现有三项失败：包预算边界诊断不明确、超大 TXT 导致合法问题丢失、回放当前帧没有编码诊断。修复后相关 9 项 JS 用例通过，覆盖 255/256、511/512、16383/16384 条边界、字节限制、TC 链完整性、单条过大、取消、降级后继续发送和恢复、无效问题与当帧诊断。

回放回归使用一个可合法接收的、少于 9000 字节的 TXT 响应；同一答案加上查询的问题部分就超过出站包限制，因此证明普通 wire 输入也能触发降级。另一个 Engine 用例直接注入超过 UDP 包长的公开 DTO，仅用于验证核心防御路径。

```powershell
.\scripts\moon.ps1 test src/wire/known_answer_limits_test.mbt src/wire/multipacket_test.mbt src/engine/known_answer_fallback_test.mbt src/engine/multipacket_test.mbt src/engine/query_invalid_wbtest.mbt src/replay/replay_test.mbt --target js --frozen --filter 'smoke:*'
.\scripts\moon.ps1 build cmd/moondiscover --target native --frozen
.\.venv\Scripts\python.exe tests/interop/cli_smoke.py
.\scripts\moon.ps1 info --frozen
.\scripts\moon.ps1 fmt
```

Native CLI 编译及 6 项离线 CLI 检查通过，包括已录制实网事件语义与回放一致。生成 `.mbti` 没有公开接口变化。本轮未运行所有后端全量测试。

代码提交 `82a529723a123f0f734d7ec1a2f1b7c08d2ec5be` 的 GitHub 验收：

- [轻量检查 40654335009](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654335009) 成功：45 项 JS `smoke:*`、Windows/Linux Native 编译、6 项离线 CLI 检查、本地工作区独立消费、浏览器回调与三项语义故障注入。此处消费的是开发源码，不是新版本的注册表发布验证。
- [Linux Avahi 40654334969](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654334969) 成功，日志中的 8 项真实组播闭环检查均为 true。它确认已有路径没有回归，不替代第三阶段多包/子类型专项证据或第二设备证据。
