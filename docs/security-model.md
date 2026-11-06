# 安全模型

状态日期：2026-11-06。本文约束当前 main / 0.2.1-dev（未发布）；已发布 0.2.0 的归档不随 main 修改。最新证据见[第四轮落实记录](security-review-20261106.md)，其余契约见[支持范围](SCOPE.md)、[行为契约](behavior-contract.md)和 [RFC 对照](rfc-conformance.md)。

## 信任边界

MoonDiscover 发现服务，不认证服务提供者。同一链路上的设备、DNS 名称、SRV 端点、A/AAAA 地址、TXT 属性和第三方录制文件都按不可信输入处理。正确的接口、组播目标和来源端口只说明接收路径符合适配层约定，不证明设备身份。白名单中的来源也可能被伪造。

应用在连接前应执行自己的地址和端口许可策略，并按业务需要使用 TLS 证书校验、设备配对或其他认证。TXT 中的 `trusted=true`、设备名称和示例 demo token 都不是认证凭证。禁止把发现结果直接用于执行命令、拼接路径、HTML 或无约束的代理请求。日志和界面应转义控制字符，并限制展示长度。

| 威胁 | 已有防御与剩余风险 |
| --- | --- |
| 恶意局域网设备伪造服务、地址、TTL、goodbye | 缓存隔离和生命周期规则限制影响范围；不验证记录所有权，不能防止同链路冒充或撤销他人记录 |
| 损坏报文、压缩指针循环、超长 RDATA | 单包 9000 字节、256 个问题/RR、名称 256 步/256 wire 字节；整包校验后原子接纳，不接受查询中的 Known Answers |
| 大量合法响应或重复流量 | Native 全局/来源令牌桶、Engine 解码前预算、容量和每 poll 64 包；不保证网络无丢包或特定 CPU 百分比。Replay 可用独立进程预算，详见[资源保护](resource-protection.md) |
| 伪造 TXT、恶意地址 | TXT 保留二进制；端点仅是候选。来源白名单不约束记录里广告的目标地址，连接策略由调用方执行 |
| 篡改的 Replay 文件 | 严格 JSON、单调时间和总量限制；确定性只证明同一输入的结果，不能证明文件来源或原始网络事实 |
| 队列溢出、接口变化 | 诊断并从快照重建视图；接口失效后关闭并重建 Browser，不沿用旧网络 scope |

## 接收入站报文

Native 默认只接纳所选入站接口、目标 `224.0.0.251`、源 UDP 端口 5353 的响应。Engine 再检查 QR=1、opcode=0、rcode=0，以及受支持的 IN 记录；按 RFC 6762 §18 接收时忽略 ID、AA、TC 等字段。结构性截断仍整包拒绝。Answer/Authority/Additional 中的响应记录都可作为断言，查询中的 Known Answers 和探测 Authority 一律不进缓存；不相关记录可机会缓存，但不建立不匹配的服务身份。未知 RR 不写入受支持缓存。源端口、目标、接口等校验不能因 ID 被忽略而省略。

[RFC 6762 §11](https://www.rfc-editor.org/rfc/rfc6762.html#section-11) 将收到的链路本地组播目标响应视为本地链路来源，不要求来源地址与接口处于同一 IPv4 子网；叠加子网可能合法。发送 TTL=255 是 SHOULD；默认强制接收 TTL=255 会损失兼容性。因此额外的 CIDR 白名单和严格 TTL 校验属于应用收紧策略，不能描述成设备认证或所有接收端的 RFC 必选检查。单播接收不在本适配层支持范围。

自定义 Engine 适配器须自行执行网络来源检查；Engine 的 scope 字符串不是网络来源证明。不要将多个接口的数据标记成同一 scope。

main 可通过 `IngressPolicy::new(allowed_sources=[SourceNetwork::new(ip, prefix)], require_ip_ttl_255=true)` 传给 `Browser::open(..., ingress_policy=policy)`；空列表表示只执行默认路径检查，列表上限 64 个。CIDR 地址按 prefix 归一化；/32 允许一个来源，/0 允许所有来源。策略复制调用者数组，之后的数组变更不改变 Browser 行为。Datagram.ip_ttl 是可选值，缺失不伪造成 255；来源策略拒绝发生在录制和缓存之前，并静默丢弃以避免诊断放大。

接收 TTL 使用 Windows 的 IP_RECVTTL/WSARecvMsg 和 Linux 的 IP_RECVTTL/recvmsg 附加信息；字段读取有长度检查。操作系统不提供时默认策略继续工作，严格策略拒绝。平台接口依据 [Microsoft IPPROTO_IP 文档](https://learn.microsoft.com/en-us/windows/win32/winsock/ipproto-ip-socket-options)。两平台生产接收函数的单播回环 TTL=255/254/1 与 Linux mDNS 组播分别验证；Windows mDNS 组播和第二设备证据仍缺失。

ServiceSnapshot.observations 最多保留 64 项记录链来源观察：owner/type、接纳时间及最后正 TTL 接纳的传输元数据；超额有 observations_truncated。它不是全部发布者历史，不证明记录所有权。缺少来源的纯核心/旧回放输入保持空观察；标准 snapshot_json 暂不序列化这项附加 API 数据，以保持既有 trace 输出契约，不能据此假定 JSON 有完整来源链。

ServiceSnapshot.endpoints(accept, ipv4_only=true) 让应用显式筛选广告地址和端口，保留 SRV 候选顺序；默认只产生 IPv4 候选，部分快照不返回候选。它不执行连接或认证。选择 IPv6 时，链路本地候选 requires_ipv6_zone=true，宿主须将 scope 映射到实际接口；不能把 scope 字符串直接当 OS zone。

## 文件与隐私

可用 Replay 检查第三方文件，但文件仍不可信。CLI 有界读取，库限制输入、报文和累计输出；离线 Engine 关闭实时包速率限制以保留同时间戳回放语义，其总量预算继续执行。新增[replay_guard](replay-isolation.md) 为可信 CLI 子进程提供外部墙钟/CPU/内存预算并丢弃子进程输出。这不是文件系统或通用代码沙箱，也不是所有部署环境的 RSS 固定上限。

录制包含同接口设备名称、地址、端口及二进制 TXT。原始文件应保存在受控位置；校验和用于比较字节，只有配合可信传递渠道或签名才有来源意义。分享前使用脱敏导出或逐项审阅，脱敏后的事件摘要不能用于协议回放，也不保证消除时序与规模侧信道。

## 验证声明

固定种子的恶意输入回归、可重放的有界 fuzz、实网互通和资源循环是分项证据，不是独立渗透测试或完整安全审计。第二物理设备、Bonjour 和长时间实网压力仍无证据；已有同机、同 VM 和十分钟核心循环报告不能替代它们。
