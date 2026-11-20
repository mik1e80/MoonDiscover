# 两种独立 mDNS 响应器的 TC 续包实验

本次在同一 Linux CI 虚拟机上运行 Avahi 0.8 与 python-zeroconf 0.148.0 两种独立实现。每个响应进程独占两个服务实例，一条 PTR 用作 Known-Answer，一条作为未知成员。两个响应器使用同一测试接口，按唯一登记的 PTR 目标归属，不按源 IP 推断。网络路径是实际 IPv4 组播 UDP。

普通 QM 查询必须收到四条匹配 PTR。后续场景间保留安静期并清空接收队列。独立测试解析器验证 TC 首包有问题、末包无问题且携带两条 Known-Answer。探针从首次发送前开始用单调时钟计时，记录每个匹配 PTR 的首次接收时间。延迟续包人为制造可辨别的观测窗口，产品发送路径仍需按 RFC 6762 §7.2 紧接首包发送续包。[RFC 6762 §7.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-7.2)

| 场景 | Avahi 0.8 | python-zeroconf 0.148.0 |
| --- | --- | --- |
| 普通查询 | 24ms 收到两条 PTR | 27ms 收到两条 PTR |
| 单包带 Known-Answer | 24ms 收到未知 PTR，观测窗内无已知 PTR | 94ms 收到未知 PTR，观测窗内无已知 PTR |
| 立即 TC 续包 | 100ms 收到未知 PTR，观测窗内无已知 PTR | 70ms 收到未知 PTR，观测窗内无已知 PTR |
| 首包后 252ms 发续包 | 99ms 已收到两条 PTR，早于续包 | 274ms 收到未知 PTR，观测窗内无已知 PTR |
| 仅发 TC 首包 | 99ms 收到两条 PTR | 564ms 收到两条 PTR |

该次运行确认了两种独立响应器能在同一链路同时供同一个查询器发现，且立即续包都观察到了按记录抑制。延迟续包区分了两种实现在此次运行中的表现。接收时刻包含响应调度及进程唤醒，仅是一次运行的数据。400–500ms 窗口仍待更细粒度的计时和重复验证。多查询器同时等待同一答案、第二物理设备、其他响应器版本和网络环境均未覆盖。[原始观测](evidence/linux-two-responder-tc-20261120.json) · [GitHub 专项](https://github.com/mik1e80/MoonDiscover/actions/runs/44744493713)

复现使用仓库固定 MoonBit 工具链、正在运行的 Avahi daemon、avahi-publish-service 和已安装 tests/interop/requirements.txt 的 Python。在 Linux 测试环境构建探针，再启动实验。生成的报告位于 .tools/tc-interop.json。

```sh
moon build tests/tc_interop --target native
moon run scripts/tc-interop.mbtx -- .venv/bin/python
```

CI 失败条件是任一发布进程异常、实验报文语义校验失败或普通查询缺少注册记录。时间及抑制字段保留实际输出，工作流的成功状态表示获得有效实验对照。
