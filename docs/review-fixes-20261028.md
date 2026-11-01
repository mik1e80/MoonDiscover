# 顾问审查修复记录

依据用户指定的“mDNS-DNS-SD顾问大师”最近一次报告实施。检查日期：2026-10-28。将报告作为待核验的问题清单，先复现后修改，没有据静态建议直接宣称协议全面通过。

| 项目 | 修改与证据 |
| --- | --- |
| P1 容量误报移除 | 先重建仍有活动订阅和有效缓存证据的旧实例，再纳入新实例；容量只省略新增项并诊断。两类订阅的回归检查稳定快照、无假 Removed、真实 goodbye 后候选补入 |
| P1 PTR cache-flush | DNS-SD 缓存忽略 PTR 上的异常 flush 位，保护同组其他实例及常规 PTR 查询；保留 TTL=0 goodbye 宽限。反向 PTR 唯一 RRSet 刷新不在该缓存声明内 |
| P1 Linux 脚本 | 启动前创建 trace 目录；读取前记录退出码、stdout/stderr、读线程错误、录制存在/字节数/散列；失败仍保留报告 |
| P1 实网复跑 | 干净 a8703be 的 [40645501957](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40645501957) 八项通过；[完整报告](evidence/linux-avahi-20261028.json) |
| P1 状态文档 | README、SCOPE、协议矩阵、CHANGELOG、进度和报名说明统一区分版本及验证层次 |
| P2 版本分离 | v0.1.0 / 2b922d6 不变；main 标为下一功能版本 0.2.0-dev，尚未重新发布到 Mooncakes |
| P2 新增功能验收 | TC/首包问题/后续仅答案/完整性/中途取消和子类型非成员排除/基础身份分别有确定性核心用例；专项独立实现实网另列待验证 |
| P2 环境与长时证据 | 用户已确认暂时没有第二设备；不冒充跨设备完成。继续采用轻量测试，没有以加速虚拟时间冒充长时间实网 |

核心缺陷修复前，三个复现用例全部失败；修复后，相关 12 项 JS 用例通过。后续四项新增协议验收通过。各次只执行与改动相关的文件与过滤器，非所有后端全量测试。

复现核心修复：

```powershell
.\scripts\moon.ps1 test src/engine/capacity_test.mbt src/engine/shared_ptr_test.mbt src/cache/shared_ptr_test.mbt --target js --frozen --filter 'smoke:*'
.\scripts\moon.ps1 test src/engine/multipacket_test.mbt src/engine/subtype_test.mbt src/wire/multipacket_test.mbt --target js --frozen --filter 'smoke:*'
```

共享记录的处理依据 [RFC 6762 §10.2](https://www.rfc-editor.org/rfc/rfc6762.html#section-10.2)。NSEC 实验保存在本机忽略目录中的补丁与测试副本，未进入本轮代码；本轮不升级固定工具链或全局环境。性能报告保留原始单次测量范围，不将它作为当前版本的统计性性能承诺。

## Known-Answer 阶段

顾问规划要求先处理 Known-Answer 容量与超限退化。`e36fe07`、`5eea5a9`、`82a5297` 分别修复数量上限、合法 QM 降级和回放当帧诊断。相关 9 项 JS 检查、Native CLI 编译、6 项离线检查通过，公开接口无变化。

代码提交 `82a5297` 的[轻量 CI](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654335009)成功（45 项 JS smoke）；[Avahi 闭环](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654334969)八项通过。详细边界、复现命令和后续阶段见[开发路线](development-roadmap.md)。0.2.0-dev 仍未发布。

状态说明：本记录早期文字曾把另一轮对话中的“报名完成”误套用到本项目；用户已澄清本项目尚未报名，计划报名 11 月赛，当前记录不代表已提交或通过审核。
