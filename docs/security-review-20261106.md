# 第四轮安全、稳定性、准确性与边界建议落实

日期：2026-11-06。对应顾问最近一次检查；main 仍为 **0.2.1-dev，未发布**。已发布 0.2.0 标签和包不修改。这里区分实际新增行为、已验证范围与依赖外部环境的待办。

## 已落实的主要建议

| 建议 | 实现和契约 | 证据入口 |
| --- | --- | --- |
| 高频合法包的 CPU 工作量保护 | Native 全局/来源令牌桶、Engine 解码前预算；单来源桶有容量，静默限流并分类计数 | model/budget_test、engine/rate_test、native/rate_wbtest；Linux 实际 UDP；[资源保护](resource-protection.md) |
| 来源不等于端点许可 | 记录链 observations 有界保留来源；endpoints 显式应用地址/端口策略，默认仅 IPv4；HTTP 示例使用该筛选 | endpoint_test；[安全模型](security-model.md) |
| Section 语义和缓存污染 | 三个响应 RR 区域都是可能的断言；按名称/类型/内容去重；不相关缓存不变成订阅服务，坏支持记录整包拒绝 | cache/section_test、engine/section_test；[RFC 对照](rfc-conformance.md) |
| RFC 接收字段准确性 | 修复 ID=0/TC=0 的额外限制；接收忽略 ID/AA/TC 等，opcode/rcode 异常仍忽略；DTO header 有 wire 字段边界 | cache/section_test；RFC 6762 §18.1/18.4/18.5 |
| 查询长期饥饿 | 每秒轮换容量窗口，稳定集合能轮到；deadline 暴露轮换，deferred_queries 可观察 | fairness_test；持续任意 churn 不承诺无条件公平延迟 |
| 异步消费旧事件 | EventEnvelope 带 epoch/sequence；StateView 带同一快照水位；旧代次和已覆盖事件应丢弃 | view_test；Browser.poll_batch；[行为契约](behavior-contract.md) |
| 单驱动与同地址换网 | run 期间检测 DriverBusy；第二个 run 不误关第一个；notify_network_changed 关闭旧代次，宿主重开/恢复订阅 | native_cancel、隔离接口恢复；不增加线程锁或自动迁移 |
| 异常释放 | 六个初始化和两个 I/O 错误拦截，句柄平衡、peer 不受影响、重开成功；回调/取消释放；时钟错误分类与关闭保底 | native_fault、native_cancel、clock_wbtest；[稳定性观测](stability-observations.md) |
| Fuzz 深度和定位 | Wire/Cache/Engine 三目标、有界失败样本最小化、固定/变化种子、选定回归覆盖率报告 | security_fuzz、minimize-fuzz、minimizer-smoke；不是覆盖引导 fuzz |
| TXT、SRV、地址准确性 | TXT 跨包/冲突/宽限/救回与 SRV 同窗更新；4096 seed 加权票据宽容分布与排列完整性；AAAA-only 与 IPv4 候选区分 | txt_contract_test、srv_distribution_wbtest、endpoint_test |
| Replay 进程资源保护 | 独立进程墙钟、CPU、内存预算，强制回收；离线回放不误套实时包限速；中文/空格路径回归 | guard-smoke；[回放隔离说明](replay-isolation.md) |
| 平台 TTL 与短期资源证据 | 两平台生产接收函数实际单播回环 TTL=255/254/1；双 Browser 两秒观测；Linux mDNS 流量/来源限流与录制溢出后继续浏览 | native_ttl、live_soak、protocol_live/ingress |

## 轻量验证

实际运行代码基线 **a824ad0a9490431039a01970e797a4b534fd711d**：

- [双平台轻量 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/42234247044)通过；70 项核心 JS smoke、独立解析器检查、Native 策略/时钟检查、CLI/浏览器回放、独立消费与定向故障注入等既有步骤保持成功。
- [Linux Avahi 实网专项](https://github.com/mik1e80/MoonDiscover/actions/runs/42234246712)通过；保留原发现/HTTP/更新/goodbye/取消/回放/子类型/多包检查，新增实际 UDP 限流、来源限额、录制队列溢出后仍能发现。
- Wire 固定/变化种子各 192 例，Cache 和 Engine 各 192 例。本机另跑 seed=20261106 三目标各 192 例；这是有限样本，不是漏洞数量或全状态穷尽。
- 仅对选定六项安全用例做覆盖率观察；覆盖点分子/分母与构建版本绑定，不是全库 100% 或覆盖引导搜索。样本最小化以人为设计的 BUG 哨兵验证，不宣称发现新的漏洞。
- 该提交选定用例覆盖点为 712/1275，原始时间戳摘要取自 CI 日志；固定工具链 summary 的 -o 未写文件，后续改为 save-coverage.mbtx 显式保存，不将旧 artifact 中不存在的文件描述成已归档。
- 原始 artifact 报告、散列和来源绑定见[证据清单](evidence/security-20261106-manifest.json)。不把 Windows 的单播回环报告当成 mDNS 组播实收证明。

中途 CI 暴露并修复了 Linux 未设置 MOON_HOME 时的脚本路径，以及 Windows 首次 CIM 查询接口过慢；后续没有放松协议/资源断言来通过。当前测试用 UDP 路由查询辅助选择接口，不发送应用报文、不改变网卡配置。

## 边界与待完成验证

身份认证仍由应用执行；来源地址/TTL、observations、endpoints、complete 都不是 Reachable 或 Authenticated。JSON 保持既有输出字段，来源观察扩展暂仅通过快照 API 提供。Unicode 不隐式 IDNA/规范化，二进制名称保留可逆字节而非伪装 UTF-8 发布合规。

未执行 1h/6h 实网观测：只提供可选入口，并按用户要求运行 2 秒冒烟。真实 Wi-Fi 换网、第二物理设备、Bonjour、Windows mDNS 组播严格 TTL、多实现 responder 等待/抑制仍需外部环境。小时级、物理网络稳定性不能由本轮短测推断。

未提供完整覆盖引导 fuzz、状态序列自动最小化、每个 OS 失败模式、真实系统单调时钟破坏、或独立安全审计。Native 故障拦截不等于所有 Browser 随机源/系统初始化失败都逐项注入过。任意持续变化下的查询公平性也无硬时延证明。IPv6 组播、NSEC、服务发布者和自动接口迁移保持不支持。
