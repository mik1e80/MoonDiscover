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

上述注册表核心验证使用注入时钟。

## 2026-11-26 注册表 Native 同机验收

在新建的仓库外工程固定依赖 `mik1e80/dnssd@0.3.0`，无 `moon.work` 源码映射。安装的 341 个文件逐一与已发布归档核对。Windows 同机的受控响应带有 1 秒 TTL 的 Additional NSEC。生产 Browser 接纳否定证据后，独立解码器在发包后 1125ms 观测到恢复的 AAAA 问题，并确认此时否定状态已失效。测试端随后发出正向 AAAA，Browser 的快照接纳了该地址。第一次在受限执行环境下未在 4.5 秒窗口完成。以本机网络权限新建独立工程重跑后通过。

使用项目固定工具链。在仓库根目录先刷新注册表索引，安装 `tests/interop/requirements.txt` 的测试依赖，再按顺序运行以下两步。将工作区参数替换为仓库外的新目录，Python 参数指向已安装 python-zeroconf 0.148.0 的解释器。脚本自动选择组播路由对应的 IPv4，测试可在拥有组播收发权限的本机接口复现。

```powershell
.\scripts\moon.ps1 update
.\scripts\moon.ps1 run scripts/registry-native-acceptance.mbtx -- nsec ../moondiscover-registry-native .tools/moon/bin/moon.exe
.\scripts\moon.ps1 run scripts/registry-native-acceptance.mbtx -- soak ../moondiscover-registry-native .tools/moon/bin/moon.exe .venv/Scripts/python.exe 3600
```

资源观测使用同一独立工程中的两个 Browser，订阅同机独立 python-zeroconf 0.148.0 发布的两个 `_md-tcproof._tcp.local.` 实例。实际运行达到 3600 秒，并执行了两者的关闭路径。第 10–50 分钟每十分钟采样，两者均各解析两个实例，每个 Browser 的缓存为 8–9 条、查询任务为 7。进程工作集（RSS）为 11.18–11.31 MiB，活跃句柄为 161–163，采样时未观察到丢事件、限速丢包或传输错误。

**关闭后句柄检查未通过。** 两个 Browser 的缓存清零，进程句柄为 161 个，预热基线为 157 个。旧探针在写终点报告前退出，保留到第 50 分钟的采样和关闭断言中的计数。用同一 `0.3.0` 安装、相同负载补跑 15 秒，两者均完成解析且关闭后句柄回到新进程的基线 151 个。短对照未复现，差额的归属、是否会累积及能否稳定复现仍待确认。探针现会在退出前写入终点测量。[原始观测数据](evidence/registry-native-0.3.0-20261126.json)

## 2026-11-26 Windows 句柄复核

继续使用同一个从 Mooncakes 安装 `0.3.0` 的独立项目、同机 IPv4 及固定的独立发布者。复跑耗时 3600000ms，最大轮询间隔 125ms。第 10 分钟到终点的每次采样中，两个 Browser 各解析两个实例，进程有 157 个活跃句柄。工作集在这些采样中为 2.88–4.27 MiB。工作集受 Windows 驻留页策略影响，按本轮样本报告。

| 观测阶段 | 进程句柄 | 与 151 个预热基线相比 |
| --- | ---: | --- |
| 两个 Browser 刚打开 | 153 | 新增两个 `File`，分别随各自的 Browser 关闭而消失 |
| 1 小时结束，关闭前 | 157 | 两个 `File`，加两个 `Thread`、两个 `Event` |
| 关闭第一个后 | 156 | 剩一个 `File`，两个 `Thread`、两个 `Event` |
| 两个都已关闭，立即及等待 1 秒后 | 155 | 两个 `Thread`、两个 `Event`。缓存清零，严格进程总数断言仍失败 |

随后在一个新的诊断进程内连续开关 50 对 Browser，每轮两者都各解析两个实例，关闭后缓存均为零。预热 149 个句柄；第 1–25 轮关闭并静置 100ms 后为 151，第 26–50 轮为 153。第一轮和最后一轮关闭后的快照均无本轮打开的两个 `File` 句柄。最后 25 轮保持 153，尚未验证多轮小时级运行下的累积性。

不创建 Browser 的对照中，并发执行三次异步文件写入后，进程由 122 增至 126，新增类型同样是两个 `Thread` 和两个 `Event`。`moonbitlang/async 0.22.5` 的 Windows 工作线程各持有一个唤醒事件，完成任务后的空闲线程会保留在事件循环内，事件循环清理时释放。对照与实现均支持空闲工作线程是总数偏差的解释。当前没有这四个对象各自的分配调用栈。观测未发现 Browser 打开的文件句柄留存，因此保留严格总数断言和诊断记录，生产库未修改。[原始采样及分类](evidence/windows-browser-handles-0.3.0-20261126.json) · [Microsoft 进程快照文档](https://learn.microsoft.com/en-us/windows/win32/api/processsnapshot/ns-processsnapshot-pss_handle_entry)

在上文的 `soak` 命令最后追加 `--handle-types` 采集 Windows 快照。按顺序完成长测后，在同一独立安装上执行循环实验。异步文件写入对照使用只运行探针的单独进程。

```powershell
.\scripts\moon.ps1 run scripts/registry-native-acceptance.mbtx -- cycles ../moondiscover-registry-native .tools/moon/bin/moon.exe .venv/Scripts/python.exe 50
.\scripts\moon.ps1 build tests/live_soak --target native --frozen
.\_build\native\debug\build\tests\live_soak\live_soak.exe --fs-control
```

发布源码 `fb3df9f` 的轻量 CI 和 Avahi 专项通过。TC 专项首次未满足恢复断言：8 轮中 7 轮解析，唯一首包丢失的一轮在 7.8 秒内的 4 次查询全部丢失。单独复跑失败作业后，首包丢失的 6 轮都重试并解析，8 轮均完整解析。两次结果均保留。[轻量 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/45757868524) · [Avahi 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45757800864) · [TC 首轮](https://github.com/mik1e80/MoonDiscover/actions/runs/45757800889/job/139700439654) · [TC 复跑](https://github.com/mik1e80/MoonDiscover/actions/runs/45757800889/job/139849551763)

## 2026-11-27 工作线程分配栈与多轮启停

在单独的临时工程验证 `moonbitlang/async@0.22.5` 的分配调用栈。在该工程的依赖副本加入探针，紧随 `CreateThread` 和唤醒用的 `CreateEventA` 记录返回句柄及调用栈。测试只执行三次并发异步文件写入。进程句柄从 121 增至 125，四个新增对象逐个匹配分配记录：

| 新增对象 | 首帧经 Windows 展开信息校验 | 配对方法 |
| --- | --- | --- |
| 两个 Thread | `moonbitlang_async_spawn_worker + 188` | 记录新线程 ID |
| 两个 Event | `worker_loop + 136` | 记录创建事件的线程 ID，分别与上面两个线程匹配 |

该记录确认异步文件对照中四个对象均来自 `moonbitlang/async`。此前一小时实验只保留了进程快照，历史对象的分配栈无法回溯。独立安装的长测使用未经插桩的依赖，未使用上述临时工程。[对象、模块偏移和依赖散列](evidence/windows-async-worker-stacks-20261127.json) · [Windows 栈捕获 API](https://learn.microsoft.com/en-us/windows/win32/debug/capturestackbacktrace)

原版 Mooncakes 0.3.0 在 Windows 同机 IPv4 组播中完成了两个一小时轮次。每轮打开同一进程内的两个 Browser，两者在十分钟采样及轮末均完整解析了两个服务，关闭后缓存均归零。第一轮的打开前、立即关闭、关闭后一秒句柄总数为 151 / 155 / 155，第二轮为 155 / 155 / 155。两轮每轮运行 3,600,000 ms，最大轮询间隔分别为 47 ms、63 ms。第三轮因所选 IPv4 接口失效或变化报告 `interface_unavailable`，实验中止。六小时句柄趋势仍待验证，当前证据覆盖两个完整轮次。

在已安装固定工具链的 Windows 环境中，使用以下命令复现两项实验，替换为不同的仓库外工作目录。`hourly` 使用已按上文完成 `nsec` 准备的原版注册表工程。

```powershell
.\scripts\moon.ps1 run scripts/trace-async-workers.mbtx -- ../moondiscover-worker-trace .tools/moon/bin/moon.exe
.\scripts\moon.ps1 run scripts/registry-native-acceptance.mbtx -- hourly ../moondiscover-registry-native .tools/moon/bin/moon.exe .venv/Scripts/python.exe 6 3600
```

## 2026-11-27 MoonBit 1.0 RC 验收复核

在 Windows 使用 `moonc v1.0.0-rc1+3c0520448` 完成 Native 严格类型检查、84 项 JS 测试、5 项 Native 重点测试、最小编码示例、浏览器回放和 CLI 版本验证。仓库为回放入口保留了 16 层 JSON 限制，并测试带引号、转义和括号的字符串及超深输入。

另建独立工程从 Mooncakes 安装原版 `0.3.0`，用同一编译器重复上文的 `nsec` 实验。同机 IPv4 组播下接受 Additional 区段中的 NSEC，设置 TTL 1 秒，发送后 1125 ms 首次观察到恢复的 AAAA 查询，随后接受正向响应并完成解析。该轮使用受控对端与独立的出站问题解析器，范围为同机 IPv4。原版发布包的这个实测与仓库主分支的回放修复分别对应各自源码。

同一工程于 11 月 27 日 23:28 启动六轮小时级复测。首轮完整运行 3600000 ms，最大轮询间隔 47 ms。两个 Browser 关闭后缓存均归零，打开前、立即关闭及关闭后一秒的句柄总数为 157 / 161 / 161。第二轮最后一次采样于 11 月 28 日 00:38 写入，两个 Browser 当时均完整解析两个实例。Windows 系统日志随后记录 00:43 关机，进程未留下第二轮关闭结果。此轮包含一次完整启停。

11 月 28 日 12:19 重新启动同一实验。首轮运行 3600000 ms，最大轮询间隔 156 ms，两个 Browser 关闭后缓存均归零，句柄总数为 151 / 155 / 155。句柄类型快照中，两个 Browser 运行时有 11 个 `File`，关闭后回到预热时的 9 个。首轮第 10 分钟至轮末的工作集为 11063296–11186176 字节。第二轮第 40 分钟采样时两者仍解析完整，之后程序于 14:03 报告 `interface_unavailable`，Windows WLAN 日志在该时段也记录了断开和重连。第二轮缺少关闭观测，六小时同进程趋势仍待在稳定接口上完成。[两次 RC 尝试的逐轮数据](evidence/windows-hourly-browser-rc1-20261128.json)

## 开发阶段与专项实测

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

单查询器响应方向实验中，zeroconf 连续两次响应被内核丢弃，三轮六次均无目标 PTR 到达。解除丢包并重新查询后，三轮均收到两条 PTR。固定 125ms 延迟的三轮也均收到两条 PTR。生产 Browser 在连续两次响应被丢弃后六轮均自动发出第三次查询并解析两个实例。50% 随机响应丢包实验的 18 次结果均与内核计数吻合。十二查询器的响应方向无损、定向丢包、恢复后重新查询和延迟各三轮，套接字收包与内核计数一致。十二个生产 Browser 在随机响应丢包的八轮均完整解析两实例，首份响应丢弃的六轮均观测到自动重发。受控响应报文乱序三轮均反转到达顺序且两条 PTR 可解码。生产 Browser 在 PTR 先到和 SRV、TXT、IPv4 地址先到的三轮对照中均从两份正向响应聚合出同一完整实例。仓库源码也在 Windows 同机组播通过受控乱序叠加 SRV 到期、PTR goodbye 的各三轮。Avahi 0.8 的实际记录经过重新分包后，在 Linux 隔离 veth 上通过乱序叠加 SRV 到期和 PTR goodbye 各三轮。后续由 Avahi 守护进程实时发送原封包，隔离链路上观测到最后一份正向 SRV 收到 120000 ms 后到期，以及另一个实例的迟到正向响应进入宽限时，目标 PTR 仍在 goodbye 后 1005 ms 移除。[原封包实测](tc-interop.md#avahi-守护进程原封包的实时乱序与生命周期)。[实测报告](tc-interop.md#响应方向丢包恢复和延迟) · [乱序生命周期](tc-interop.md#乱序叠加-srv-到期和-ptr-goodbye)

单查询器查询方向配置 50% 随机丢包，18 次普通 QM 的发送、内核计数、对端收包和 PTR 响应逐次对应。内核放行 6 份、丢弃 12 份。单个与十二个生产 Browser 各运行八轮，均解析两个实例。首份查询丢失时，两种规模均观察到自动重发。多查询器场景中，即使初始发送源的重发也被丢弃，其他源到达的查询仍可带来共享组播响应。[实测报告](tc-interop.md#查询方向随机丢包)

双向各配置 50% 随机丢包时，单个与十二个生产 Browser 各跑八轮，两种规模均观测到自动重发。7.8s 内，单 Browser 四轮解析完成，四轮无完整解析。十二 Browser 八轮均完成。单 Browser 延长至 30s 另测八轮，七轮完整解析，一轮到期未完成。十二 Browser 的重叠双向突发丢包三轮均完整解析。60s 单 Browser 复测中三轮在 30s 后仍自动重发，两轮约 31.15s 完成，一轮到 60s 仍未完成。十二 Browser 的 5s 重叠突发三轮均完成。120s 单 Browser 复测中三轮在约 63 秒自动重发，一轮在 63.190 秒完成，两轮到期仍未完成。十二 Browser 的 10 秒重叠突发丢包三轮均为 12/12 完整解析。240s 单 Browser 复测八轮均完成，一轮在 127.089 秒重发并于 127.161 秒完整解析。十二 Browser 的 20 秒重叠突发丢包三轮均为 12/12 完整解析。480s 单 Browser 复测中，独立随机样本八轮有七轮完整解析，一轮在约 255 秒重发后到期仍未解析。固定种子补充轮在 255.172 秒完整解析。十二 Browser 的 40 秒重叠突发丢包三轮均为 12/12 完整解析。960s 单 Browser 复测中，独立随机样本八轮有七轮完整解析，一轮在 511.094 秒自动重试后到期仍未解析。固定种子补充轮在 511.123 秒完整解析。十二 Browser 的 80 秒重叠突发丢包三轮均为 12/12 完整解析。1920s 单 Browser 复测中，独立随机样本八轮有七轮完整解析，一轮在 1023.085 秒自动重试后到期仍未解析。固定种子补充轮在 1023.138 秒完整解析。十二 Browser 的 160 秒重叠突发丢包三轮均为 12/12 完整解析。其他丢包率、突发持续时间、独立随机样本中 960 秒后的完整解析及 1920 秒后的恢复仍待验证。[双向实测报告](tc-interop.md#browser-在双向随机丢包下的重试与解析)

第二台物理设备、Bonjour、多个小时级运行周期中的句柄趋势、6 小时观察、多主机局域网压力和上文列出的组合与恢复场景仍待验证。
