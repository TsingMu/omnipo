# Permissions Infrastructure

Phase 0 不读取 TCC 数据库或任何隐私授权内容。本目录预留给 Permission Audit change 的只读授权状态查询。

当前 Permission Audit 第一阶段已经固定以下实现边界，后续文件必须遵守：

- 只读访问授权状态,不读取对应隐私内容
- 不修改其他应用的 TCC 授权记录
- 不绕过 macOS 安全机制
- 版本容错:TCC 结构随系统变化,必须显式区分"不可读取"与"未授权"
- 不把数据库不可访问、系统版本不支持或沙盒限制误报为"未授权"
- 不把应用路径、原始数据库行或其他敏感权限元数据写入日志

建议实现形态：

- 使用统一的 `PermissionCategory` / `AppPermissionGrant` / `PermissionAuditResult` 领域模型
- 把 TCC 读取收敛在非常窄的只读 snapshot provider 内
- 按权限类别分别实现 provider,允许分类别降级
