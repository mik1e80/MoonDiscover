# 轻量开发与复现

固定版本与散列见 `toolchain.json`：moon `0.1.20261023`、moonc `v0.10.17+d971670cd`、async `0.22.5`。旧的 2026-09 工具链不能读取此 async 版本的配置。不要修改已安装依赖源码来掩盖不兼容。

## 工具链与最小检查

Windows 已安装 Visual Studio C++ 工具和 Windows SDK 时：

```powershell
.\scripts\bootstrap.ps1
.\scripts\moon.ps1 run examples/encode_query --target js
.\scripts\moon.ps1 test src/engine --target js --frozen --filter 'smoke:*'
.\scripts\moon.ps1 build cmd/moondiscover examples/http_connect examples/watch_events tests/native_cancel --target native
python tests/interop/cli_smoke.py
```

bootstrap 将官方固定工具链装在项目 `.tools/moon`，校验归档散列并构建 core bundle；不会升级全局工具链。工具链和依赖已安装时，可用 `bootstrap.ps1 -Offline`。

按改动选择相关包或具体测试文件。需要复现当前 CI 核心范围时运行：

```powershell
.\scripts\moon.ps1 test dnssd_test.mbt src/model src/wire src/cache src/engine src/replay --target js --frozen --filter 'smoke:*'
```

提交前运行 `scripts/moon.ps1 info --frozen` 和 `scripts/moon.ps1 fmt`，检查生成接口差异。不以重复全量测试增加提交步骤。

## 离线回放

先构建 CLI，再运行实际二进制：

```powershell
$cli = '.\_build\native\debug\build\cmd\moondiscover\moondiscover.exe'
& $cli replay --file fixtures/replay-basic.jsonl --seed 7
& $cli replay --file fixtures/live-20261024.jsonl
```

有 `config` 首帧时自动恢复录制的 UInt32 随机种子；显式 `--seed` 必须与配置一致。相同帧/时间/种子应产生相同 JSON 事件和待发报文。文件上限 8 MiB/10000 帧，时间需为不递减的精确 JSON 整数。

## 受控 Windows 实网实验

`tests/interop/live_smoke.py` 创建独立 zeroconf 发布者与动态端口 HTTP 服务，运行 Native CLI/HTTP/取消程序，修改 TXT、发送 goodbye、保存录制并离线回放。先完成 Native 构建，选择当前活动物理网卡的 IPv4 地址：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r tests/interop/requirements.txt
.\.venv\Scripts\python.exe tests/interop/live_smoke.py --interface 192.168.1.10 --output .tools/live-local.json
```

测试前确认该地址属于活动接口；VPN/隧道地址可能不具备预期组播可达性。宿主机需允许组播收发；受限 sandbox 内无响应不能当作协议验证通过。脚本清理它创建的进程与服务，不需要停止其他占用 5353 的应用。

CLI 手工录制为 `browse` 或 `resolve` 添加 `--record path.jsonl`，正常退出后写入配置、输入命令、时钟和接收原始报文。录制也可能包含同接口其他服务的报文，提交前只导出受控服务相关内容，并分别记录原始与导出散列。

## 后端与证据

仓库外消费验证脚本会新建独立临时工程，只导入公开包，不复制库源码：

```powershell
python tests/interop/consumer_smoke.py --mode local --version 0.2.0 --interface 192.168.1.10 --output .tools/consumer-local.json
```

local 模式通过 `moon.work` 指向本地源码，检查 JS 调用、Native 编译和可选 socket 打开/关闭。实际发布后，使用 `--mode registry --version 0.1.0` 验证注册表包；该模式不生成工作区覆盖。两种模式的结果分别记录，失败会返回非零。

根包是无 socket 的纯核心；真实网络入口为 `mik1e80/dnssd/src/native`。默认轻量 CI 使用固定版本做 JS 冒烟、Windows/Linux Native 编译和离线契约验证；独立的 `linux-interop.yml` 则在相关路径变更或手动触发时，运行同 VM 的真实 Avahi IPv4 组播闭环，保留逐项报告。

Linux 实验需要 Avahi 守护进程、D-Bus 与系统 python3-dbus，使用 `/usr/bin/python3 tests/interop/avahi_smoke.py --output .tools/avahi-linux.json`。脚本会创建录制目录，失败时保留浏览器和文件状态。平台结论依 [验证记录](verification.md)；同 VM 不代表第二设备，原始计划也不作为全部完成的证明。
