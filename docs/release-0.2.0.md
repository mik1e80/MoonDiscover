# MoonDiscover 0.2.0

发布日期目标：2026-11-01。模块 `mik1e80/dnssd`，Apache-2.0。

本版本汇集子类型、有界多包 Known-Answer 与降级、SRV 加权候选及跨响应包 RRSet、公开状态计数、输入原子校验、Native 失败关闭与接口丢失分类修复。

源码相关轻量 CI 已通过 54 项核心 JS 检查、1 项独立解析器、Windows/Linux Native 构建及短时资源、消费/CLI 检查；Linux 专项覆盖实际 UDP、Avahi 子类型及隔离网卡恢复。详见[验证记录](verification.md)、[专题报告](specialized-interop.md)与[十分钟资源观察](performance.md)。

当前支持仍为指定接口 IPv4 QM 服务浏览/解析；没有发布者、IPv6 组播、自动接口迁移、NSEC、跨子网与第二物理设备兼容性承诺。详见 [SCOPE](SCOPE.md)。

发布准备状态：版本与材料已固定，实际 Mooncakes 上传、源码标签、GitHub Release、归档散列及从注册表独立消费将在执行后记录；此状态不代表已经上传成功。旧 `v0.1.0` 与发布归档保持原样。
