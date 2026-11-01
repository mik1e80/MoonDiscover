# MoonDiscover 项目说明

十一月报名准备入口：[一页申报书](proposal-november-2026.md)、[固定基线与新增贡献](november-baseline.md)。本页保留详细项目说明。

仓库：[mik1e80/MoonDiscover](https://github.com/mik1e80/MoonDiscover)。模块名：`mik1e80/dnssd`。许可：Apache-2.0。状态：2026-11-01，已发布 0.1.0；main 为 0.2.0-dev，含尚未发布的新功能和修复。本项目尚未报名，用户计划报名 11 月赛。所有能力按版本与证据区分，不宣称完整 RFC 或所有平台验收。

## 解决的问题

局域网服务的端口和地址会变化。应用可以通过 `_http._tcp.local.` 等 DNS-SD 类型发现实例，再拿到 SRV、TXT 与地址，跟踪属性变化、goodbye 和缓存到期，而不把端点写死在代码里。

MoonDiscover 用 MoonBit 实现发现所需的报文、缓存、查询与状态引擎。Native 层提供指定 IPv4 接口的真实组播收发，纯核心可在没有局域网和系统 socket 的环境中回放相同输入。

## 三个完整使用场景

| 场景 | 调用方输入与动作 | 实际输出与验证入口 |
| --- | --- | --- |
| 本地开发 HTTP 服务连接 | 应用知道 `_http._tcp.local.` 和受控 demo token，主动发现服务并请求约定路径 | 得到目标、地址、动态端口与 TXT；`examples/http_connect` 使用发现结果请求 `/moondiscover-demo` 并验证 body，实网报告保存请求记录 |
| 桌面伴随程序持续连接 | Native `Browser.browse` 订阅应用约定的服务类型，按事件维护连接候选；取消时释放浏览器 | 首次解析、TXT 更新、goodbye 移除以及取消后 socket 重开已有受控实网证据；`examples/watch_events` 展示公开 API 持续事件 |
| 局域网服务盘点与离线排查 | CLI 浏览一个或多个指定类型并 `--record`，随后 CLI 或浏览器加载 JSONL | 输出范围、实例、端点、二进制 TXT、完整性和变化原因；固定时间与种子回放可重现该次服务事件，公开 fixture 可离线复核 |

第三个场景只盘点调用方明确订阅的类型，不代表自动枚举所有服务。第二设备互通尚未验证，以上实网范围均为同机独立进程。

## 可检查的成果

- 原始标签字节与二进制 TXT，保留实例内点、flag/empty、重复键语义。
- 范围隔离的 TTL 缓存、goodbye/cache-flush 宽限、部分与完整服务、连续生命周期事件。
- QM 查询抖动、退避、TTL 刷新、Known-Answer、指定实例解析超时与取消；多包扩展按 main 的边界单独列出。
- Native Browser、四个 CLI 命令、实时 JSONL、原始报文录制和固定种子确定性回放。
- 使用发现端点的 HTTP 示例，未通过 Python 发现库代替 MoonBit 内部逻辑。
- 按实际功能与修复逐步提交的 Git 历史、固定版本工具链和轻量 CI。
- main 新增子类型浏览与有界多包 Known-Answer，已分别验证成员筛选、身份复用、TC/问题位置/答案完整性与中途取消；专项实网互操作仍待补。
- main 新增 SRV 优先级与固定种子权重候选顺序、公开候选快照、受支持 DTO 记录的原子校验、恶意报文/共享主机生命周期回归，以及 Native 稳定传输错误分类和失败关闭行为。
- CI 明确执行类型检查、格式检查和生成接口无差异检查；这些改进尚未发布到 Mooncakes。

## 演示与证据

从 [README](../README.md) 构建 CLI 后，可用 `replay --file fixtures/live-20261024.jsonl` 离线查看筛选后的真实录制。该样本来自 Windows 上的独立 python-zeroconf 发布进程，服务与 HTTP 端点由测试脚本创建。

[Windows 报告](evidence/windows-live-20261024.json)记录了 8 项通过检查：主动发现、动态端口 HTTP 请求、TXT 更新、goodbye 移除、所有受控进程成功退出、异步取消关闭、录制回放确定性、实网与回放服务事件一致。报告包含源提交、工作树状态、二进制散列和事件时间线。复现脚本为 `tests/interop/live_smoke.py`，轻量测试和来源说明见 [验证文档](verification.md)。

## 支持范围与后续工作

Windows 证据来自同机独立 zeroconf 进程。main 另有[同 Linux VM 的 Avahi 0.8 实网报告](evidence/linux-avahi-20261028.json)，发现、HTTP、更新、goodbye、取消与回放共八项通过；它不回填为已发布 0.1.0 包的 Linux 验证。尚无第二设备、Bonjour 或长时间实网运行证据。多包 Known-Answer 和子类型仍缺专项独立实现互操作报告。

实时传输仍为 IPv4 QM 组播，单播接收排除。未实现发布者、IPv6 组播、NSEC 负缓存、自动接口切换与跨响应批次的 SRV RRSet 重组。main 的容量、异常 PTR、防御性 DTO 校验与 SRV 候选选择均有回归；具体契约和限制见 [SCOPE.md](SCOPE.md) 与 [SRV 选择说明](srv-selection.md)。

Mooncakes 0.1.0 已实际发布，[源码标签](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/tree/v0.1.0)对应 `2b922d6`。无 `moon.work` 源码映射的新工程已从注册表安装、运行公开核心 API、编译 Native 并打开/关闭 socket；归档散列及全部 116 个安装文件匹配。详见[发布记录](evidence/release-0.1.0-20261024.json)和[消费记录](evidence/consumer-registry-20261024.json)。

## 11 月参赛准备说明

已发布的 `0.1.0` 是既有项目基线。main 在 2026-11-01 形成的新增工作包括 SRV 候选选择与快照、记录接纳边界校验、协议状态回归、Native 错误/关闭语义和更明确的 CI 检查。它们与原有功能分开记录，不将旧版本工作重复写成新成果。Known-Answer 多包已有独立解析器核心验收，专项实网互操作仍待补；50/200/500 个合成服务已有三轮本机观察，不代表更大规模或长期压力。具体报名入口、规则和提交范围须等官方 11 月公告确认；本说明本身不是报名提交。
