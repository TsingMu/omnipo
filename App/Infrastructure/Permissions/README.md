# Permissions Infrastructure

Phase 0 不读取 TCC 数据库或任何隐私授权内容。本目录预留给 Permission Audit change 的只读授权状态查询。

**约束**:任何权限相关实现必须满足:
- 只读访问授权状态,不读取对应隐私内容
- 不修改其他应用的 TCC 授权记录
- 不绕过 macOS 安全机制
- 版本容错:TCC 结构随系统变化,必须显式区分"不可读取"与"未授权"
