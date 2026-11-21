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

仍待验证四个及以上查询器、重排和丢包、两台物理设备、Windows/Bonjour 实网及其他响应器版本。长期实网与正式发布验收另行跟踪。

复现使用仓库固定 MoonBit 工具链、正在运行的 Avahi daemon、avahi-publish-service 和已安装 tests/interop/requirements.txt 的 Python。三个查询器实验要求同一接口上的三个不同 IPv4 地址。以下两个附加地址为专用 CI 示例。生成报告位于 .tools/tc-interop.json。省略第三个地址时运行上一节的双查询器与首包复测。

```sh
moon build tests/tc_interop --target native
moon run scripts/tc-interop.mbtx -- .venv/bin/python 192.0.2.242 192.0.2.243
```

CI 检查发布进程、实验报文语义、普通查询的注册记录、双源报文顺序及定时器观测数量。时间和抑制字段记录实测值。
