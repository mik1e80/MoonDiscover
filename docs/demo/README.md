# 一分钟离线回放演示

[播放 WebM 视频](../media/moondiscover-demo-20261101.webm) · [预览图](../media/moondiscover-demo-20261101.png) · [录制元数据](../media/moondiscover-demo-20261101.json)

视频时长约 60 秒，1280×720，VP9 WebM，约 1.02 MiB；编码后由浏览器重新加载确认可解码。它以字幕和事件卡片展示实际 CLI 离线回放输出，不包含实时扫描或现场网络录屏。

输入是仓库公开的 `fixtures/live-20261024.jsonl`，来源见 [fixtures/README.md](../../fixtures/README.md)。实际执行命令为：

```text
moondiscover replay --file fixtures/live-20261024.jsonl
```

同一命令连续执行两次，完整输出逐字节一致。视频中实例、目标、端口、地址、TXT phase 与事件顺序来自这次输出；展示时间被压缩。CLI 源码为 `5f246ea54a1e4f541fac2b16508fda3e460e68b4`，当时版本字段为 `0.2.0-dev`，画面保留这一真实状态。后续正式发布不会改写这次录制的来源。

WebM SHA256：`42680bb2ed8266a82b3437902aa828520f260440d860e4e0e373f8f973d97db9`。

PNG SHA256：`84f8c7336a6baaf0977343ad1b50fb4dc9f25ab28d3c4886ac8d6649f023c236`。

项目原创讲解画面与字幕适用根目录 Apache-2.0 许可；无第三方音乐或外部图片。实网验证请阅读[专项互通报告](../specialized-interop.md)，完整手工演示流程见[演示脚本](../demo-script.md)。
