# MoonDiscover

**用 MoonBit 发现局域网服务，获取动态地址、端口和属性，并持续跟踪服务变化。**

MoonDiscover 是 mDNS / DNS-SD 服务浏览与解析库，模块名 `mik1e80/dnssd`，采用 [Apache-2.0](LICENSE) 许可。应用只需知道约定的服务类型，例如 `_http._tcp.local.`，就可以查询实例、目标主机、端口、TXT 属性和 IP 地址，减少手工填写与写死端点的需要。

项目包含纯 MoonBit 协议核心、Native IPv4 组播适配层、命令行工具，以及录制和离线回放功能。**当前适合在明确支持范围内接入服务发现；0.2.0-dev 仍在加固，尚未发布，不宣称完整 RFC 或所有平台支持。**

[项目作用](#项目作用) · [版本选择](#版本选择) · [安装与构建](#安装与构建) · [命令行使用](#命令行使用) · [作为库使用](#作为库使用) · [使用边界](#使用边界) · [常见问题](#常见问题) · [验证与文档](#验证与文档)

## 项目作用

### 解决什么问题

局域网服务可能因 DHCP、重启或动态分配而改变地址和端口。MoonDiscover 让应用按“服务类型 → 实例 → 主机与端口 → 地址”取得当前发现结果，并在记录变化时收到事件。

- **mDNS**：在本地链路上使用组播传递 DNS 查询和响应。
- **DNS-SD**：通过 PTR、SRV、TXT 等记录描述服务实例、端点与属性。
- **MoonDiscover**：实现本项目支持的报文处理、TTL 缓存、服务聚合、查询调度和事件生命周期；Native 层负责真实网络收发。

例如，你知道局域网内有一个发布了 `_http._tcp.local.` 的受控 HTTP 服务，却不知道它当前监听哪个端口。MoonDiscover 可以取得它的实例、SRV 端口和地址，再由你的 HTTP 客户端连接。发现本身不会创建、发布或启动这个 HTTP 服务。

### 适合哪些场景

| 场景 | 应用如何使用 | 对应入口 |
| --- | --- | --- |
| 本地开发工具、测试设备的 HTTP 连接 | 订阅约定类型，根据 TXT 筛选实例，使用发现的地址和动态端口 | [HTTP 示例](examples/http_connect/main.mbt) |
| 桌面伴随程序或设备面板 | 维护服务列表，响应新增、解析完成、属性更新、暂不可用和移除 | [连续事件示例](examples/watch_events/main.mbt) |
| 指定类型的局域网服务盘点 | 浏览一个或多个已知类型，逐行输出 JSON，交给其他程序处理 | CLI `browse` |
| 故障复现、协议调试与教学 | 保存原始响应和时间，在没有网络时重放同一输入 | `--record`、`replay`、[离线页面](examples/browser_replay/README.md) |
| 自定义运行时或传输适配 | 自行提供时钟、scope、收包与发包逻辑 | 纯核心 `Engine` 和 `Replay` |

盘点范围由调用方订阅的类型决定，目前没有自动枚举整个局域网所有服务的功能。完整场景见 [项目说明](docs/submission.md)。

### 工作方式

```mermaid
flowchart LR
  P[局域网中已有的服务发布者] <-->|IPv4 mDNS 组播| N[Native Browser]
  N <--> E[纯 MoonBit Engine]
  E --> S[快照与生命周期事件]
  S --> A[你的应用或 CLI]
  N --> T[JSONL 录制]
  T --> R[离线 Replay]
  R --> E
```

根包不依赖系统 socket。Native Browser 将系统接口、单调时钟和网络收发接到同一个核心；浏览器 JavaScript 示例处理离线录制，不扫描局域网或发送待发查询。

## 版本选择

状态更新：**2026-11-01**。已发布版本和开发分支具有不同能力和证据。

| 项目 | Mooncakes `0.1.0` | `main` / `0.2.0-dev` |
| --- | --- | --- |
| 获取方式 | `moon add mik1e80/dnssd@0.1.0` | 克隆本仓库；尚无该开发版本的注册表发布 |
| 基础能力 | 名称/TXT、有限 codec、缓存、聚合、QM、browse/resolve、Native IPv4、CLI、录制/回放 | 包含基础能力及后续修复 |
| 子类型浏览 | 未实现 | 已实现，专项核心用例通过；专项实网互操作待完成 |
| Known-Answer | 有界单包 | 最多 64 包，增加容量边界、普通 QM 降级与诊断修复；Engine 实际出站字节另由独立测试解析器验收，专项实网仍待验证 |
| SRV 候选 | 基础解析 | 按优先级与固定种子权重顺序提供候选列表，详见 [选择契约](docs/srv-selection.md) |
| 输入与 Native 生命周期 | 不包含后续修复 | DTO 缓存接纳原子校验；稳定传输错误代码和关闭行为回归 |
| 容量与异常 PTR flush 修复 | 不包含后续修复 | 已修复并加入回归 |
| 逻辑状态观测 | 不包含后续 `Engine.stats()` 扩展 | 提供缓存、服务、查询和队列等计数 |
| 验证范围 | Windows 同机独立 zeroconf 发布者、实际注册表消费 | 另有同 Linux VM 的 Avahi 闭环与新增核心回归 |

`v0.1.0` 固定到发布源码 `2b922d6`，标签和归档保持原样。[GitHub Release](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/releases/tag/v0.1.0) 提供已校验的模块 ZIP；[注册表消费报告](docs/evidence/consumer-registry-20261024.json)保存下载散列及安装文件匹配结果。

需要已发布依赖时使用固定 `0.1.0`，并了解表中的旧版本边界；需要 main 的新功能和修复时使用源码并固定提交。下面仓库内的构建和 CLI 命令面向当前 main，不能由安装旧包推断已取得这些修复。差异见 [CHANGELOG](CHANGELOG.md) 和 [支持矩阵](docs/SCOPE.md)。

## 安装与构建

### 在已有 MoonBit 工程中安装发布包

```text
moon add mik1e80/dnssd@0.1.0
```

| 导入入口 | 用途 | 环境要求 |
| --- | --- | --- |
| `mik1e80/dnssd` | 名称、TXT、报文、Engine、事件、Replay | 无系统网络依赖；可用于 JS 离线处理 |
| `mik1e80/dnssd/src/native` | 真实 IPv4 组播 socket 和 Browser | Native 后端及系统 C 工具链 |

模块使用 `moonbitlang/async@0.22.5`。消费工程若直接导入 async 包，应将它作为自己的依赖声明。精确公共 API 见 [根包接口](pkg.generated.mbti)、[Engine 接口](src/engine/pkg.generated.mbti)和 [Native 接口](src/native/pkg.generated.mbti)；main 的接口文件描述开发源码。

### 获取开发源码

```text
git clone https://github.com/mik1e80/MoonDiscover.git moondiscover
cd moondiscover
```

固定工具链为 `moon 0.1.20261023` / `moonc v0.10.17+d971670cd`，依赖 `async 0.22.5`，见 [toolchain.json](toolchain.json)。旧工具链可能无法读取依赖配置，建议使用已验证的固定版本。

#### Windows / PowerShell

构建 Native 前需要 Visual Studio C++ 构建工具和 Windows SDK。首次准备需要网络；仓库脚本把固定 MoonBit 安装到项目 `.tools/moon`，不替换全局安装。

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 run examples/encode_query --target js --frozen
.\scripts\moon.ps1 build cmd/moondiscover --target native --frozen
```

离线示例只编码、解码 QM 查询，不要求有服务在线。Windows CLI 位于：

```text
_build/native/debug/build/cmd/moondiscover/moondiscover.exe
```

#### Linux

需要可用的 C 编译工具链。以下安装和构建方式与 Linux CI 一致，使用当前用户的 `~/.moon`：

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- '0.10.17+d971670cd'
export PATH="$HOME/.moon/bin:$PATH"
moon update
moon build cmd/moondiscover --target native --frozen
./_build/native/debug/build/cmd/moondiscover/moondiscover --help
```

Avahi 和 python-zeroconf 是互操作实验中的独立发布者，不是 MoonDiscover 浏览器的运行时依赖。实时浏览要求网络中确有发布对应类型的服务。

## 命令行使用

下面以 PowerShell 为例。**把 `192.168.1.10` 换成本机活动网卡的 IPv4 地址**；它不是待发现服务的地址或网关。Linux 使用构建出的同名二进制和相同参数。

```powershell
$cli = '.\_build\native\debug\build\cmd\moondiscover\moondiscover.exe'
& $cli --help
& $cli --version
```

### 1. 检查本机接口和共享绑定

```powershell
& $cli doctor --interface 192.168.1.10
```

`doctor` 打开两个共享绑定 socket，输出接口索引与检查结果。成功说明本地接口与绑定路径可用，不能证明组播响应可达，也不证明网络中已有对应服务。

### 2. 浏览指定类型

```powershell
& $cli browse --interface 192.168.1.10 --service _http._tcp.local. --duration-ms 5000
```

用逗号可在同一次运行中订阅多个类型：

```powershell
& $cli browse --interface 192.168.1.10 --service '_http._tcp.local.,_ipp._tcp.local.' --duration-ms 10000
```

main 支持子类型。下面只观察声明了相应子类型成员关系的 HTTP 实例，返回身份仍属于基础服务类型：

```powershell
& $cli browse --interface 192.168.1.10 --service _printer._sub._http._tcp.local. --duration-ms 5000
```

服务类型由你的业务约定；示例名称不会自动发布服务。订阅 `_ipp._tcp.local.` 也不代表本项目实现了打印协议客户端。

### 3. 解析已知实例

```powershell
& $cli resolve --interface 192.168.1.10 --instance 'Demo._http._tcp.local.' --duration-ms 5000
```

把 `Demo...` 换成实际完整实例名。该路径直接查询指定实例，不依赖先收到 PTR。未在窗口内解析完成时返回非零退出码；`browse` 空结果只表示窗口内未观察到服务。

CLI browse/resolve 的时长范围为 `1..3600000` 毫秒，默认 5000。CLI 使用有限运行窗口；应用中管理订阅生命周期可使用 Browser API。

### 4. 录制与离线回放

```powershell
& $cli browse --interface 192.168.1.10 --service _http._tcp.local. --duration-ms 5000 --record trace.jsonl
& $cli replay --file trace.jsonl
```

`resolve` 也支持 `--record`。录制保存配置、随机种子、命令、时间和原始接收报文，正常完成后写入文件。请先创建目标父目录；强制终止进程可能无法得到完整录制。

回放不需要接口或在线服务，不会发送输出中的 `outbound` 报文。有 `config` 首帧时自动恢复种子；显式 `--seed` 必须与配置一致。相同输入、时间和种子可复现同一核心的结果，不代表服务当前仍在线。

无需实网即可加载受控样本：

```powershell
& $cli replay --file fixtures/live-20261024.jsonl
```

录制可能包含同接口其他服务的名称、地址和 TXT，分享前应检查。公开 fixture 已筛选为本项目受控服务相关报文，来源见 [fixtures](fixtures)。

### 5. 理解 JSONL 输出

CLI 向 stdout 实时逐行输出 JSONL，可保存或交给程序解析。服务事件中的 `service` 包含：

| 字段 | 含义 |
| --- | --- |
| `scope` | 当前接口/网络运行范围；同名实例跨 scope 不合并 |
| `service_type`、`instance`、`instance_label` | 基础类型、可逆实例名、用于展示的首标签 |
| `target`、`port`、`addresses` | 当前发现的主机、端口和地址；尚缺的值可能为 null/空数组 |
| `txt_entries_hex` | 原始 TXT 条目十六进制，保留任意二进制内容 |
| `complete`、`missing` | 当前记录链是否完整，以及缺失/冲突项 |
| `remaining_ttl_ms` | 当前快照的剩余缓存有效期 |

| 事件 | 含义与调用方处理建议 |
| --- | --- |
| `seen` | 首次观察实例，可能为部分状态，可先显示在列表中 |
| `resolved` | 记录链首次完整，可按业务规则选择连接候选 |
| `updated` | 内容变化，重新评估 TXT、端点或连接候选 |
| `unavailable` | 已观察实例失去完整性，暂缓依赖完整端点的操作 |
| `removed` | 不再属于当前观察结果，按原因更新列表 |
| `diagnostic` | 解析、容量、队列或查询降级信息，查看 `code` / `detail`；代码表见[诊断目录](docs/diagnostics.md) |
| `resolve_timeout` | 指定实例的初次解析超时 |

重复响应或仅刷新 TTL 不单独制造内容更新事件。CLI 还会输出 `summary`、录制结果或 `error`；回放也可能输出订阅和待发查询。按 `event` 分派，不能假定每行都有 `service`。完整定义见 [JSON 序列化](src/replay/json.mbt)。

## 作为库使用

### 纯核心：无需网络的最小例子

在消费包 `moon.pkg` 导入根包，下面为可执行包配置：

```text
import {
  "mik1e80/dnssd",
}

pkgtype(kind: "executable")
```

`main.mbt`：

```moonbit
fn main raise {
  let name = @dnssd.DnsName::from_utf8_labels(["_http", "_tcp", "local"])
  let packet = @dnssd.qm_query(name, 12)
  let decoded = @dnssd.decode_packet(packet)
  println(
    "QM PTR query: \{decoded.questions[0].name.to_presentation()} (\{packet.length()} bytes)",
  )
}
```

与 [examples/encode_query](examples/encode_query/main.mbt) 一致，可用 JS 后端运行。它仅构造和读取查询；实际发现应使用 Native Browser 或为 Engine 接入自己的传输。

### Native：订阅真实网络事件

完整示例使用 [watch_events 的包配置](examples/watch_events/moon.pkg)，导入根包、`src/native`、async/stdio/socket/env，并限定 Native 后端：

```moonbit
async fn main {
  let args = @env.args()
  guard args.length() == 3 else {
    fail("usage: watch_events <interface-ipv4> <service-type>")
  }
  let interface = @socket.Addr::parse(args[1] + ":0")
  guard !interface.is_ipv6() else { fail("IPv4 required") }
  let browser = @native.Browser::open(interface.ip())
  defer browser.close()
  let _ = browser.browse(@dnssd.DnsName::parse(args[2]))
  browser.run(5000, event => {
    @stdio.stdout.write(@dnssd.event_json(event).stringify() + "\n")
  })
}
```

在仓库根目录运行这个五秒示例：

```powershell
.\scripts\moon.ps1 run examples/watch_events --target native --frozen -- 192.168.1.10 _http._tcp.local.
```

Browser 提供 `browse`、`resolve`、`cancel`、同步有界 `poll`、异步 `run`、`snapshots` 和幂等 `close`。保存 browse/resolve 返回的订阅 ID，以便取消。`run` 结束、错误或异步取消时关闭 Browser；再次观察需要重新打开。同步轮询调用方应持续 poll 并负责 close；不要在同一个 Browser 上并发驱动 poll/run。

库的 resolve 超时覆盖初次解析；成功后继续订阅变化，直到 cancel/close。HTTP 示例按 TXT demo token 选择受控服务，再请求发现的 IPv4 和端口；它不是通用 HTTP、打印或数据库客户端。

### 自行集成 Engine

Engine 不读取系统网络或时钟。自定义集成需要完成以下闭环：

1. 创建 Engine，设置所需容量和随机种子。
2. 调用 `browse` 或 `resolve`，提供明确 scope 和单调 `Int64` 毫秒时间。
3. 用 `ingest` 输入收包；按 `next_deadline()` 推进 `advance`，没有收包时也要处理定时器。
4. 取尽 `poll_outbound()`，连续发送到对应 scope；Known-Answer 分包整组发完后再改变输入或时间。
5. 取事件、读取 `snapshots()`；取消或结束时调用 `cancel` / `close`。

scope 代表接口和网络代次，不是实例的永久全局 ID；换网时不要复用旧 scope 合并缓存。时间不能倒退；标签字节、二进制 TXT 与缺失状态应按模型处理。

main 的 `Engine.stats()` 提供逻辑数量和丢事件计数，**不表示字节内存或进程 RSS**。签名见 [Engine 接口](src/engine/pkg.generated.mbti)，详细契约见 [模型说明](docs/model.md)。

### 在浏览器离线查看录制

```powershell
.\scripts\build-replay.ps1
python -m http.server 8000 --bind 127.0.0.1 --directory .tools/browser-replay
```

打开本机 `http://127.0.0.1:8000` 加载 JSONL，分别查看事件与待发查询；也可直接打开生成目录的 `index.html`。页面不上传输入，不需要 npm/CDN，不具备浏览器内真实 mDNS 收发能力。详见 [离线页面说明](examples/browser_replay/README.md)。

## 使用边界

本节主要描述当前 main；已发布 0.1.0 的差异以版本表和历史发布说明为准。

### 网络与协议

| 项目 | 当前范围 |
| --- | --- |
| 发现域 | 显式订阅 `_服务._tcp.local.` / `_服务._udp.local.`；main 支持 `子类型._sub.基础类型` |
| 真实传输 | 指定本机接口的 IPv4 QM 组播；UDP 5353、目标 `224.0.0.251` |
| Native 接纳来源 | 源端口 5353、目标为上述组播地址、入站接口与所选接口一致 |
| 地址记录 | 解码和聚合 A / AAAA；AAAA 不等于 IPv6 组播传输或已验证 IPv6 连接 |
| 支持记录 | PTR、SRV、TXT、A、AAAA；未知 RR 有界保留/跳过，不自动成为业务能力 |
| 缓存 | scope 隔离、TTL、goodbye 一秒宽限、flush 近期分包保护；main 忽略 DNS-SD PTR 异常 flush 位 |
| 冲突记录 | SRV 汇集同范围未过期 RRSet，按优先级与固定种子权重顺序公开候选；替换遵循 cache-flush 宽限。多个冲突 TXT 仍保持未完成 |
| 接口变化 | 接口失效或地址/索引变化报错，不自动迁移到新接口 |
| 异步实现 | 短周期协作轮询，尚未接入系统原生异步 fd 事件源 |

当前没有服务发布者、探测/重命名、完整普通 DNS 递归解析器、QU/单播接收、NSEC 负缓存、IPv6 组播、自动接口切换、跨子网发现/反射器、后台守护进程或自动枚举所有类型。codec 能处理一种 RR，不代表相关完整协议功能已实现。

### 数据与资源上限

| 资源 | 当前 main 的限制或默认值 |
| --- | --- |
| DNS 标签/完整名称 | 每标签 1..63 字节；完整 mDNS wire 名称最多 256 字节，含根终止字节 |
| 单 DNS 报文 | 最多 9000 字节；问题和 RR 合计最多 256；单名称解码步数受限 |
| TXT 模型 | 单条最多 255 字节，总 RDATA 最多 65535；可表示不等于能放入一个 UDP 报文 |
| Known-Answer burst | 最多 64 包；首包 255 条、后续每包 256 条，默认最多 16383；另受字节限制 |
| Engine 缓存/服务 | 默认 2048 条记录 / 512 个服务，可配置上限分别为 16384 / 4096 |
| Engine 事件/查询任务 | 默认各 256，可配置上限分别为 16384 / 8192 |
| 订阅/待发问题 | 每个 Engine 最多 64 个订阅；待发问题队列最多 64 项 |
| CLI 录制/回放 | 8 MiB / 10000 帧；Replay 单行最多 32768 字符，时间为不递减的精确 JSON 整数 |
| 浏览器回放页面 | 另有 20000 条输出上限，较大文件优先用 CLI |

main 自定义 `query_packets` 包预算时数量上限为 `max_packets * 256 - 1`。wire 编码超限报错，不返回截断序列；Engine 对合法问题发送无 Known Answers 的普通 QM，并输出 `known_answer_limit`。问题无效则输出 `query_invalid` 后继续其他问题，Replay 在当前帧输出诊断。

纯 Engine 集成在分包尚未取尽时改变输入/时间或取消，会清除未发分包并诊断。事件队列溢出产生 `event_overflow`，应从 `snapshots()` 重新同步；服务容量不足时 main 保留仍有效的已公布实例，诊断省略的新增项。资源计数不是大规模并发或长期运行保证。

### 发现结果的含义

- `complete=true` 表示当前缓存记录链满足本实现要求，不代表目标一定可连接、HTTP 请求成功或设备身份可信。
- TTL 到期表示缓存证据失效；观察窗口无结果表示该窗口未发现，不能直接等同设备离线。
- 名称保留原始标签及标签内的点，仅折叠 ASCII 大小写。构造实例时优先传入已划分标签，不要机械按点拆展示名。
- TXT 可能包含二进制；JSON 十六进制保留原条目，应用仍应校验自己使用的键和值。
- 同 scope 的多个订阅共享身份；跨 scope 同名实例独立，应用应连同 scope 标识列表项。
- 连接认证、访问控制、重试和超时由业务应用负责。HTTP 示例的 demo token 仅作受控测试筛选，不是身份认证。

### 平台与证据范围

| 环境 | 已有证据 | 不能外推的结论 |
| --- | --- | --- |
| Windows Native | 同机独立 python-zeroconf 发布者；发现、动态端口 HTTP、TXT 更新、goodbye、取消和回放 | 不等于第二设备互通 |
| Linux Native / main | 同 Ubuntu VM 的 Avahi 守护进程，八项真实 IPv4 组播闭环 | 不回填为 0.1.0 Linux 包验收；不等于跨设备 |
| JS 核心/离线浏览器 | 核心冒烟、独立消费、回放和页面回调 | 不等于浏览器实时局域网扫描 |
| 其他环境 | 部分核心用例曾在 Wasm/Native 运行，详见验证记录 | 没有全后端验收，不承诺 macOS/Bonjour 或所有设备兼容 |

第二设备、Bonjour、长时间实网运行尚无证据。子类型与多包 Known-Answer 已有专项核心验收；Known-Answer 还通过独立测试解析器检查 Engine 实际生成的完整报文，但尚无对应专项实网互操作。一般 Avahi/zeroconf 闭环不能替代专项实网报告。50/200/500 个合成服务已有三轮单机性能观察，数据范围见[报告](docs/performance.md)，不构成通用性能或峰值资源保证。

## 常见问题

| 现象 | 建议检查 |
| --- | --- |
| `doctor` 失败 | 接口是否为本机当前 IPv4、接口是否可用；检查错误和共享 5353 绑定条件 |
| `doctor` 成功但没有服务 | 是否有对应发布者、类型/网卡是否正确、防火墙/VPN/访客网络/AP 隔离是否阻断组播，适当延长观察窗口 |
| 只有 `seen` 或 `complete=false` | 查看 `missing`，等待 SRV/TXT/地址，检查冲突诊断；不要连接空端点 |
| 其他工具可见，本项目不可见 | 核对组播/单播、接口、发现域和类型是否受支持；录制受控报文后分析 |
| 中文名或实例里有点 | 用 `DnsName::from_utf8_labels` / `from_labels` 保留边界；CLI 使用 DNS presentation 转义 |
| TXT 看起来像十六进制 | `txt_entries_hex` 保存原始字节；按业务协议解码，不强制将所有值解释成 UTF-8 |
| `event_overflow` | 加快事件消费，从 `snapshots()` 重建列表，按需要调整容量 |
| 安装 0.1.0 后没有 main 的 API | 核对版本表和实际依赖，不把开发文档的新能力当作发布包能力 |

提交 [GitHub Issue](https://github.com/mik1e80/MoonDiscover/issues)时，优先提供版本、平台、接口选择、命令、诊断和经过检查的受控录制。

## 验证与文档

最近代码加固的 [轻量 CI](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654335009)对应 `82a5297`，45 项 JS smoke 及其余轻量步骤成功；同提交 [Linux Avahi 检查](https://github.com/mik1e80/moonbit-mDNS-DNS-SD-/actions/runs/40654334969)八项通过。历史 [Windows 报告](docs/evidence/windows-live-20261024.json)对应 `f2baff7`，[Linux 存档](docs/evidence/linux-avahi-20261028.json)对应 `a8703be`，不混作同一版本全平台证明。

按变更运行相关文件和过滤器即可。例如只检查第一阶段的 Known-Answer 边界与回放：

```powershell
.\scripts\moon.ps1 test src/wire/known_answer_limits_test.mbt src/engine/known_answer_fallback_test.mbt src/engine/query_invalid_wbtest.mbt src/replay/replay_test.mbt --target js --frozen --filter 'smoke:*'
```

不要求每一步全量运行所有后端。更多证据和操作说明：

| 文档 | 内容 |
| --- | --- |
| [支持范围](docs/SCOPE.md) / [协议矩阵](docs/protocol-matrix.md) | 按版本、协议、环境划分能力 |
| [验证记录](docs/verification.md) / [开发指南](docs/development.md) | 测过什么、复现方法、轻量开发 |
| [模型说明](docs/model.md) | 原始字节、快照、时间、生命周期 |
| [HTTP 示例](examples/http_connect/main.mbt) / [事件示例](examples/watch_events/main.mbt) | 真实调用方式 |
| [浏览器离线回放](examples/browser_replay/README.md) | 加载、查看、复现 JSONL |
| [性能记录](docs/performance.md) / [生态对比](COMPARISON.md) | 测量范围与项目定位 |
| [当前进度](docs/progress.md) / [后续路线](docs/development-roadmap.md) | 已完成与仍待验收的工作 |
| [变更记录](CHANGELOG.md) / [0.1.0 发布说明](docs/release-0.1.0.md) | 版本差异及发布依据 |
| [项目说明](docs/submission.md) / [参赛准备状态](docs/registration-status.md) | 项目现状、准备材料与待核实事项 |

本仓库介绍的是项目本身；参赛准备状态单独记录，准备材料不代表已经提交报名或通过审核。[原始实施计划](docs/implementation-plan-20261023.md)作为历史保留，未来计划不代表当前能力。
