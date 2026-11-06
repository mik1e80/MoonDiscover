# 已发布版本与 main 支持状态

状态日期：2026-11-06。`0.1.0` 对应 `v0.1.0` / `2b922d6`；`0.2.0` 对应 `v0.2.0` / `aaf6ced`，均已发布至 Mooncakes。main 为 **0.2.1-dev（未发布）**，包含后续来源/TTL、预算、恢复和协议修复。下面旧版对照表描述已发布 0.2.0 的基础；main 的新增项另列，不回填发布归档。[0.2.0 发布证据](release-0.2.0.md)。

| 能力 | 已发布 0.1.0 | 已发布 0.2.0 |
| --- | --- | --- |
| Known-Answer | 有界单包 | 最多 64 包的 TC 连续序列，核心用例验证 |
| 服务子类型 | 不支持 | `_sub` PTR 选择性浏览，核心用例验证 |
| 状态与性能 | 原始接口 | 新增 Engine.stats() 与不可变名称键缓存 |
| 容量/PTR 防御 | 未包含本轮修复 | 保留有效旧服务、归一化异常 PTR flush 位 |
| SRV 候选选择 | 基础解析 | 跨响应包汇集未过期 RRSet，按 priority 与 seed 派生权重顺序公开候选 |
| Native 生命周期错误 | 基础关闭行为 | 关闭幂等、失败路径释放与稳定诊断分类 |
| Linux 实网 | 发布时仅编译证据 | Avahi 0.8 同 VM 八项闭环通过；非第二设备 |

| 层 | 当前实现 | 证据与边界 |
| --- | --- | --- |
| 模型与 wire | 原始标签字节、可逆名称文本、二进制 TXT、PTR/SRV/TXT/A/AAAA、未知 RR 有界跳过、QM 编码 | JS 轻量用例与独立 zeroconf 报文；不是完整 DNS codec |
| 缓存 | 范围隔离、重复刷新、TTL、goodbye、cache-flush 宽限、容量失败原子性 | 注入时间的确定性用例；不解释 NSEC |
| 聚合与事件 | PTR→SRV 候选/TXT/地址；部分/完整快照；生命周期事件 | SRV 按优先级及确定性加权顺序提供候选；TXT 冲突仍保守处理 |
| 查询与解析 | QM 抖动与退避、依赖查询、TTL 刷新、有界多包 Known-Answer、子类型；指定实例解析、超时、取消 | 已有 Linux 实际 UDP+独立解析器、Avahi 子类型专项；不是所有 responder 抑制/等待行为的证明 |
| 核心后端 | 系统无关的 Engine 与 Replay | JS 冒烟通过；部分引擎用例在 Wasm/Native 通过，未全量运行所有后端 |
| Windows 实时网络 | 指定活动 IPv4 接口、5353 共享绑定、入站接口/目标地址元数据、异步轮询与取消释放 | 同机独立 python-zeroconf 进程实网闭环；无第二设备证据 |
| Linux Native | 条件编译的 IPv4 socket 适配 | [Avahi 报告](evidence/linux-avahi-20261028.json)对应 a8703be：实际发现、HTTP、更新、goodbye、取消、回放通过 |
| CLI 与示例 | browse、resolve、doctor、replay、JSONL 录制；事件、HTTP 和浏览器离线回放示例 | 实际二进制离线冒烟、Node 回调与真实浏览器检查、Windows 实网实验 |
| 发布 | 固定工具链、GitHub 轻量 CI、API 文档、样本与来源、Mooncakes 0.1.0 / 0.2.0 | 0.2.0 无源码映射独立安装、核心/新 API、Native 编译和 socket 开关均通过；下载归档散列匹配 |

## main 的统一能力状态

Supported = 所列子项已实现且有对应验证；Partial = 有限行为或条件；Unsupported = 未实现；Untested = 缺少所列环境证据。状态不会扩大到整份协议或全部平台。

| 能力 | 状态 | 约束 |
| --- | --- | --- |
| IPv4 QM 组播与 A/AAAA 解码 | Supported | Windows/Linux 的已有报告；AAAA 解码不表示 IPv6 传输 |
| SRV 跨包 RRSet 与加权候选 | Supported | 确定性核心回归；应用负责连接和重试 |
| 多包 Known-Answer | Partial | 编码、核心、独立解析器、实际 UDP 已测；所有 responder 抑制/等待场景 Untested |
| 子类型过滤与身份共享 | Supported | 核心与 Avahi 同 VM 专项 |
| TXT 多记录策略 | Partial | 最新批次有不同 TXT 时保持未完成；不声称全面冲突解决 |
| 来源 CIDR 策略、TTL 严格接纳 | Supported | main 新增；两平台策略用例+Linux 实际 TTL/缓存/录制验证 |
| Windows/Linux 实际 TTL 元数据 | Supported（单播回环） | 生产接收函数实际收到 255/254/1；不替代 Windows mDNS 组播严格策略与第二设备验证 |
| 接口失效后手动关闭/重建 | Supported | Linux 隔离网络命名空间验证；无自动迁移或同地址换网识别 |
| 三目标变异、组合容量与 Replay 总量/进程预算 | Supported（所列测试范围） | Wire/Cache/Engine、有界最小化、有限覆盖率观察、独立进程限制；非覆盖引导 fuzz 或安全审计 |
| 高频输入、压力查询轮换与版本化视图 | Supported（稳定集合） | 实时全局/来源/核心令牌桶；每秒轮换容量窗口；异步旧事件按 epoch/sequence 丢弃。任意持续变化无无条件公平延迟保证 |
| 第二物理设备、Bonjour、长时间实网压力 | Untested | 不用同机/同 VM/核心资源循环替代 |
| IPv6 组播、发布者、NSEC、跨子网反射 | Unsupported | 无相关实现声明 |

安全、Scope/事件/退化规则、解析和 RFC 追踪分别见[安全模型](security-model.md)、[行为契约](behavior-contract.md)、[解析契约](dnssd-resolution-contract.md)、[RFC 对照](rfc-conformance.md)。

## 传输范围

Native Browser 仅接纳源端口 5353、目标组播地址 `224.0.0.251`、所选入站接口的响应。单播不在当前适配层范围。发送使用组播 TTL 255；main 通过 Datagram.ip_ttl 和录制暴露可选接收 TTL，0.2.0 没有该字段。默认不按来源子网或接收 TTL 非 255 一概拒绝，符合 RFC 6762 §11 对组播目标和叠加子网的处理。应用可配置最多 64 个 CIDR 来源范围和 require_ip_ttl_255；严格模式对缺失 TTL 也拒绝。来源策略只筛选发送者，不认证身份或约束广告端点。

2026-11-01 Linux 专项已验证实际多包 UDP、独立测试解析器、Avahi 子类型过滤/共享身份，以及隔离网卡地址删除后的关闭/重建恢复。具体方法和局限见[专题验证](specialized-interop.md)；不将其扩展为第二物理设备、全部 Known-Answer 响应抑制或自动迁移证明。

接口地址或索引失效时报告错误；不自动迁移到其他接口。底层提供有界同步 poll，异步 `run` 以短周期协作轮询并在取消时释放资源，尚未接入原生异步 fd 事件源。

2026-11-06 新增限速、端点筛选、来源观察、版本化事件和网络变化主动通知；状态与证据见[第四轮记录](security-review-20261106.md)。来源观察不是认证历史，端点候选不是连通性证明。1h/6h 观测入口已提供，本轮仅跑 2 秒双 Browser 冒烟，不宣称完成小时级实网验收。

## 数据与资源边界

- 名称标签为 1..63 字节；mDNS 完整 wire 名称最多 256 字节（含根终止字节）。
- 单报文最多 9000 字节，问题和 RR 合计最多 256，单名称解码最多 256 步。Known-Answer 一组最多 64 包、16383 条答案；自定义包预算的数量上限为 `max_packets * 256 - 1`，字节上限可能先到达。调用方须连续取尽发送；改变输入/时间或取消会中止未发完序列。
- wire 编码器超限会返回错误，不返回截断序列。Engine 对合法问题退化为无 Known Answers 的普通 QM，输出 `known_answer_limit`；问题无效输出 `query_invalid` 并继续处理后续问题。Replay 在当前帧输出诊断。
- 默认缓存 2048 条、服务 512 个、事件 256 个、查询任务 256 个、订阅最多 64 个；部分容量可在 Engine 构造时调整。
- 多个 SRV 候选按 priority 与固定 seed 派生的权重顺序提供；跨响应包汇集同范围未过期记录，替换/救回遵循缓存宽限。TXT 冲突仍标为未完成。完整规则见 [SRV 选择契约](srv-selection.md)。
- CLI 录制文件上限 8 MiB/10000 帧，录制队列溢出时拒绝保存不完整 trace。main Replay 库本身累计限 10000 帧、8 MiB 输入、4 MiB 报文字节、65536 条/8 MiB 输出，单行 32768 个 UTF-16 代码单元；可降低预算。预算耗尽关闭该 Replay。脱敏命令输出有限事件摘要，不能当作原始 trace 回放。

## 暂未实现或未验证

未实现发布者、自动重命名、IPv6 组播、跨子网/反射器、后台守护进程、自动枚举所有类型、NSEC 负缓存、接口自动切换。没有 Bonjour、第二设备或长时间实网运行证据。

当前 DNS-SD 缓存把 PTR 当作共享成员关系处理并忽略其 flush 位；不提供反向 PTR 唯一 RRSet 的刷新语义。多包 Known-Answer 不解决同一主机上多个独立 mDNS 实现之间的协调问题；一般 Avahi 闭环也不证明该扩展的完整互操作性。

解码 AAAA 不代表支持 IPv6 传输。未见响应只表示观察窗口内未发现；TTL 到期只表示已有缓存证据失效，不证明设备离线。原始计划中的完整平台/RFC 验收不能据此标为全部完成。
