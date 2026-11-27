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

## 十三个查询器请求同一条 PTR

2026-11-22（北京时间），Linux 同机十三个独立 IPv4 源请求同一服务类型。B 至 M 在 A 的首包后 18–86ms 发出 QM 查询，A 在 93–94ms 发出声明 `av-known` 和 `zc-known` 的末包。三轮中，十三方均在末包后收到共同缺少的 `zc-unknown`，距首包 519–521ms。B 至 M 每轮也在各自观察到末包后收到了 `zc-known`。

A 三轮分别在 34ms、34ms、20ms 观察到 Avahi 回包，均早于末包。B 至 M 在各自的末包后窗口中均未观察到 `av-known`。三轮 A 单独查询对照中，Avahi 也都在末包前返回两条 PTR，zeroconf 均省略 A 已知的 PTR。[原始观测](evidence/linux-tc-thirteen-queriers-twelve-netem-20261122.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44985461926)

## 十二个查询器叠加链路丢包与乱序

发送侧使用十二个独立 IPv4 源，接收侧运行 python-zeroconf 0.148.0，并确认 B 至 L 的十一份竞争查询均到达。十二方都缺少 `zc-unknown`，B 至 L 同时缺少 `zc-known`。netem 仅处理 A 携带 `zc-known` 的续包 2。

| 场景（各三轮） | A 的报文到达顺序 | 目标队列每轮通过 / 丢弃 | 十二个套接字收包 |
| --- | --- | --- | --- |
| 无损对照 | 首包 → 续包 1 → 续包 2 → 末包 | 1 / 0 | 两条 PTR 均收到（36/36），509–511ms |
| 定向丢包 | 首包 → 续包 1 → 末包 | 0 / 1 | 两条 PTR 均收到（36/36），509–510ms |
| 将续包 2 延迟 125ms | 首包 → 续包 1 → 末包 → 续包 2 | 1 / 0 | 两条 PTR 均收到（36/36），510–511ms |

乱序组中，续包 2 每轮比末包晚 99–100ms 到达。九轮均在 A 发出末包后收到两条 PTR，表中的时间从发送端探针开始计。响应方向的链路保持正常。[原始观测](evidence/linux-tc-thirteen-queriers-twelve-netem-20261122.json)

## 响应方向丢包、恢复和延迟

2026-11-22（北京时间），在同一 Linux VM 的隔离 veth 两侧运行单查询器和 python-zeroconf 0.148.0。查询器每次发出普通 QM。netem 从响应器侧匹配发往组播组的 IPv4 mDNS 响应，查询方向保持正常。每轮先跑无损对照，再连续查询两次并丢弃两次响应，随后恢复传输重新查询，最后单测 125ms 响应延迟。[原始观测](evidence/linux-tc-response-link-20261122.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44986069774)

| 场景 | 三轮实测 |
| --- | --- |
| 无损对照 | 每轮内核放行一份响应，两条 PTR 在 36–50ms 到达 |
| 连续两次丢包 | 每轮内核分别丢弃两次查询各自的响应，累计 2 份，六次查询均未收到目标 PTR |
| 恢复后重新查询 | 每轮内核放行一份响应，两条 PTR 在 54–121ms 到达 |
| 在响应方向加 125ms 延迟 | 每轮内核放行一份响应，两条 PTR 在 188–230ms 到达 |

时间从对应查询的探针启动起算，包含响应器调度和传输时间。恢复阶段由探针主动发起一次新查询，本实验验证这条链路恢复后可以重新取得答案。

## Browser 自动重试与随机响应丢包

2026-11-22（北京时间），Linux 隔离 veth 上用生产 Browser 订阅一次服务类型，独立解析器记下同源发出的普通 QM 查询。netem 从响应器侧丢弃前两次回答，内核计数确认丢弃两份后解除丢包。探针持续驱动同一 Browser 并检查快照，不额外发查询。两次 CI 各三轮，六轮均在约 1.07s 发出第二次查询，在 3.075–3.080s 自动发出第三次查询，随后在 4.105–4.182s 验证两个目标实例均完整解析。恢复前浏览快照为空。时间相对 Browser 探针启动。[逐轮证据](evidence/linux-tc-browser-retry-random-response-20261122.json) · [首轮 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44986664401) · [复测 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44986753930)

另用单查询器在相同隔离链路上执行 18 次普通 QM，响应方向配置 50% 随机丢包。内核实际放行 7 份、丢弃 11 份，每次查询对应一份响应。7 次放行均在 25–120ms 收到两条 PTR，11 次丢弃均无目标 PTR 到达，最长连续丢弃 5 份。每次由测试探针独立发起查询。50% 为队列配置，此次样本用于核对收到的记录与内核计数。[逐轮证据](evidence/linux-tc-browser-retry-random-response-20261122.json)

## 十二个查询器叠加响应方向故障

2026-11-22（北京时间），十二个独立 IPv4 源通过隔离 veth 查询 python-zeroconf 0.148.0。同一轮中，响应器侧探针逐份核对 A 的四份 TC 报文与 B 至 L 的十一份竞争查询。四种场景各三轮，每轮十五份查询报文均按发送顺序到达。netem 只处理响应器侧回往查询器的组播响应。

| 场景 | 目标队列每轮通过 / 丢弃 | 十二个套接字的收包结果 |
| --- | --- | --- |
| 无损对照 | 1 / 0 | 两条 PTR 均收到（36/36），509–510ms |
| 响应丢包 | 0 / 1 | 均未收到目标 PTR（36/36） |
| 解除丢包后重新查询 | 1 / 0 | 两条 PTR 均收到（36/36），510–511ms |
| 响应方向加入 125ms 延迟 | 1 / 0 | 两条 PTR 均收到（36/36），635ms |

时间从每组发送端探针启动起算。恢复阶段由探针重新发出查询，生产 Browser 的自动重试单独在单查询器场景验证。[逐轮证据](evidence/linux-tc-multi-response-link-20261122.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/45037999182)

## 十二个 Browser 在随机响应丢包下自动重试

2026-11-22（北京时间）在 Linux 隔离 veth 上完成，11 月 23 日归档。十二个生产 Browser 分别使用独立 IPv4 源，各订阅一次服务类型。响应侧为 python-zeroconf 0.148.0，netem 仅对响应方向配置 50% 随机丢包。探针驱动 Browser 并观察同一接口上的 QM 查询及各自快照。八轮共放行 8 份响应、丢弃 8 份。50% 是配置，结果只描述本次样本。[原始观测](evidence/linux-tc-multi-retry-response-reorder-20261123.json) · [专项 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/45038950752)

- 两轮首份响应放行。每轮只观察到一个源发出查询，十二个 Browser 均在 57–103ms 内解析两个实例。
- 六轮首份响应被丢弃。五轮各丢一份，恢复时刻为 2051–2133ms。另一轮连续丢三份，十二个 Browser 均在 4085ms 完成解析。六轮均观察到 Browser 自动重发，并且各轮最终只放行一份组播响应。
- 首份响应被丢弃的六轮中，五轮十二个源均有至少两次可识别的 QM，一轮只有十个源发出至少两次 QM，其余两个各发一次。六轮每个 Browser 最终均完整解析两实例。时间从对应轮次探针启动起算。

## 响应报文乱序

同一隔离链路上用测试探针发送两份带不同 PTR 的 IPv4 组播 mDNS 响应，发送顺序始终为第 1 份、第 2 份，两者相隔 35ms。无损对照三轮的接收顺序均为 1 → 2。仅对第 1 份施加 125ms 延迟后，三轮接收顺序均为 2 → 1，第 1 份比第 2 份晚 90ms。每轮 netem 放行被选中的一份响应、零丢弃，两条目标 PTR 均能由接收端解码。此项使用测试套接字和受控报文。[原始观测](evidence/linux-tc-multi-retry-response-reorder-20261123.json)

## 生产 Browser 聚合乱序响应

2026-11-23（北京时间），Linux 隔离 veth 上发送两份受控 IPv4 组播 mDNS 响应。第一份含浏览 PTR 和一条用于区分报文的地址记录，第二份含实例的 SRV、TXT 和目标 IPv4 地址。发送顺序固定为第一份再第二份。乱序组只给第一份加 125ms 延迟，独立套接字逐份核对来源和到达顺序，生产 Browser 处理同一批报文。[逐轮原始观测](evidence/linux-tc-browser-response-reorder-20261123.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45176653389)

| 到达顺序 | 首份响应后的三轮中间状态 | 两份响应到齐后的三轮结果 |
| --- | --- | --- |
| PTR 先到 | 缓存 2 条记录，显示 1 个未完成实例 | 均完整解析，46–48ms |
| SRV、TXT、地址先到 | 缓存 3 条记录，尚无可见实例 | 均完整解析，136–137ms |

乱序组的 PTR 比第二份响应晚 88–91ms 到达。六轮均恰好接纳两份响应，最终快照都只有一个完整实例，目标地址为 `192.0.2.10`，端口为 `18424`，TXT 为 `stage=split`。时间从接收端探针启动起算。本实验覆盖两份正向响应的聚合。首轮 CI 曾因测试编码器的已知答案约束在发送前退出，改为逐条编码记录后重跑通过。[首轮调试记录](https://github.com/mik1e80/MoonDiscover/actions/runs/45175970888)

### 乱序叠加 SRV 到期和 PTR goodbye

2026-11-27（北京时间），Windows 同机 IPv4 组播用仓库源码构建的 Browser 和独立接收套接字复核两种生命周期场景。测试发送器刻意让 SRV、TXT 和 A 先于 PTR 进入网络，接收套接字按来源、接口、目的地址和报文字节核对每次发送。

- SRV 的 TTL 为 1 秒。三轮延迟 1109–1125 ms 发送 PTR，均只得到缺少 SRV 的未完成实例，补发新 SRV 后均恢复完整解析。
- 三轮均先通过反序到达的正向响应成功解析，再接收 PTR goodbye。发出 goodbye 后 203 ms 补发重复的 SRV、TXT 和 A，接收端确认收到。实例仍在 1000 ms 时按 `goodbye` 移除，新的正向 PTR 均重新触发完整解析。

这六轮覆盖受控到达次序下的 Browser 生命周期。隔离链路注入、独立发布者和跨设备下的同类组合仍待验证。[逐轮数据](evidence/windows-reordered-lifecycle-20261127.json)

## 查询方向随机丢包

2026-11-23（北京时间），Linux 同机隔离 veth 上仅对查询器发往响应器的 IPv4 mDNS 查询配置 50% 随机丢包。三轮各发六次普通 QM，每次独立发起一份查询。响应器侧探针按来源、组播目的地址和报文内容确认是否收到，查询器记录 python-zeroconf 0.148.0 返回的两条目标 PTR。[原始观测](evidence/linux-tc-random-query-loss-20261123.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45178460436)

内核共放行 6 份、丢弃 12 份。6 份放行查询全部在对端出现，查询器均在 23–108ms 收到两条 PTR。12 份被丢弃的查询在对端均未出现，查询器也均未收到目标 PTR。第三轮六份查询全部被丢弃。时间从每次查询的发送端探针启动起算。50% 为内核队列配置，计数描述本次样本。各次查询由测试探针主动发出。

## Browser 在查询方向随机丢包下自动重试

2026-11-23（北京时间），Linux 隔离 veth 上分别运行单个和十二个生产 Browser，每个 Browser 仅订阅一次服务类型。仅在查询方向配置 50% 随机丢包，响应器为 python-zeroconf 0.148.0。发送端和对端按源记录普通 QM，两侧计时采用同一虚拟机的单调时钟。每轮对端实际收到的查询报文数与内核放行计数一致。[逐轮数据](evidence/linux-tc-browser-random-query-retry-20261123.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45182184985)

| 规模 | 查询方向观测 | 最终解析结果 |
| --- | --- | --- |
| 单 Browser，八轮 | 五轮首份查询放行。三轮首份查询被丢弃，同源在 1072–1074ms 自动重发，第二份查询均到达对端 | 首份放行时 97–168ms，首份丢弃时 1099–1171ms。八轮均解析两个实例 |
| 十二个 Browser，八轮 | 八轮首份查询均被丢弃。内核共放行 51 份、丢弃 53 份，每轮对端收到来自 5–9 个源的查询 | 八轮的十二个 Browser 均在 1058–1147ms 完整解析两个实例 |

并发场景中，最先发问的同一个源每轮发两次 QM，其他十一个源每轮各发一次。该源在 1026–1031ms 重发，六轮重发到达对端，两轮均未到达。这两轮十二个 Browser 仍通过共享组播响应完整解析。时间从每轮发送端 Browser 探针启动起算。50% 是配置值，放行和丢弃计数描述本次样本。

## Browser 在双向随机丢包下的重试与解析

2026-11-23（北京时间），同一 Linux VM 内的隔离 veth 两端分别对查询和响应方向配置 50% 随机丢包。先运行单个生产 Browser，再运行十二个独立 IPv4 源的 Browser，各八轮。每个 Browser 只订阅一次，随后由探针驱动其原有调度。对端为 python-zeroconf 0.148.0。查询端记录发包和完整服务快照，对端独立收包计数与查询方向内核放行数逐轮一致。[逐轮数据](evidence/linux-tc-browser-bidirectional-loss-20261123.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45186492892/job/137733347577)

| 规模 | 查询放行 / 丢弃 | 响应放行 / 丢弃 | 7.8s 窗口内的完整解析 |
| --- | --- | --- | --- |
| 单 Browser | 10 / 16 | 4 / 6 | 4/8 轮，1120–3195ms |
| 十二个 Browser | 94 / 89 | 9 / 10 | 8/8 轮均为 12/12，1124–3125ms |

单 Browser 八轮均在 1070–1075ms 发出第二次普通 QM。四轮未在窗口内完整解析，其中两轮全部查询被丢弃，另两轮有查询到达，响应均被丢弃。完成解析的四轮中，有一轮同时观测到查询和响应被丢弃，于 3195ms 恢复。

并发八轮均观测到自动重发。七轮的十二个源都至少发了两次 QM，另一轮只有最先发问的源重发。八轮中实际到达对端的查询来自每轮 5–12 个源，十二个 Browser 最终均解析两个实例。时间从发送端 Browser 探针启动起算。50% 是两侧各自的配置值，样本结果保留每轮实际计数和未完成状态。

## 单 Browser 双向随机丢包 30 秒复测

2026-11-24（北京时间），Linux 同机隔离 veth 上对查询和响应各配置 50% 随机丢包。单个生产 Browser 每轮只订阅一次，两份目标实例均完整解析时结束该轮，未完成时观测满 30s。八轮均核对了内核放行和对端实际查询数。响应器为 python-zeroconf 0.148.0。[逐轮数据](evidence/linux-tc-browser-30s-bidirectional-burst-20261124.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45399469257/job/138463944496)

八轮中七轮完整解析两实例，耗时 132–7102ms。查询方向放行 11 份、丢弃 8 份，响应方向放行 7 份、丢弃 4 份。未完成的一轮共发出五次普通 QM，后四次均为自动重发，最后一次在 15078ms。该轮两份查询到达对端，但两份响应均被丢弃，30s 内无完整解析。成功轮次均在 7.8s 以内。这组八轮与此前 7.8s 实验为独立随机样本。

## 十二个 Browser 的双向突发丢包

同一隔离链路的查询和响应方向起初均配置 100% 丢包。确认查询被丢弃后继续保持至少 500ms，再恢复查询方向。确认至少一份响应被丢弃后，再保持至少 500ms 才恢复响应方向。内核计数与接收侧查询观测共同验证了每轮故障。每个 Browser 仅订阅一次。

三轮在解除故障前每轮均丢弃一份查询和一份响应。恢复后每轮有 24 份查询到达响应器，放行的响应数分别为 2、1、1。三轮的每个 Browser 都至少发出两次普通 QM，并在 3090–3120ms 内完整解析两实例。时间从各轮发送端探针启动起算。[逐轮数据](evidence/linux-tc-browser-30s-bidirectional-burst-20261124.json)

## 单 Browser 双向随机丢包 60 秒复测

2026-11-24（北京时间），同一 Linux VM 内分别对查询和响应方向配置 50% 随机丢包。单个生产 Browser 每轮只订阅一次，完整解析两个实例即结束，未完成时观测至 60s。内核放行的查询数与对端实收数逐轮一致。[逐轮数据](evidence/linux-tc-browser-60s-bidirectional-burst-20261124.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45405462046/job/138484855755)

八轮中五轮在 30s 内解析完成，耗时 97–7108ms。另三轮均在 31074–31084ms 自动发出第六次普通 QM，其中两轮分别在 31150ms 和 31155ms 完整解析。剩余一轮有三份查询通过，对端的三份响应均被丢弃，直至 60s 仍未完成。八轮合计查询放行 18 份、丢弃 10 份，响应放行 7 份、丢弃 11 份。这批样本独立于 30s 复测。

## 十二个 Browser 的 5 秒重叠突发丢包

两侧起初都设置为 100% 丢包。确认查询方向已丢包后，保持至少 5s 再恢复该方向。确认响应方向实际丢包后，再保持至少 5s 才恢复响应方向。每轮至多观察 30s，计时从发送端探针启动起算。

三轮查询方向各丢弃 36 份、放行 13 份，对端逐轮实收 13 份。响应方向分别丢弃 3、3、2 份，恢复后每轮放行一份。十二个 Browser 每轮都至少发出四次普通 QM，并在 15063–15115ms 完整解析两个实例。[逐轮数据](evidence/linux-tc-browser-60s-bidirectional-burst-20261124.json)

## 单 Browser 双向随机丢包 120 秒复测

2026-11-24（北京时间），在同一 Linux VM 的隔离 IPv4 veth 链路上，对查询和响应方向各配置 50% 随机丢包。单个生产 Browser 每轮订阅一次，完整解析两个实例即结束该轮，否则观察满 120 秒。响应器为 python-zeroconf 0.148.0。对端实收查询数与内核放行数逐轮一致。[逐轮数据](evidence/linux-tc-browser-120s-bidirectional-burst-20261125.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45408844808/job/138496822971)

八轮中六轮完整解析，其中五轮在 15.110 秒内完成。第 5、6、8 轮在 63.083–63.085 秒自动发出第七次普通组播查询（QM）。第 6 轮在 63.190 秒完整解析。第 5、8 轮有查询到达对端，但响应全部被丢弃，直到 120 秒仍未完整解析。八轮合计放行 17 份查询、丢弃 14 份，放行 6 份响应、丢弃 11 份。50% 为各方向的配置值，八轮是独立于此前复测的新样本。

## 十二个 Browser 的 10 秒重叠突发丢包

查询和响应方向起初均配置 100% 丢包。查询方向实测丢包后再保持至少 10 秒才开放，响应方向也在实测丢包后再保持至少 10 秒才开放。十二个独立 IPv4 源各订阅一次，每轮最多观察 60 秒。

三轮中每轮开放前均丢弃 48 份查询和 2 份响应，开放后均有 13 份查询到达对端，放行 1 份组播响应。每个 Browser 发出 5–6 次普通 QM，三轮均为 12/12 完整解析两个实例，耗时分别为 31.095、31.130、31.069 秒，均从发送端探针启动起算。[逐轮数据](evidence/linux-tc-browser-120s-bidirectional-burst-20261125.json)

## 单 Browser 双向随机丢包 240 秒复测

2026-11-25（北京时间），在同一 Linux VM 的隔离 IPv4 veth 链路上，对查询和响应方向各配置 50% 随机丢包。对端为 python-zeroconf 0.148.0。生产 Browser 每轮只订阅一次，完整解析两个实例即结束该轮，未完成时最多观察 240 秒。对端实收查询数与内核放行数逐轮一致。[逐轮数据](evidence/linux-tc-browser-240s-bidirectional-burst-20261125.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45558082991/job/139014897548)

八轮均完整解析。第 1 轮在 127.089 秒自动发出第八次普通组播查询（QM），在 127.161 秒完整解析。该轮放行 3 份查询、丢弃 5 份，放行 1 份响应、丢弃 2 份。其他七轮在 0.148–15.148 秒完成。八轮合计放行 11 份查询、丢弃 10 份，放行 8 份响应、丢弃 3 份。50% 是每个方向的配置值，实测计数来自这八轮独立于此前复测的新样本。所有轮次均在 128 秒前完成，持续未解析到 240 秒时的行为仍需单独验证。

## 十二个 Browser 的 20 秒重叠突发丢包

两个方向起初均配置 100% 丢包。确认首份查询被丢弃后，保持至少 20 秒才开放查询方向。确认响应方向已丢包后，再保持至少 20 秒才开放响应方向。十二个独立 IPv4 源各订阅一次，每轮最多观察 120 秒。

三轮中，每轮开放前均丢弃 60 份查询和 2 份响应。开放后均有 13 份查询到达对端，有 1 份组播响应放行。每个 Browser 发出 6–7 次普通 QM。三轮均为 12/12 完整解析两个实例，分别在 63.122、63.068、63.144 秒完成。耗时从每轮发送端探针启动起算。[逐轮数据](evidence/linux-tc-browser-240s-bidirectional-burst-20261125.json)

## 单 Browser 双向随机丢包 480 秒复测

2026-11-25（北京时间），在同一 Linux VM 的隔离 IPv4 veth 链路上，对查询和响应方向各配置 50% 随机丢包。对端为 python-zeroconf 0.148.0。生产 Browser 每轮订阅一次，完整解析两个实例即结束该轮，否则观察至 480 秒。每轮的查询放行数均与对端实收数一致。[逐轮数据](evidence/linux-tc-browser-480s-bidirectional-burst-20261125.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45559848869/job/139020664366)

八轮独立随机样本中，七轮在 0.118–31.195 秒内完整解析。第 1 轮在 255.089 秒自动发出第九次普通组播查询（QM），该轮有 4 份查询到达对端，4 份响应全部被丢弃，到 480 秒仍未解析。八轮合计放行 19 份查询、丢弃 10 份，放行 7 份响应、丢弃 12 份。

另做一轮固定种子验证，查询方向使用种子 22，响应方向使用 393。两个方向全程保持 50% 配置。第 5 次查询放行，其响应丢弃。第 9 次查询在 255.085 秒发出并收到响应，Browser 于 255.172 秒完整解析。该轮放行 2 份查询和 1 份响应，分别丢弃 7 份和 1 份。种子按 Linux netem 的随机序列预先选定，结果单独报告。[netem 实现](https://github.com/torvalds/linux/blob/v6.17/net/sched/sch_netem.c#L277)

## 十二个 Browser 的 40 秒重叠突发丢包

查询和响应方向起初均配置 100% 丢包。确认查询被丢弃后，保持至少 40 秒再开放查询方向。确认响应被丢弃后，再保持至少 40 秒才开放响应方向。十二个独立 IPv4 源各订阅一次，每轮最多观察 240 秒。

三轮中，每轮开放前均丢弃 72 份查询和 2 份响应。开放后每轮有 13 份查询到达对端，放行 1 份组播响应。每个 Browser 共发出 7–8 次普通 QM。三轮均为 12/12 完整解析两个实例，分别在 127.136、127.132、127.149 秒完成。耗时从每轮发送端探针启动起算。[逐轮数据](evidence/linux-tc-browser-480s-bidirectional-burst-20261125.json)

## 单 Browser 双向随机丢包 960 秒复测

2026-11-25（北京时间），在同一 Linux VM 的隔离 IPv4 veth 链路上，对查询和响应方向各配置 50% 随机丢包。对端为 python-zeroconf 0.148.0。生产 Browser 每轮订阅一次，完整解析两个实例即结束该轮，否则观察至 960 秒。各轮查询放行数均与对端实收数一致。[逐轮数据](evidence/linux-tc-browser-960s-bidirectional-burst-20261125.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45568217917/job/139048155199)

八轮独立随机样本中，七轮在 0.178–15.190 秒完整解析。第 8 轮在 511.094 秒自动发出第十次普通组播查询（QM）。该轮有 4 份查询到达对端，但 4 份响应全部被丢弃，到 960 秒仍未完整解析。八轮合计放行 15 份查询、丢弃 19 份，放行 7 份响应、丢弃 8 份。

固定种子补充轮使用查询种子 34、响应种子 393，两个方向全程仍各配置 50% 丢包。第 5 次查询放行，其响应丢弃。第 10 次查询在 511.093 秒发出并收到响应，Browser 于 511.123 秒完整解析。该轮放行 2 份查询和 1 份响应，分别丢弃 8 份和 1 份。种子按 Linux netem 的随机序列预先选定，结果单独报告。[netem 实现](https://github.com/torvalds/linux/blob/v6.17/net/sched/sch_netem.c#L277)

## 十二个 Browser 的 80 秒重叠突发丢包

查询和响应方向起初均配置 100% 丢包。确认查询被丢弃后，保持至少 80 秒才开放查询方向。确认响应被丢弃后，再保持至少 80 秒才开放响应方向。十二个独立 IPv4 源各订阅一次，每轮最多观察 480 秒。

三轮在开放前均丢弃 84 份查询，分别丢弃 3、2、2 份响应。开放后每轮有 13 份查询到达对端，放行 1 份组播响应。每个 Browser 共发出 8–9 次普通 QM。三轮均为 12/12 完整解析两个实例，分别在 255.074、255.076、255.131 秒完成。耗时从每轮发送端探针启动起算。[逐轮数据](evidence/linux-tc-browser-960s-bidirectional-burst-20261125.json)

## 单 Browser 双向随机丢包 1920 秒复测

2026-11-25（北京时间），在同一 GitHub Actions Linux VM 的隔离 IPv4 veth 链路上，查询和响应方向各配置 50% 随机丢包。对端为 python-zeroconf 0.148.0。生产 Browser 每轮订阅一次，完整解析两个实例即结束该轮，否则观察至 1920 秒。各轮的查询放行数均与对端实收数一致。[逐轮数据](evidence/linux-tc-browser-1920s-bidirectional-burst-20261125.json) · [Linux 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/45623224446/job/139236571769)

八轮独立随机样本中，七轮在 0.098–255.115 秒完整解析，包括第 6 轮在 255.115 秒恢复。第 1 轮在 1023.085 秒自动发出第十一次普通组播查询（QM）。该轮有 2 份查询到达对端，两份响应均被丢弃，到 1920 秒仍未完整解析。八轮合计放行 13 份查询、丢弃 18 份，放行 7 份响应、丢弃 6 份。

固定种子补充轮使用查询种子 3514、响应种子 393，两个方向全程各配置 50% 丢包。第 5 次查询放行，其响应被丢弃。第 11 次查询在 1023.092 秒发出并收到响应，Browser 于 1023.138 秒完整解析。该轮放行 2 份查询和 1 份响应，分别丢弃 9 份和 1 份。种子按 Linux netem 的随机序列预先选定，结果单独报告。[netem 实现](https://github.com/torvalds/linux/blob/v6.17/net/sched/sch_netem.c#L277)

## 十二个 Browser 的 160 秒重叠突发丢包

查询和响应方向起初均配置 100% 丢包。确认查询被丢弃后，保持至少 160 秒才开放查询方向。确认响应被丢弃后，再保持至少 160 秒才开放响应方向。十二个独立 IPv4 源各订阅一次，每轮最多观察 960 秒。

三轮在开放前均丢弃 96 份查询，分别丢弃 2、3、2 份响应。开放后每轮有 13 份查询到达对端，放行 1 份组播响应。每个 Browser 共发出 9–10 次普通 QM。三轮均为 12/12 完整解析两个实例，全员完成时间分别为 511.122、511.118、511.171 秒。耗时从每轮发送端探针启动起算。[逐轮数据](evidence/linux-tc-browser-1920s-bidirectional-burst-20261125.json)

仍待验证十四个及以上查询器、十三个及以上查询器叠加链路故障、Avahi 的同类隔离链路实验、不同双向丢包率、其他突发持续时间和相关丢包模型、独立随机样本在 960 秒后的完整解析、超过 1920 秒的恢复、其他并发规模、隔离链路及独立发布者下的乱序和生命周期组合、两台物理设备，以及 Windows 与 Bonjour 的同类 TC 实验。长期实网与正式发布验收另行跟踪。

复现使用仓库固定 MoonBit 工具链、正在运行的 Avahi daemon、avahi-publish-service 和已安装 tests/interop/requirements.txt 的 Python。脚本会探测主 IPv4，命令中的附加地址需预先配置在同一测试接口上。以下地址为专用 CI 示例。报告位于 `.tools/tc-interop.json`。传入四至十二个附加地址分别运行五至十三查询器，传入三个运行四查询器和续包顺序实验，传入两个运行连续 TC 与三查询器实验，传入一个运行双查询器与首包复测。

```sh
moon build tests/tc_interop --target native
moon run scripts/tc-interop.mbtx -- .venv/bin/python 192.0.2.242 192.0.2.243 192.0.2.244 192.0.2.245 192.0.2.246 192.0.2.247 192.0.2.248 192.0.2.249 192.0.2.250 192.0.2.251 192.0.2.252 192.0.2.253
```

隔离链路复用上面构建的探针。需有 Linux iproute2、veth、netem 和创建网络命名空间的权限。脚本创建并清理专用命名空间，只在虚拟接口上应用队列规则。报告位于 `.tools/tc-link.json`。可用 `--five`、`--six`、`--seven`、`--eight`、`--nine`、`--ten`、`--eleven`、`--twelve` 选择查询器数量，省略时运行单查询器链路实验。

使用 `--response` 可运行单查询器的响应方向实验，输出位于 `.tools/tc-response-link.json`。 `--retry` 运行生产 Browser 自动重试实验，报告为 `.tools/tc-retry-link.json`。`--random-response` 运行随机响应丢包实验，报告为 `.tools/tc-random-response-link.json`。 `--multi-response` 运行十二查询器的响应方向丢包、恢复和延迟实验，报告为 `.tools/tc-multi-response-link.json`。 `--advanced-response` 先运行十二个 Browser 的随机响应丢包实验，再运行报文级与生产 Browser 的响应乱序实验，报告为 `.tools/tc-advanced-response-link.json`。 `--random-query` 可运行单查询器查询方向随机丢包实验，报告为 `.tools/tc-random-query-link.json`。 `--query-retry` 和 `--multi-query-retry` 分别运行单个与十二个 Browser 的查询方向随机丢包实验，报告为 `.tools/tc-query-retry-link.json` 和 `.tools/tc-multi-query-retry-link.json`。 `--bidirectional-retry` 与 `--multi-bidirectional-retry` 分别运行单个与十二个 Browser 的双向随机丢包实验，报告为 `.tools/tc-bidirectional-retry-link.json` 和 `.tools/tc-multi-bidirectional-retry-link.json`。 `--bidirectional-30s` 运行单 Browser 30s 复测，`--multi-bidirectional-burst` 运行十二个 Browser 的重叠突发丢包实验。报告为 `.tools/tc-bidirectional-30s.json` 与 `.tools/tc-multi-bidirectional-burst.json`。 `--bidirectional-60s` 运行单 Browser 60s 复测，`--multi-bidirectional-burst-5s` 运行两个方向分别在确认丢包后至少保持 5s 的十二 Browser 实验。报告为 `.tools/tc-bidirectional-60s.json` 与 `.tools/tc-multi-bidirectional-burst-5s.json`。

`--bidirectional-120s` 运行单 Browser 120 秒复测，`--multi-bidirectional-burst-10s` 运行两个方向分别在确认丢包后至少保持 10 秒的十二 Browser 实验。报告为 `.tools/tc-bidirectional-120s.json` 与 `.tools/tc-multi-bidirectional-burst-10s.json`。

`--bidirectional-240s` 运行单 Browser 240 秒复测，`--multi-bidirectional-burst-20s` 运行十二个 Browser 的双向突发丢包实验，两个方向各在确认丢包后再保持至少 20 秒。报告为 `.tools/tc-bidirectional-240s.json` 与 `.tools/tc-multi-bidirectional-burst-20s.json`。

`--bidirectional-480s` 运行单 Browser 八轮随机样本和一轮固定丢包种子的补充实验。两个方向各配置 50% 丢包。 `--multi-bidirectional-burst-40s` 运行十二个 Browser 的双向突发丢包实验，两个方向各在确认丢包后再保持至少 40 秒。报告为 `.tools/tc-bidirectional-480s.json` 与 `.tools/tc-multi-bidirectional-burst-40s.json`。

`--bidirectional-960s` 运行单 Browser 的八轮独立随机样本和一轮固定种子补充实验，查询与响应方向各配置 50% 丢包。`--multi-bidirectional-burst-80s` 运行十二个 Browser 的双向突发丢包实验，两个方向各在确认丢包后再保持至少 80 秒。报告为 `.tools/tc-bidirectional-960s.json` 与 `.tools/tc-multi-bidirectional-burst-80s.json`。

`--bidirectional-1920s` 运行单 Browser 的八轮独立随机样本和一轮固定种子补充实验，查询与响应方向各配置 50% 丢包。`--multi-bidirectional-burst-160s` 运行十二个 Browser 的双向突发丢包实验，两个方向各在确认丢包后再保持至少 160 秒。报告为 `.tools/tc-bidirectional-1920s.json` 与 `.tools/tc-multi-bidirectional-burst-160s.json`。

```sh
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --twelve
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --response
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --retry
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --random-response
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --random-query
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --query-retry
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-query-retry
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-retry
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-retry
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-30s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-60s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst-5s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-120s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst-10s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-240s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst-20s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-480s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst-40s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-960s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst-80s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --bidirectional-1920s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-bidirectional-burst-160s
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --multi-response
sudo --preserve-env=HOME,PATH "$(command -v moon)" run scripts/tc-link.mbtx -- .venv/bin/python "$(git rev-parse HEAD)" --advanced-response
```

CI 检查发布进程、实验报文语义、普通查询的注册记录、各查询报文的源地址与顺序、竞争查询器各自观察到的末包，以及适用场景的定时器和链路队列计数。时间和抑制字段记录实测值。
