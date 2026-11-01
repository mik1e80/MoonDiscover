# MoonDiscover（月见）十一月项目申报书

项目仓库：https://github.com/mik1e80/MoonDiscover

模块：`mik1e80/dnssd`；许可：Apache-2.0；方向：MoonBit 网络基础设施。

**已有基础。** 项目以 MoonBit 实现 mDNS / DNS-SD 浏览、服务解析、TTL 缓存、生命周期事件、查询调度和确定性回放，Native 适配层负责指定 IPv4 接口的组播通信。已发布 `0.1.0`。十一月前源码基线固定为 `c6e5ae51ef13c9b8670a4cb30cd6bb94b768e532`（2026-10-28）；十月已有修复不计作十一月新增。

**本期新增。** 十一月新增 SRV 优先级与确定性加权候选、构造记录的原子校验、恶意输入与共享主机回归、Native 失败关闭与错误分类、多包 Known-Answer 独立字节解析及三轮资源观察；进一步完成跨响应包 SRV、实际 UDP/Avahi 子类型专项、隔离接口恢复、十分钟资源循环，以及 0.2.0 发布与注册表独立消费。

**技术路线。** 保留纯 MoonBit Engine 与最小 Native socket 层分离的架构；按 mDNS cache-flush 宽限维护 SRV RRSet；用固定时间和随机种子复现状态变化；用 Avahi 独立发布服务并检查实际组播字节。网络恢复创建新的 Browser 与 scope，避免把不同网络的缓存合并。

**验收目标。**

1. 分包 SRV、记录替换和到期的定向测试通过，候选及服务事件符合公开契约。
2. Linux Avahi 专项报告覆盖子类型过滤、共享身份、多包 TC/问题/答案、取消和超限降级。
3. 接口失效后关闭并重建订阅有隔离环境证据；资源循环记录实际时长、逻辑计数和进程内存。
4. README、支持矩阵、API 与演示一致；相关轻量 CI 成功；发布新版本并从 Mooncakes 独立安装验证。

**功能边界。** 本期面向指定接口的 IPv4 QM 服务浏览与解析；不承诺 IPv6 组播、服务发布、NSEC、跨子网、自动接口迁移或所有设备兼容。第二物理设备和 Bonjour 验证另列待办。

**来源与文档。** 项目为原创实现；RFC 为协议参考，Avahi / python-zeroconf 为独立测试对端。来源与许可见 `THIRD_PARTY_NOTICES`、`fixtures/README.md`；贡献边界见 `docs/november-baseline.md`，运行入口和证据见 README。

材料状态：2026-11-01，供十一月报名准备使用；正式赛期、入口与要求以主办方十一月通知为准。本文件不表示已报名或审核通过。
