# MoonDiscover 0.2.0

发布日期：2026-11-01。模块 `mik1e80/dnssd`，Apache-2.0。安装：`moon add mik1e80/dnssd@0.2.0`。

本版本汇集子类型、有界多包 Known-Answer 与降级、SRV 加权候选及跨响应包 RRSet、公开状态计数、输入原子校验、Native 失败关闭与接口丢失分类修复。

源码相关轻量 CI 已通过 54 项核心 JS 检查、1 项独立解析器、Windows/Linux Native 构建及短时资源、消费/CLI 检查；Linux 专项覆盖实际 UDP、Avahi 子类型及隔离网卡恢复。详见[验证记录](verification.md)、[专题报告](specialized-interop.md)与[十分钟资源观察](performance.md)。

当前支持仍为指定接口 IPv4 QM 服务浏览/解析；没有发布者、IPv6 组播、自动接口迁移、NSEC、跨子网与第二物理设备兼容性承诺。详见 [SCOPE](SCOPE.md)。

Mooncakes 上传返回 `200 OK`、退出码 0；上传前及解包后的 `moon check` 均通过。源码标签 [`v0.2.0`](https://github.com/mik1e80/MoonDiscover/tree/v0.2.0) 固定到 `aaf6ced5d87a063a22718f841b93b6930cddc808`。[GitHub Release](https://github.com/mik1e80/MoonDiscover/releases/tag/v0.2.0) 已发布并附带模块 ZIP。

归档 SHA256：`c6d9a43a5964ee2584de49597f6ccd9bc04d3bf0b2110d1762e98ac2a8e4eebf`。Mooncakes 下载归档与上传 ZIP 逐字节一致，GitHub 附件 digest 相同；187 个安装文件逐一匹配发布源码，Native C stub 在内，私有凭据、缓存和构建目录未打包。

新建仓库外工程、无 `moon.work` 映射，从注册表安装精确 `0.2.0` 后，核心 API、Native 构建和实际 socket 打开/关闭通过；另六项新 API 检查覆盖跨包 SRV、TXT lookup、stats、快照复制、生命周期与取消。证据为[发布清单](evidence/release-0.2.0-20261101.json)、[注册表消费](evidence/consumer-registry-0.2.0-20261101.json)、[新 API](evidence/consumer-new-api-0.2.0-20261101.json)与[归档核对](evidence/archive-0.2.0-20261101.json)。

固定工具链的 dry-run 在服务器返回 202 Accepted、明确报告验证完成时仍退出 1；实际上传返回 200 并退出 0，两者分别记录，没有把 dry-run 当成实际发布。旧 `v0.1.0` 仍指向 `2b922d6`，其标签及归档保持原样。
