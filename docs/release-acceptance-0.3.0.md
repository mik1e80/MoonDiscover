# 0.3.0 预发布验收

2026-11-20 仍为 0.3.0-dev。0.2.0 是现有发布包。

| 项目 | 当前可复现证据 |
| --- | --- |
| 模型、Wire、Cache、Engine、Replay | 79 项定向 JS smoke。含跨报文正向优先、scope 隔离、明确否定 TXT 的空属性、负缓存到期及刷新、异常位图、Additional 和回放 |
| Avahi Known-Answer | 两个服务由同一 daemon 发布。对照收到两条 PTR 且带 Known-Answer 的查询收到另一条 PTR 时，才报告是否省略已知记录。任一条件不足时报告不可比较。此前运行既曾返回已知 PTR，也曾缺少对照记录，保留现象作为未闭环证据 |
| Native 实时 NSEC | Windows 同机实际组播，受控 Additional NSEC TTL 为 1 秒，约 1079ms 时观察到出站 AAAA 问题，然后返回 IPv6 地址并由 Browser 接纳。独立解析器检查出站问题 |
| 独立发布者与解码器 | 固定 zeroconf 0.148.0. 实际录制中的 NSEC 由其解码器和 MoonDiscover 分别解析，逐条对照 TTL 与全部置位类型。Windows 本机 18 条一致，Replay 另观察 12 次有效否定。受控短 TTL 实验是另一条证据 |
| 外部 API | 单独目录的 MoonBit 工程通过源码映射运行 JS，验证 NSEC 存在和到期，Native 消费工程构建成功 |
| 候选归档 | 本地 moon package --list --frozen 通过，开发 ZIP 包含 LICENSE、THIRD_PARTY_NOTICES、README.md 与 moon.mod |

真实时间复现：构建 tests/protocol_live 与 tests/native_ttl 的 Native 目标，用 native_ttl --interface 获取活动 IPv4，再运行 protocol_live nsec-expiry <IPv4>。此实验同机运行，使用生产 Browser、受控发布输入和独立出站解析器。源码消费和本地开发归档只覆盖当前候选源码。

Linux 实验运行 [44730748989](https://github.com/mik1e80/MoonDiscover/actions/runs/44730748989) 在约 1107ms 恢复 AAAA 并通过正向接纳验证。普通 Avahi goodbye 通过。独立 zeroconf 实验同样收到了 NSEC，但未在观察窗得到 goodbye 移除事件。NSEC 专项按真实收包、解码一致和 Replay 验收，报告继续保留 zeroconf goodbye 的实际结果。常规完整场景仍要求原有的 goodbye 断言。

RFC 6762 §7.3 受限路径新增跨 scope、子集、TTL、TC、反复输入与 Native 回环回归。Linux 隔离网络实验观察不同发送地址的组播。剩余验证包括第二设备上的跨查询器行为、多独立响应器的续包等待与互操作、长时间实网，以及发布标签、归档散列与 Mooncakes 独立安装闭环。发布条件满足后才标记稳定版。
