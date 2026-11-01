# MoonDiscover 演示脚本

建议总长 3—5 分钟。素材必须来自实际命令或公开录制；未见响应时只报告观察窗口结果。

| 时间 | 操作 | 观众应看到的证据 |
| --- | --- | --- |
| 0:00—0:30 | 展示 README 的三个应用场景与支持范围 | 服务地址和端口无需预先写死；实时入口为 Native IPv4 |
| 0:30—1:20 | 执行受控实网脚本，打开生成报告 | 独立 zeroconf 发布服务，MoonBit 得到动态端口，HTTP 返回本次 token |
| 1:20—2:00 | 展示报告的 timeline、HTTP 请求与 checks | TXT 从 one 更新至 two，goodbye 后 Removed；取消后 socket 重开 |
| 2:00—3:10 | CLI 两次回放公开 fixture，再在浏览器加载相同 JSONL | 两次结果一致；事件与待发查询分列，浏览器没有实际发包 |
| 3:10—4:00 | 展示 registry 消费报告、版本标签与 Actions | 真实注册表安装、公开 API 调用、Native 编译、归档一致性 |
| 4:00—4:30 | 展示支持矩阵与剩余验证项 | 如实说明第二设备未测、协议和平台边界 |

## 命令

在仓库根目录，先按 README 安装固定工具链和受控发布工具：

```powershell
.\scripts\moon.ps1 build cmd/moondiscover examples/http_connect tests/native_cancel --target native
.\.venv\Scripts\python.exe tests/interop/live_smoke.py --interface <活动IPv4> --output .tools/demo-live.json
$cli = '.\_build\native\debug\build\cmd\moondiscover\moondiscover.exe'
& $cli replay --file fixtures/live-20261024.jsonl
& $cli replay --file fixtures/live-20261024.jsonl
.\scripts\build-replay.ps1
python -m http.server 8000 --bind 127.0.0.1 --directory .tools/browser-replay
```

浏览器打开 `http://127.0.0.1:8000`，加载 `fixtures/live-20261024.jsonl` 并运行。演示后停止本次 HTTP 服务。

已完成[一分钟离线回放视频](media/moondiscover-demo-20261101.webm)，展示实际 CLI 输出；[来源、散列与解码校验](demo/README.md)单独记录。它不替代上方实网步骤或现场网络录屏。
