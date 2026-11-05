# 安全、边界与协议建议落实记录

日期：2026-11-05。依据顾问对 0.2.0 的最近一次专项建议处理；已发布 0.2.0 标签/归档不修改。新增实现位于 main 的 0.2.1-dev，尚未发布到 Mooncakes。

## 已落实

| 建议 | 本轮结果 | 验证或契约 |
| --- | --- | --- |
| 威胁模型与连接责任 | 增加不可信设备/记录/文件模型；TXT token 不认证；HTTP 示例仅连接显式选择的本机地址 | [安全模型](security-model.md)，examples/http_connect/main.mbt |
| 来源范围与元数据 | IngressPolicy、CIDR 白名单、可选严格 TTL、Datagram.ip_ttl 和录制元数据；先策略后缓存/录制 | 两平台 Native 策略用例；[Linux 原始结果](evidence/linux-ingress-20261105.json) |
| Scope 定义 | 地址、索引、运行原点与独立 nonce；不按固定 seed/同毫秒复用 | Linux 双 Browser 不同 scope；[行为契约](behavior-contract.md) |
| 恶意输入持续检查 | CI 每次执行固定与变化种子的有界 Native fuzz，保存最后案例与成功摘要 | [运行与复现](../tests/security_fuzz/README.md)，[CI 摘要](evidence/security-fuzz-20261105.json) |
| Replay 总量限制 | 库累计帧、UTF-8 输入、解码包、事件/输出字节预算；超限终止并清理；hex 解码前限制 | src/replay/limits_test.mbt；首行解析限制；CLI 有界文件读取 |
| 脱敏分享 | redact 输出白名单事件摘要；删除私有字段；格式错误和命令错误均不回显输入 | redact_test.mbt，scripts/cli-smoke.mbtx；不可回放、无匿名保证 |
| 组合资源退化 | 同时用满缓存/服务/查询/事件队列；保留已有有效服务、拒绝半更新、真实空位后恢复 | resource_pressure_test.mbt |
| 事件、Scope、错误、层间责任 | 建立状态转换和资源退化表，明确部分→部分 Updated、恢复再 Resolved、重叠取消无必然 Removed | [行为契约](behavior-contract.md)、[解析契约](dnssd-resolution-contract.md) |
| RFC 条款追踪 | 按规范章节连接实现与测试；明确有限接纳和有意简化，修正 RFC 8553 的含义 | [RFC 对照](rfc-conformance.md)、[协议矩阵](protocol-matrix.md) |
| 版本和支持状态 | 统一 Supported/Partial/Unsupported/Untested；修正 SRV 跨包和已发布版本的过期说明 | [SCOPE](SCOPE.md)、README、CHANGELOG |

## 已执行的轻量验证

- 核心 JS smoke **58 项通过**；Native 来源策略 **2 项通过**。只运行相关核心/过滤用例，不全量跑所有后端。
- Native 类型检查、接口生成和格式检查通过；API 扩展仅在 Native 策略/Datagram 和 Replay.new/脱敏函数中按预期出现。
- 实际 Windows CLI 的双次回放、端点/候选/到期事件、历史记录投影、种子恢复、非法参数、help/version、脱敏字段和错误不回显原文通过。对应脚本也进入双平台轻量 CI。
- 本机 seed=20261105 的 **192 个变异案例通过**，118 个报文被拒绝；CI 固定与变化种子各 192 个案例通过。CI artifact 的 seed=42 组拒绝 133 个报文。拒绝数量不是漏洞数量。
- 干净源码 `84f63fe2733a7a254f14491113d3e2cba4c3782d` 的[双平台轻量 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/42046563635)与 [Linux 实网专项](https://github.com/mik1e80/MoonDiscover/actions/runs/42046563972)均成功。Linux 实际接收 TTL=255、允许来源入缓存/录制、拒绝来源不进入、独立 scope 均通过；原 Avahi、Known-Answer/子类型和隔离接口恢复继续通过。

原始报告从工作流 artifact 原样提取；ZIP 散列、artifact ID、源码和二进制绑定见[证据清单](evidence/security-20261105-manifest.json)。最新 CLI 脚本补充了原有历史事件投影和两类脱敏错误检查；fuzz runner 增加启动前 passed=false 标记，本机故意使用不存在的二进制验证失败不会残留旧成功，随后正常 192 例再次通过。这些脚本更新不改协议实现。不得将历史 0.2.0 或旧源提交的结果当成整个 main 全平台审计。

## 保留的限制

Windows 本轮未收到本机发出的组播回环；原有 UDP 探针也复现，不归因于已证实的 TTL 缺陷，也不宣称 Windows TTL 实收已通过。Windows Native 编译和策略边界用例通过，实际元数据仍标 Untested。

无第二物理设备；Bonjour、长期实网压力、全部独立 responder 的 Known-Answer 等待/抑制行为仍未验证。此前十分钟核心循环继续作为核心资源观察，不替代 socket/实网长时间证据。覆盖引导 fuzz、硬 CPU/RSS 隔离和独立渗透测试尚未提供。IPv6 组播、发布者、NSEC、跨子网与自动迁移保持 Unsupported，不以本轮文档/测试暗示新增支持。

RFC 6762 §11 的默认组播接纳不要求强制同子网/TTL=255；可选严格策略是应用选择。仍不能防同链路身份伪造或保证广告端点安全。录制与脱敏的确定性、校验和及通过的测试均不构成来源真实性或安全认证。
