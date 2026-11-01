# 专项组播与接口恢复验证

2026-11-01，在源码 `5f246ea54a1e4f541fac2b16508fda3e460e68b4` 的干净 Linux GitHub runner 上完成。对应 [CI 41296198257](https://github.com/mik1e80/MoonDiscover/actions/runs/41296198257) 成功；普通 Avahi 八项闭环也在同一轮通过。

| 专项 | 实际方法与结果 | 原始证据 |
| --- | --- | --- |
| 多包 Known-Answer | Engine 生成 260 条 PTR 答案，实际发往 IPv4 组播，由第二个 socket 接收；独立测试解析器核对 2 个报文、TC 链、首包问题、后续答案和完整顺序 | [Linux 协议报告](evidence/linux-protocol-20261101.json)，含完整十六进制报文 |
| 取消与降级 | 发送首包后取消仍有 2 个待发尾包的订阅，待发计数归零且 250ms 接收窗口没有该查询；过大的 TXT Known-Answer 仍经 UDP 发出合法普通 QM 并产生诊断 | 同上 |
| 子类型与共享身份 | Avahi 独立发布 printer / scanner 两种子类型；订阅 printer 时排除 scanner，随后增加基础类型得到两个完整服务；printer 仅一次 Seen / Resolved；取消基础订阅仍保留 printer | 同上 |
| 接口失效与恢复 | 独立 Linux network namespace 内创建 dummy 网卡，先接收服务，再删除地址；检测 InterfaceUnavailable、关闭并清空旧缓存、拒绝打开不存在地址；恢复地址后创建新 scope、重建订阅并再次解析 | [接口恢复报告](evidence/linux-interface-recovery-20261101.json) |

源码入口为 [protocol_live](../tests/protocol_live)；[protocol-live.mbtx](../scripts/protocol-live.mbtx) 编排实验，固定 async 0.22.5。测试解析器位于 `tests/protocol_probe`，不调用生产 wire decoder。接口实验在修改网卡前比较当前与 PID 1 的 network namespace；相同时拒绝运行。它不修改用户物理网卡。

运行环境与复现步骤见 [.github/workflows/linux-interop.yml](../.github/workflows/linux-interop.yml)。仅有 Linux、Avahi、iproute2 和相应权限的隔离环境才能执行接口项。

边界：这是同一 Linux VM 的真实 UDP 和独立发布者实验，不是第二物理设备或 Bonjour 验证。Known-Answer 专项证明实际传输字节和取消/降级，不证明 Avahi 对所有 Known-Answer 抑制/等待行为的完整规范符合性。接口项验证应用关闭并重建 Browser，不实现自动迁移；也不等同于 Wi-Fi 断连、DHCP 或操作系统全部链路通知场景。

原始接口报告中的 `ci_run_url` 因 sudo 环境未继承而为空路径；其来源由下载的同一工作流 artifact 核实。artifact ID、散列与来源关联保存在[证据清单](evidence/linux-specialized-manifest-20261101.json)，原始结果未改写。
