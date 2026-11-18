# 驳回意见整改记录与验收门槛

本轮严格针对顾问最后一轮计划：补查询端必要协议行为，不能用排除 NSEC、删功能或宣传话术代替实现。开发版本改为 0.3.0-dev，稳定 0.3.0 尚未发布。

## 已改代码和材料

- Type 47 受限位图、不同 next-name 兼容、畸形 NSEC 单条隔离，保留整体 DNS 结构校验；独立历史 zeroconf 抓包更新断言。
- 独立有界负缓存及正负一致性，scope/name/IN/type 隔离、正向优先、TTL 到期恢复；共享 PTR 继续查询；Native 和 Replay 使用同一核心链。
- Engine/Browser 否定证据接口；Additional、正向救回、flush、容量失败、Replay 确定性测试；NSEC 加入 Wire 变异语料。
- 独立 zeroconf 实际 UDP NSEC 专项：Windows 本机已收到 9 条 NSEC 并观察 6 次负证据；Linux 新入口结果由 CI 决定，不能以编译成功代替互通。首次 Avahi 地址发布实验没收到 NSEC，因此更换独立发布者，没有放松断言。
- README 写明项目对象、角色、必要功能、格式/传输/认证边界、RFC 参考和许可证责任；NSEC 文档、范围表、协议矩阵与申报版本同步。
- 桌面 Markdown 申报书仅更新过时内容；保留基本信息、标题层级和其他列表；按用户要求核心功能改为一句话，未增加表格。原稿仅保存在本地忽略目录，个人联系信息不提交公开仓库。

## 完整计划尚需满足的验收

尚不能把顾问计划的所有验收标为完成：物理时间到期后发布者新增记录的恢复、完整多 responder 抑制/等待验证、长期实网证据，以及 0.3.0 发布/注册表独立消费。Windows 新增 NSEC 收包已验证，但否定状态是在实际录制内回放复核，不能宣称全部八类场景均有独立 Windows 实网验收。用户要求轻量测试，小时级实网不在本轮执行。第二物理设备、Bonjour 仍需外部环境；不以同 VM 实验替代。

最终 0.3.0 门槛：必要查询端条款逐项核对并有证据，八类否定响应场景有完整专项，独立报文与实网报告可复现，所有当前 API 外部消费通过，许可/归档/标签一致，注册表独立安装成功后再标稳定发布。以上是明确的完成要求，而不是将必要功能永久放在可选范围之外。

本轮本机初验：71 项定向 JS 用例通过（包括额外位图和 8 轮缓存更新/到期循环），Native check 与 protocol_live/nsec_probe 构建通过。760525b 的 Windows/Linux 轻量 CI 已通过，Linux 普通 Avahi 八项闭环通过；其新增 Avahi NSEC 实验失败已如实保留。修正后的最终提交与 CI 状态应结合 GitHub Actions 的实际记录，不通过则继续修复。历史报告不改写成新版本验证。

1f60451 的[双平台轻量 CI](https://github.com/mik1e80/MoonDiscover/actions/runs/44249938921)和[Linux 独立互通](https://github.com/mik1e80/MoonDiscover/actions/runs/44249939017)均成功；后者使用 zeroconf 检查 NSEC，并继续完成 Avahi/接口专项。[Linux NSEC 日志摘要](evidence/linux-nsec-20261118.json)提取原始 job stdout；[Windows NSEC](evidence/windows-nsec-20261118.json)与[Windows 实网](evidence/windows-live-20261118.json)保留本机报告。Windows 实验核心基线 760525b、解析探针来自 1f60451，trace SHA256 为 75c59a266feaa5790838a81b25d8127174d6f375b2e111f763dbe09dc80a1f48。两平台各观测 9 条 NSEC、6 次有效负证据，均不代表完整独立解码器对拍或所有否定场景的实网验收。
