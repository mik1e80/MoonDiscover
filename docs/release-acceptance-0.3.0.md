# 0.3.0 预发布验收

2026-11-20 仍为 0.3.0-dev。0.2.0 是现有发布包。

| 项目 | 当前可复现证据 |
| --- | --- |
| 模型、Wire、Cache、Engine、Replay | 78 项 JS smoke 通过。含跨报文正向优先、scope 隔离、负缓存到期及刷新、异常位图、Additional 和回放 |
| Native 实时 NSEC | Windows 同机实际组播，受控 Additional NSEC TTL 为 1 秒，约 1079ms 时观察到出站 AAAA 问题，然后返回 IPv6 地址并由 Browser 接纳。独立解析器检查出站问题 |
| 独立发布者 | 11 月 18 日保存的 zeroconf NSEC 抓包证据仍有效。受控短 TTL 实验和独立发布者抓包分别验证不同路径 |
| 外部 API | 单独目录的 MoonBit 工程通过源码映射运行 JS，验证 NSEC 存在和到期，Native 消费工程构建成功 |
| 候选归档 | 本地 moon package --list --frozen 通过，开发 ZIP 包含 LICENSE、THIRD_PARTY_NOTICES、README.md 与 moon.mod |

真实时间复现：构建 tests/protocol_live 与 tests/native_ttl 的 Native 目标，用 native_ttl --interface 获取活动 IPv4，再运行 protocol_live nsec-expiry <IPv4>。此实验同机运行，使用生产 Browser、受控发布输入和独立出站解析器。源码消费和本地开发归档只覆盖当前候选源码。

剩余验证包括 RFC 6762 §7.3 跨查询器抑制、多独立响应器的续包等待与互操作、第二物理设备和长时间实网，以及发布标签、归档散列与 Mooncakes 独立安装闭环。发布条件满足后才标记稳定版。
