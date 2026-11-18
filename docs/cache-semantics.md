# 正负缓存与恢复

正向 IN PTR/SRV/TXT/A/AAAA 采用 RecordCache 原有 TTL、1 秒 goodbye、flush 宽限和近期分包救回。共享 DNS-SD PTR 忽略异常 flush 位；接纳失败原子回滚。

0.3.0-dev 的负缓存单独存储受限 NSEC 位图，避免混入服务正记录和 Known-Answer。正负容量分别受同一个配置数值限制；容量不够不局部提交。正向断言优先，不因 NSEC 删正记录；类型、名称及 scope 不互相扩散。负证据到期删除并恢复查询；TTL=0 NSEC 直接撤销否定证据，采用保守提早恢复查询策略，不撤销其他名称。

否定不等于整名不存在、不等于服务已离线、不具备认证；无响应或超时不生成负缓存。详细规则、测试和外部验收范围见 [negative-response.md](negative-response.md)。
