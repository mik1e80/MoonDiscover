# 许可与协议参考

2026-11-20 候选归档复核：根 LICENSE 与 v0.2.0 的 Git blob 均为 d645695673349e3947e8e5ae42332d0ac3164cd7。moon.mod 仍声明 Apache-2.0。moon package --list --frozen 构建的本地 0.3.0-dev ZIP 包含完整 LICENSE、THIRD_PARTY_NOTICES、README.md 与 moon.mod。该检查属于开发归档，正式发布时仍需核对注册表包、标签和归档散列。

核对日期 2026-11-18。源码以根目录完整 LICENSE 的 Apache-2.0 分发；moon.mod 的 license 保持一致。不增加用途限制，不更换主许可。再分发时附许可、保留适用版权/归属声明、说明修改，专利许可、商标与免责声明以原文为准。

已读取安装的 `.mooncakes/moonbitlang/async/LICENSE`，固定依赖 0.22.5 为 Apache-2.0；依赖未修改、未在本仓库 vendoring，安装时由包管理器独立获取。工具链/core 单独分发，遵守其随附许可。独立测试 Avahi、python-zeroconf、ifaddr 的来源与角色见根目录 THIRD_PARTY_NOTICES；它们不作为生产发现实现链接进本库。测试环境也不免除工具自身的许可义务，不能仅凭顶层 README 推断每个第三方文件的权利。

RFC 1035、2782、6762、6763 为行为参考；4034 §4.1 仅涉及 NSEC 格式。当前实现独立编写，没有复制 RFC 代码组件或第三方 mDNS 源码；若以后提取 RFC Code Components，必须依相应 RFC 版权声明附 Simplified BSD 文本。实现标准不代表获得 IETF 授权认证，也不代表 DNSSEC 验证。

已发布 0.2.0 不改包、标签或许可。本轮为 0.3.0-dev；新稳定发布前必须核对归档包含 LICENSE/THIRD_PARTY_NOTICES、标签与包一致，并做注册表独立消费。不以开发分支检查冒充已发布包验收；也不作超出已检查来源的法律保证。
