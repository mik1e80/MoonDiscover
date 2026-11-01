# 生态边界与新增价值

本项目不声称是首个 MoonBit mDNS 实现。下表是立项时固定源码考察得出的功能边界；来源、版本、许可与复用结论见 [依赖决策](docs/dependency-decision.md)，不用于声明其他项目当前版本缺少某项能力。

| 考察对象 | 已知交集 | MoonDiscover 已实现的相邻工作 |
| --- | --- | --- |
| moonbit-community/rtc.mbt 的 mdns | `.local` 主机 A/AAAA 查询与缓存 | PTR/SRV/TXT 服务聚合、部分/完整状态与范围隔离 |
| jinshengmeng46/moon-dns-stub | DNS wire 和普通 Native resolver | mDNS QM 调度、class 高位语义、goodbye/flush 宽限和连续生命周期 |
| moonbitlang/async | Native socket 与异步任务 | 指定接口的组播元数据适配、取消释放；协议状态由本项目纯核心处理 |
| python-zeroconf / Avahi | 独立 DNS-SD 实现 | Windows python-zeroconf 与 Linux Avahi 均作为同机/同 VM 受控实网对端；未隐藏调用其发现逻辑 |

项目当前价值在于可注入时间和输入的纯核心、带范围与完整性信息的稳定事件、Native 实网接入，以及把实网观察转为确定性回放的录制链路。Windows 已有独立进程发布到动态端口 HTTP 的证据；main 另有同 Linux VM 的 Avahi 八项实网闭环。main 还公开按 SRV 优先级和固定种子权重排序的候选列表，见 [契约与限制](docs/srv-selection.md)。第二设备与更完整规范覆盖仍待补，不能把一般闭环当成所有扩展已验证。
