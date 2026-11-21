# 两种独立 mDNS 响应器的 TC 续包实验

实验在同一 Linux CI 虚拟机上运行 Avahi 0.8 与 python-zeroconf 0.148.0 两种独立实现。每个响应进程独占两个服务实例，一条 PTR 用作 Known-Answer，一条作为未知成员。两个响应器使用同一测试接口，按唯一登记的 PTR 目标归属。网络路径是实际 IPv4 组播 UDP。

普通 QM 查询必须收到四条匹配 PTR。后续场景间保留安静期并清空接收队列。独立测试解析器验证 TC 首包有问题、末包无问题且携带两条 Known-Answer。探针从首次发送前开始用单调时钟计时，记录每个匹配 PTR 的首次接收时间。延迟续包人为制造可辨别的观测窗口，产品发送路径仍需按 RFC 6762 §7.2 紧接首包发送续包。[RFC 6762 §7.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.2)

第一轮五组对照如下。[原始观测](evidence/linux-two-responder-tc-20261120.json) · [GitHub 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/44744493713)

| 场景 | Avahi 0.8 | python-zeroconf 0.148.0 |
| --- | --- | --- |
| 普通查询 | 24ms 收到两条 PTR | 27ms 收到两条 PTR |
| 单包带 Known-Answer | 24ms 收到未知 PTR，观测窗内无已知 PTR | 94ms 收到未知 PTR，观测窗内无已知 PTR |
| 立即 TC 续包 | 100ms 收到未知 PTR，观测窗内无已知 PTR | 70ms 收到未知 PTR，观测窗内无已知 PTR |
| 首包后 252ms 发续包 | 99ms 已收到两条 PTR，早于续包 | 274ms 收到未知 PTR，观测窗内无已知 PTR |
| 仅发 TC 首包 | 99ms 收到两条 PTR | 564ms 收到两条 PTR |

## 重复测量与双查询器复测

两次独立运行各测五次仅发 TC 首包。Avahi 的首条匹配 PTR 在 37–93ms 到达，0/10 落在 400–500ms。zeroconf 在 463–556ms 到达，2/10 落在该区间。接收时间包含发送队列和进程唤醒。Avahi 的内部定时器没有接入观测。[重复测量原始观测](evidence/linux-tc-repeat-20261120.json) · [带定时器复测](evidence/linux-tc-timer-20261120.json)

在第二次运行的 zeroconf 发布进程中，记录原事件循环的 TC 定时器调用，保留原 deadline。按同机单调时钟将设定和触发与五次只发首包的查询对应。五次均在目标窗口设定和触发。该结论覆盖这一版本在无续包时的内部等待。其 UDP 回包可以晚于 500ms。[zeroconf 的 TC 定时器实现](https://github.com/python-zeroconf/python-zeroconf/blob/0.148.0/src/zeroconf/_listener.py) · [运行记录](https://github.com/mik1e80/MoonDiscover/actions/runs/44745779995)

| 只发首包的复测 | 定时器设定值 | 自设定到触发 | zeroconf UDP 到达 |
| --- | ---: | ---: | ---: |
| 1 | 413ms | 414.744ms | 463ms |
| 2 | 443ms | 444.828ms | 520ms |
| 3 | 422ms | 422.744ms | 531ms |
| 4 | 465ms | 465.802ms | 512ms |
| 5 | 417ms | 417.725ms | 480ms |

双查询器使用同一接口的两个源 IPv4 地址。A 先发 TC 首包，约 30ms 后由 B 发出不含 Known-Answer 的同名 PTR 查询，随后 A 立即发出携带已知记录的末包。探针核对三份组播报文的源地址与顺序，并单独从 B 的套接字观察回答。

两轮各三组对照。只有 A 时，6/6 在两种响应器上均只观察到未知 PTR。加入 B 后，6/6 的 B 在续包后收到两种响应器的已知及未知 PTR。按 A 首包起算，B 收到所需 PTR 的时间为 Avahi 32–119ms、zeroconf 65–533ms。该样本覆盖 B 在 A 的首包和末包之间发出普通 QM 的场景。

## 连续 TC 续包与三个查询器

专项于 2026-11-20（北京时间）在同一 Linux 虚拟机执行，结果于 11 月 21 日归档。三次分别在 0、151、301ms 发首包和两个带 TC 的续包。两个续包各携带一条不同的已知 PTR，观察期间保持 TC，没有发送清除 TC 的末包。探针观察实际组播报文并按同机单调时钟核对 zeroconf 的内部定时器。

| 连续 TC 试次 | Avahi 首条 UDP PTR（相对首包） | zeroconf 最后一个定时器设定 | zeroconf 最后一次设定至触发 | zeroconf 首条 UDP PTR（相对最后一个 TC 包） |
| --- | ---: | ---: | ---: | ---: |
| 1 | 102ms | 499ms | 499.668ms | 546ms |
| 2 | 101ms | 442ms | 442.591ms | 500ms |
| 3 | 102ms | 476ms | 477.623ms | 538ms |

zeroconf 三次均为每个 TC 包重新设定定时器，仅最后一个定时器触发，并省略两个续包声明的已知 PTR。Avahi 三次都在第一份续包到达前回复，无法从这条网络观测推断它内部的定时器实现。[RFC 6762 §7.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.2)

三个查询器使用同一接口上不同源 IPv4 地址。A 在 0ms 发 TC 首包，B 在 25ms 发不含 Known-Answer 的查询，C 在 31ms 发携带另两条 Known-Answer 的同名查询。B 和 C 都需要 A 所知的两条 PTR。A 在 37ms 才发清除 TC 的末包。探针核对实际发送源和顺序，并从 B、C 各自套接字的末包标记之后开始计数。

三组 A 单独查询对照中，两种响应器都省略 A 已知的 PTR。加入 B、C 后，三组里 B 和 C 都在 A 的末包之后收到了两种响应器返回的所需 PTR。Avahi 的首次到达时刻为 65–69ms，zeroconf 为 127–134ms，均从 A 的首包起算。[原始观测](evidence/linux-tc-chain-three-queriers-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44746788465)

## 续包缺失、重排与四个查询器

2026-11-21（北京时间）在 Linux CI 上用同样的两个响应器复测。普通 QM 对照收到四条 PTR。下表的时间从探针开始本组观测起算，括号内是实际发包时刻。每个顺序场景运行一次。省略续包由探针主动跳过发送，重排由探针改变发送顺序。[原始观测](evidence/linux-tc-loss-four-queriers-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44879924995)

| 场景和发包时刻（ms） | Avahi 的对照 PTR | zeroconf 的对照 PTR |
| --- | --- | --- |
| 顺序发送（1、38、72、106） | 声明为已知的 PTR 未收到，另一条 48ms 收到 | 声明为已知的 PTR 未收到，另一条 213ms 收到 |
| 省略载有 zeroconf 对照 PTR 的续包（0、36、106） | 两条均在 35ms 收到 | 两条均在 177ms 收到 |
| 交换两个带 TC 的续包（0、35、72、106） | 两条均在 35ms 收到 | 声明为已知的 PTR 未收到，另一条 134ms 收到 |
| 末包先于最后一个带 TC 的续包（0、36、73、106） | 两条均在 36ms 收到 | 两条均在 119ms 收到 |

各组的另一条 Avahi PTR 在末包中声明为已知，但本次均早于末包收到。交换续包时，Avahi 自己的已知 PTR 位于 72ms 发出的续包，晚于已观测的回答。末包提前时，zeroconf 在迟到的 TC 续包之后仍发出了该续包声明的 PTR。本轮另做三次只有带 TC 包的计时对照。zeroconf 从最后一个带 TC 的续包设定到触发分别为 440.573、487.663、432.569ms。Avahi 三次在 47–48ms 已回包，早于第一份续包。

四查询器实验中，A 发出 TC 首包，随后 B、C、D 在 18–31ms 陆续发出三份同名 QM 查询，A 在 37ms 发末包。B、C、D 都需要 A 已知的两条 PTR。三轮实验中，B、C、D 各自在观察到 A 的末包后均收到了两种响应器的所需 PTR。按 A 首包起算，Avahi 在 80–119ms 到达，zeroconf 在 129–521ms 到达。A 单独查询的三轮配对对照中，zeroconf 三次都省略 A 已知的 PTR，Avahi 两次省略，另一次在 35ms 已回包，末包于 36ms 发出。

## 五个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机五个不同 IPv4 源请求同一服务类型。A 先发 TC 首包，B、C、D、E 在 18–38ms 发出查询，A 在 46–47ms 发出带两条已知 PTR 的末包。五方都缺少 `zc-unknown`。B 不携带 Known-Answer，C、D、E 携带同一条 `av-unknown`，用不同的剩余 TTL 保持报文可区分。

三轮中，五方都在 A 发出末包后收到共同缺少的 `zc-unknown`，按每轮探针开始计为 519–520ms。B、C、D、E 也都在各自观察到末包后，收到 A 已知而它们缺少的两条 PTR。Avahi 的记录在 58–94ms 到达，zeroconf 的记录在 519–520ms 到达。三轮 A 单独查询对照中，两种响应器都省略 A 已知的 PTR，共同缺少的 `zc-unknown` 在 71–134ms 到达。[原始观测](evidence/linux-tc-five-queriers-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44881056220)

## 隔离链路丢包与乱序

同一 Linux VM 创建两个独立网络命名空间，用一对虚拟网卡（veth）连接。发送端每轮都按首包、续包 1、续包 2、末包的顺序发出四份真实 IPv4 组播 UDP 数据报。只有续包 2 声明 `zc-known`。发送端的 Linux netem 队列只处理这份续包。接收端根据源地址、接口和报文内容核对到达顺序，另读内核队列统计。普通查询先确认 python-zeroconf 0.148.0 发布的两条 PTR 都能收到。[Linux netem 手册](https://man7.org/linux/man-pages/man8/tc-netem.8.html) · [原始观测](evidence/linux-tc-five-queriers-netem-20261121.json)

| 场景（各三轮） | 对端实际收包顺序 | 目标队列每轮通过 / 丢弃 | zeroconf 回包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | `zc-known` 3/3 未收到，另一条在 114–150ms 到达 |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 3/3 均收到，100–193ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 3/3 均收到，117–149ms |

回包时间从发送端探针开始计。乱序三轮中，接收端观察到续包 2 比末包晚约 100ms。内核作用于查询方向的一个指定包，响应方向保持正常。五查询器竞争与链路故障分别执行。前两次 CI 在隔离发布者的 Python 环境和准备阶段失败，作为调试记录保留。最终专项在修复后通过。[运行记录](https://github.com/mik1e80/MoonDiscover/actions/runs/44881056220)

## 六个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机六个独立源 IPv4 请求同一服务类型。A 先发 TC 首包，B 至 F 在 18–44ms 发出各自的 QM 查询，A 在 52–53ms 发出声明 `av-known` 和 `zc-known` 的末包。六方都缺少 `zc-unknown`。与五查询器实验一样，B 不携带 Known-Answer，其余竞争查询器用 `av-unknown` 的不同剩余 TTL 区分报文。

三轮均观察到六方在 A 的末包后收到 `zc-unknown`，距每轮探针开始 519–520ms。B 至 F 也都在各自观察到末包后收到 A 已知的两条 PTR。Avahi 在 53–65ms 到达，zeroconf 在 519–520ms 到达。三轮 A 单独查询对照中，两种响应器均省略 A 已知的 PTR，`zc-unknown` 在 133–162ms 到达。[原始观测](evidence/linux-tc-six-queriers-five-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44881883100)

## 五个查询器叠加链路丢包与乱序

同一 Linux VM 内的发送侧使用五个独立 IPv4 源，接收侧运行 python-zeroconf 0.148.0。A 依序发送带 TC 的首包、续包 1、携带 `zc-known` 的续包 2 和清除 TC 的末包。B 至 E 在 A 的首包和续包 1 之间查询同一服务类型。B 发普通 QM，C 至 E 用同一条未发布的占位 PTR 和不同 TTL 区分查询。所有来源都缺少 `zc-unknown`，B 至 E 同时缺少 `zc-known`。

每组运行三轮，发送顺序相同。接收侧探针按报文内容和源地址确认 B 至 E 的四份查询全部过链路，只对 A 的续包 2 使用 netem。发送侧逐个套接字记录两条 PTR 的首次到达时间。

| 场景 | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 五个套接字的收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（15/15），124–510ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（15/15），87–511ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（15/15），509–510ms |

乱序三轮中，续包 2 均比末包晚 100ms 到达。所有场景均在 A 发出末包后收到两条 PTR。五查询器的无损组也收到 `zc-known`，单查询器隔离实验的无损组曾省略该记录。这些结果覆盖固定发包顺序和单个指定续包的故障。[原始观测](evidence/linux-tc-six-queriers-five-netem-20261121.json)

## 七个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机七个独立 IPv4 源请求同一服务类型。A 先发 TC 首包，B 至 G 在 18–50ms 发出各自的 QM 查询，A 在 59ms 发出声明 `av-known` 和 `zc-known` 的末包。七方都缺少 `zc-unknown`。B 不携带 Known-Answer，C 至 G 用 `av-unknown` 的不同剩余 TTL 区分报文。

三轮中，七方都在 A 的末包后收到 `zc-unknown`，距每轮探针开始 519–521ms。B 至 G 也都在各自观察到末包后收到 A 已知的两条 PTR，Avahi 在 93–111ms 到达，zeroconf 在 519–521ms 到达。三轮 A 单独查询对照中，两种响应器均省略 A 已知的 PTR，`zc-unknown` 在 131–150ms 到达。[原始观测](evidence/linux-tc-seven-queriers-six-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44882530492)

## 六个查询器叠加链路丢包与乱序

沿用五查询器实验的隔离 veth 和 python-zeroconf 0.148.0。B 至 F 在 A 的首包与续包 1 之间查询同一服务类型。六方都缺少 `zc-unknown`，B 至 F 同时缺少 `zc-known`。接收侧按来源和报文内容验证五份竞争查询均到达。netem 只处理 A 携带 `zc-known` 的续包 2。

| 场景（各三轮） | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 六个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（18/18），510–511ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（18/18），510–511ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（18/18），78–511ms |

乱序三轮中，续包 2 比末包晚 99–100ms 到达。第一轮六个套接字在 78ms 收到两条 PTR，早于 A 在 90ms 发出的末包。另两轮分别在 511ms 和 510ms 收到。队列只改变查询方向的指定续包。这些时间为探针的收包观测。[原始观测](evidence/linux-tc-seven-queriers-six-netem-20261121.json)

## 八个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机八个独立 IPv4 源请求同一服务类型。B 至 H 在 A 的首包后 18–56ms 发出 QM 查询，A 在 65ms 发出包含 `av-known` 和 `zc-known` 的末包。八方都缺少 `zc-unknown`。三轮中，八方都在 A 的末包之后收到这条 PTR，距首包 519–520ms。B 至 H 也各自在观察到末包之后收到 A 已知的两条 PTR，Avahi 为 75–83ms，zeroconf 为 519–520ms。三轮 A 单独查询对照中，两种响应器均省略 A 已知的 PTR，`zc-unknown` 在 98–161ms 到达。[原始观测](evidence/linux-tc-eight-queriers-seven-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44917914188)

## 七个查询器叠加链路丢包与乱序

沿用隔离 veth 与 python-zeroconf 0.148.0。A 仍按首包、续包 1、续包 2、末包的顺序发送。B 至 G 在 A 的首包和续包 1 之间查询。七方都缺少 `zc-unknown`，B 至 G 同时缺少 `zc-known`。接收侧逐份核对六个竞争来源的查询。netem 仅处理 A 携带 `zc-known` 的续包 2，各场景执行三轮。

| 场景 | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 七个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（21/21），510–511ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（21/21），510–511ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（21/21），509–511ms |

乱序三轮中，续包 2 都比末包晚 100ms 到达。九轮均在 A 发出末包后收到两条 PTR。表中的时间为发送端从探针启动到各套接字首次观察到记录的时间。响应方向的链路保持正常。[原始观测](evidence/linux-tc-eight-queriers-seven-netem-20261121.json)

## 九个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机九个独立 IPv4 源请求同一服务类型。B 至 I 在 A 的首包后 18–62ms 发出 QM 查询，A 在 69ms 发出声明 `av-known` 和 `zc-known` 的末包。九方都缺少 `zc-unknown`，三轮均在末包后收到这条 PTR，距首包 519–520ms。

B 至 I 每轮也在各自观察到末包后收到 `zc-known`。`av-known` 在前两轮于 74–75ms 到达 B 至 I。第三轮 A 在 63ms 已观察到 `av-known`，早于 69ms 的末包，B 至 I 的末包后窗口均无这条记录。三轮 A 单独查询对照中，zeroconf 均省略 A 声明的已知记录，Avahi 两轮省略，另一轮在 64ms 回包，早于 70ms 的末包。[原始观测](evidence/linux-tc-nine-queriers-eight-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44918472984)

## 八个查询器叠加链路丢包与乱序

发送侧用八个独立 IPv4 源，接收侧运行 python-zeroconf 0.148.0。接收侧逐份确认 B 至 H 的七份竞争查询均到达。八方都缺少 `zc-unknown`，B 至 H 同时缺少 `zc-known`。netem 仅处理 A 携带 `zc-known` 的续包 2，各场景执行三轮。

| 场景 | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 八个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（24/24），509–510ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（24/24），510–511ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（24/24），509–511ms |

乱序组中，续包 2 每轮比末包晚 99–100ms 到达。九轮均在 A 发出末包后收到两条 PTR，表中的时间从发送端探针开始计。响应方向的链路保持正常。[原始观测](evidence/linux-tc-nine-queriers-eight-netem-20261121.json)

## 十个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机十个独立 IPv4 源请求同一服务类型。B 至 J 在 A 首包后 18–68ms 发出各自的 QM 查询，A 在 77–78ms 发出携带 `av-known` 和 `zc-known` 的末包。三轮中，十方都在末包后收到共同缺少的 `zc-unknown`，距首包 519–521ms。B 至 J 也都在各自观察到末包后收到 A 已知的两条 PTR，Avahi 为 104–115ms，zeroconf 为 519–521ms。三轮 A 单独查询对照中，两种响应器均省略 A 已知的 PTR，`zc-unknown` 在 126–160ms 到达。[原始观测](evidence/linux-tc-ten-queriers-nine-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44919519533)

## 九个查询器叠加链路丢包与乱序

发送侧用九个独立 IPv4 源，接收侧运行 python-zeroconf 0.148.0。接收侧逐份确认 B 至 I 的八份竞争查询均到达。九方都缺少 `zc-unknown`，B 至 I 同时缺少 `zc-known`。netem 仅处理 A 携带 `zc-known` 的续包 2，各场景执行三轮。

| 场景 | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 九个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（27/27），509–510ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（27/27），509–511ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（27/27），509–510ms |

乱序三轮中，续包 2 比末包晚 100–101ms 到达。九轮均在 A 发出末包后收到两条 PTR，表中的时间从发送端探针开始计。响应方向的链路保持正常。[原始观测](evidence/linux-tc-ten-queriers-nine-netem-20261121.json)

## 十一个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机十一个独立 IPv4 源请求同一服务类型。B 至 K 在 A 首包后 18–74ms 发出 QM 查询，A 在 81–83ms 发出声明 `av-known` 和 `zc-known` 的末包。三轮中，十一方均在 A 的末包后收到共同缺少的 `zc-unknown`，距首包 519–521ms。B 至 K 每轮也在各自观察到末包后收到 `zc-known`。

Avahi 在前两轮于 51ms、52ms 回包，均早于 A 的末包。B 至 K 的末包后窗口均未再观测到 `av-known`。第三轮中，B 至 K 均在 86ms 观测到该 PTR，晚于 81ms 的末包。三轮 A 单独查询对照中，zeroconf 均省略 A 已知的 PTR。Avahi 前两轮在末包前返回已知 PTR，第三轮省略该记录。[原始观测](evidence/linux-tc-eleven-queriers-ten-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44920154184)

## 十个查询器叠加链路丢包与乱序

发送侧使用十个独立 IPv4 源，接收侧运行 python-zeroconf 0.148.0。接收侧确认 B 至 J 的九份竞争查询均到达。十方都缺少 `zc-unknown`，B 至 J 同时缺少 `zc-known`。netem 仅处理 A 携带 `zc-known` 的续包 2，各场景执行三轮。

| 场景 | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 十个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（30/30），510–511ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（30/30），509–510ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（30/30），509–511ms |

乱序组中，续包 2 每轮比末包晚 99–100ms 到达。九轮均在 A 发出末包后收到两条 PTR，表中的时间从发送端探针开始计。响应方向的链路保持正常。[原始观测](evidence/linux-tc-eleven-queriers-ten-netem-20261121.json)

## 十二个查询器请求同一条 PTR

2026-11-21（北京时间），Linux 同机十二个独立 IPv4 源请求同一服务类型。B 至 L 在 A 的首包后 18–80ms 发出 QM 查询，A 在 87–89ms 发出声明 `av-known` 和 `zc-known` 的末包。三轮中，十二方均在末包后收到共同缺少的 `zc-unknown`，距首包 519–521ms。B 至 L 每轮也在各自观察到末包后收到了 `zc-known`。

三轮中，A 在 29ms、61ms、62ms 观察到 Avahi 回包，均早于 A 的末包。B 至 L 在末包后的观察窗口中均未见 `av-known`。三轮 A 单独查询对照中，Avahi 也都在末包前回复两条 PTR，zeroconf 均省略 A 已知的 PTR。[原始观测](evidence/linux-tc-twelve-queriers-eleven-netem-20261121.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44920876515)

## 十一个查询器叠加链路丢包与乱序

发送侧使用十一个独立 IPv4 源，接收侧运行 python-zeroconf 0.148.0，并确认 B 至 K 的十份竞争查询均到达。十一方都缺少 `zc-unknown`，B 至 K 同时缺少 `zc-known`。netem 仅处理 A 携带 `zc-known` 的续包 2。

| 场景（各三轮） | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 十一个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（33/33），510ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（33/33），509–511ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（33/33），510–511ms |

乱序组中，续包 2 每轮比末包晚 100–101ms 到达。九轮均在 A 发出末包后收到两条 PTR，表中的时间从发送端探针开始计。响应方向的链路保持正常。[原始观测](evidence/linux-tc-twelve-queriers-eleven-netem-20261121.json)

仍待验证十三个及以上查询器、十二个及以上查询器叠加链路故障、Avahi 的同类隔离链路实验、随机或连续丢包、响应方向的链路故障、两台物理设备、Windows 与 Bonjour 的同类 TC 实验。长期实网与正式发布验收另行跟踪。

复现使用仓库固定 MoonBit 工具链、正在运行的 Avahi daemon、avahi-publish-service 和已安装 tests/interop/requirements.txt 的 Python。脚本会探测主 IPv4，命令中的附加地址需预先配置在同一测试接口上。以下地址为专用 CI 示例。报告位于 `.tools/tc-interop.json`。传入四至十一个附加地址分别运行五至十二查询器，传入三个运行四查询器和续包顺序实验，传入两个运行连续 TC 与三查询器实验，传入一个运行双查询器与首包复测。

```sh
moon build tests/tc_interop --target native
moon run scripts/tc-interop.mbtx -- .venv/bin/python 192.0.2.242 192.0.2.243 192.0.2.244 192.0.2.245 192.0.2.246 192.0.2.247 192.0.2.248 192.0.2.249 192.0.2.250 192.0.2.251 192.0.2.252
```

隔离链路复用上面构建的探针。需有 Linux iproute2、veth、netem 和创建网络命名空间的权限。脚本创建并清理专用命名空间，只在虚拟接口上应用队列规则。报告位于 `.tools/tc-link.json`。可用 `--five`、`--six`、`--seven`、`--eight`、`--nine`、`--ten`、`--eleven` 选择查询器数量，省略时运行单查询器链路实验。

```sh
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --eleven
```

CI 检查发布进程、实验报文语义、普通查询的注册记录、各查询报文的源地址与顺序、竞争查询器各自观察到的末包，以及适用场景的定时器和链路队列计数。时间和抑制字段记录实测值。
