# 0.3.0 验收与发布证据

本页保留开发阶段实测，并记录 0.3.0 的交付验证。

## 2026-11-26 发布与注册表独立验收

`mik1e80/dnssd@0.3.0` 已发布至 [Mooncakes](https://mooncakes.io/docs/mik1e80/dnssd)。[GitHub v0.3.0](https://github.com/mik1e80/MoonDiscover/releases/tag/v0.3.0) 固定到源提交 `fb3df9fa0e59c28d279ded9ef54e52c124d082d7`。Mooncakes 上传返回 200，下载归档及 GitHub 附件的 SHA-256 相同，独立安装的 341 个文件均与归档内容匹配。归档包含 LICENSE、THIRD_PARTY_NOTICES、README.md 和 moon.mod。[发布与实测数据](evidence/release-0.3.0-20261126.json)

| 项目 | 实测结果 |
| --- | --- |
| 定向回归 | Wire、Cache、Engine 的 9 项 NSEC 测试通过，Native 严格检查、格式和接口检查通过。 |
| CLI | Native 构建及冒烟通过，`--help` 和 `--version` 与模块的 0.3.0 一致。 |
| 独立消费 | 新建仓库外工程，安装精确 0.3.0，未使用 `moon.work` 或本地源码映射。JS 公共 API 运行通过，Native 公共入口构建成功。 |
| NSEC 抑制与恢复 | 注入 2 秒 TTL 的 Additional NSEC。虚拟时间 120ms 和 1999ms 解码出站报文均无目标 AAAA，PTR 仍发出。2000ms 断言负缓存到期，至 2120ms 解码到目标 AAAA 查询。IPv4 服务快照在否定有效时仍完整。 |

复现时用仓库固定工具链先执行 `moon update`，再运行 `python tests/interop/consumer_smoke.py --mode registry --version 0.3.0`。该命令默认创建仓库外的临时工程。首次发布后的安装尝试使用了旧索引，刷新后在新目录成功。

本次注册表验证使用注入时钟。独立工程构建了 Native 入口，同机真实组播的 NSEC 到期证据见下文历史实测。第二台实体设备、Bonjour、长时间真实局域网压力和其他未覆盖的组合故障仍待验证。

| 项目 | 当前可复现证据 |
| --- | --- |
| 模型、Wire、Cache、Engine、Replay | 79 项定向 JS smoke。含跨报文正向优先、scope 隔离、明确否定 TXT 的空属性、负缓存到期及刷新、异常位图、Additional 和回放 |
| Avahi Known-Answer | 两个服务由同一 daemon 发布。对照须收到两条 PTR，单包和 TC 续包各自在收到另一条 PTR 时记录是否省略已知 PTR，并记录首条匹配回答的等待时间。缺少对照时标为不可比较 |
| Native 实时 NSEC | Windows 同机实际组播，受控 Additional NSEC TTL 为 1 秒，约 1079ms 时观察到出站 AAAA 问题，然后返回 IPv6 地址并由 Browser 接纳。独立解析器检查出站问题 |
| 独立发布者与解码器 | 固定 zeroconf 0.148.0. 实际录制中的 NSEC 由其解码器和 MoonDiscover 分别解析，逐条对照 TTL 与全部置位类型。Windows 本机 18 条一致，Replay 另观察 12 次有效否定。受控短 TTL 实验是另一条证据 |
| 外部 API | 单独目录的 MoonBit 工程通过源码映射运行 JS，验证 NSEC 存在和到期，Native 消费工程构建成功 |
| 候选归档 | 本地 moon package --list --frozen 通过，开发 ZIP 包含 LICENSE、THIRD_PARTY_NOTICES、README.md 与 moon.mod |

真实时间复现：构建 tests/protocol_live 与 tests/native_ttl 的 Native 目标，用 native_ttl --interface 获取活动 IPv4，再运行 protocol_live nsec-expiry <IPv4>。此实验同机运行，使用生产 Browser、受控发布输入和独立出站解析器。源码消费和本地开发归档只覆盖当前候选源码。

Linux 实验运行 [44730748989](https://github.com/mik1e80/MoonDiscover/actions/runs/44730748989) 在约 1107ms 恢复 AAAA 并通过正向接纳验证。普通 Avahi goodbye 通过。独立 zeroconf 实验同样收到了 NSEC，但未在观察窗得到 goodbye 移除事件。NSEC 专项按真实收包、解码一致和 Replay 验收，报告继续保留 zeroconf goodbye 的实际结果。常规完整场景仍要求原有的 goodbye 断言。

RFC 6762 §7.3 受限路径新增跨 scope、子集、TTL、TC、反复输入与 Native 回环回归。在 [Linux 44742577533](https://github.com/mik1e80/MoonDiscover/actions/runs/44742577533)，两个独立源 IPv4 地址通过隔离网络实际交换查询，本端在 1008ms 恢复发送。

[Linux 44743492242](https://github.com/mik1e80/MoonDiscover/actions/runs/44743492242) 复测本端在 1010ms 恢复发送。单 Avahi daemon 的普通查询收到两条 PTR，单包和 TC 续包只收到未知成员。首条匹配回答分别约为 55ms、55ms、38ms。

后续已在同一 Linux VM 完成 Avahi 与 python-zeroconf 双响应器对照。十次仅发 TC 首包的实验中，五次另记录 zeroconf 的 413–465ms 内部定时器，实际约 415–466ms 触发。Avahi 十次实际回包均早于 400ms。六组双查询器对照均收到所需 PTR。

2026-11-21 归档的连续 TC 专项及四查询器复测中，zeroconf 六次均从最后一个带 TC 的续包重新计时，432.569–499.668ms 后触发。Avahi 六次均在第一份续包之前回包。三查询器和四查询器各测三次，竞争查询器每次都在 A 的末包后收到两种响应器的所需 PTR。同机已观测主动省略续包、交换续包和末包提前三种行为。

五至十三个查询器同机实验各三轮，每轮均收到各方共同缺少的 PTR。单个及五至十二个查询器在隔离 veth 上分别完成无损、指定续包丢包和乱序实验，各场景三轮。单查询器无损时 zeroconf 均省略目标已知 PTR，丢包和乱序时均返回。五至十二查询器的三种场景中，每个套接字都收到两条目标 PTR。十四个及以上查询器、十三个及以上查询器叠加链路故障、Avahi 同类链路实验、Windows 与 Bonjour 同类 TC 实验和跨设备仍待验证。[实验及数据](tc-interop.md)

单查询器响应方向实验中，zeroconf 连续两次响应被内核丢弃，三轮六次均无目标 PTR 到达。解除丢包并重新查询后，三轮均收到两条 PTR。固定 125ms 延迟的三轮也均收到两条 PTR。生产 Browser 在连续两次响应被丢弃后六轮均自动发出第三次查询并解析两个实例。50% 随机响应丢包实验的 18 次结果均与内核计数吻合。十二查询器的响应方向无损、定向丢包、恢复后重新查询和延迟各三轮，套接字收包与内核计数一致。十二个生产 Browser 在随机响应丢包的八轮均完整解析两实例，首份响应丢弃的六轮均观测到自动重发。受控响应报文乱序三轮均反转到达顺序且两条 PTR 可解码。生产 Browser 在 PTR 先到和 SRV、TXT、IPv4 地址先到的三轮对照中均从两份正向响应聚合出同一完整实例。乱序与 TTL 到期或 goodbye 叠加仍待验证。[实测报告](tc-interop.md#响应方向丢包恢复和延迟)

单查询器查询方向配置 50% 随机丢包，18 次普通 QM 的发送、内核计数、对端收包和 PTR 响应逐次对应。内核放行 6 份、丢弃 12 份。单个与十二个生产 Browser 各运行八轮，均解析两个实例。首份查询丢失时，两种规模均观察到自动重发。多查询器场景中，即使初始发送源的重发也被丢弃，其他源到达的查询仍可带来共享组播响应。[实测报告](tc-interop.md#查询方向随机丢包)

双向各配置 50% 随机丢包时，单个与十二个生产 Browser 各跑八轮，两种规模均观测到自动重发。7.8s 内，单 Browser 四轮解析完成，四轮无完整解析。十二 Browser 八轮均完成。单 Browser 延长至 30s 另测八轮，七轮完整解析，一轮到期未完成。十二 Browser 的重叠双向突发丢包三轮均完整解析。60s 单 Browser 复测中三轮在 30s 后仍自动重发，两轮约 31.15s 完成，一轮到 60s 仍未完成。十二 Browser 的 5s 重叠突发三轮均完成。120s 单 Browser 复测中三轮在约 63 秒自动重发，一轮在 63.190 秒完成，两轮到期仍未完成。十二 Browser 的 10 秒重叠突发丢包三轮均为 12/12 完整解析。240s 单 Browser 复测八轮均完成，一轮在 127.089 秒重发并于 127.161 秒完整解析。十二 Browser 的 20 秒重叠突发丢包三轮均为 12/12 完整解析。480s 单 Browser 复测中，独立随机样本八轮有七轮完整解析，一轮在约 255 秒重发后到期仍未解析。固定种子补充轮在 255.172 秒完整解析。十二 Browser 的 40 秒重叠突发丢包三轮均为 12/12 完整解析。960s 单 Browser 复测中，独立随机样本八轮有七轮完整解析，一轮在 511.094 秒自动重试后到期仍未解析。固定种子补充轮在 511.123 秒完整解析。十二 Browser 的 80 秒重叠突发丢包三轮均为 12/12 完整解析。1920s 单 Browser 复测中，独立随机样本八轮有七轮完整解析，一轮在 1023.085 秒自动重试后到期仍未解析。固定种子补充轮在 1023.138 秒完整解析。十二 Browser 的 160 秒重叠突发丢包三轮均为 12/12 完整解析。其他丢包率、突发持续时间、独立随机样本中 960 秒后的完整解析及 1920 秒后的恢复仍待验证。[双向实测报告](tc-interop.md#browser-在双向随机丢包下的重试与解析)

第二台物理设备、Bonjour、长时间真实局域网压力和上文列出的组合与恢复场景仍待验证。
