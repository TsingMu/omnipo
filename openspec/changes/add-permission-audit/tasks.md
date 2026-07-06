# 任务：添加 Permission Audit 核心能力

> 本 change 当前仅完成 OpenSpec 文档，以下实现任务均未开始。实施时每完成一项必须将 `[ ]` 更新为 `[x]`，并保持工程可编译。

## 1. 模型、协议与只读边界

- [x] 1.1 定义 `PermissionCategory`、`AppPermissionGrant`、`PermissionAuditResult` 和不可读取原因模型。
  - `App/Models/PermissionAudit.swift`：新增 `PermissionCategory`、`PermissionUnavailableReason`、`PermissionGrantStatus`、`AppPermissionGrant`、`PermissionAuditSummary`、`PermissionAuditResult`；统一 `displayName/symbolName/sortOrder/stableCode/userDescription` 语义。
- [x] 1.2 定义 `PermissionAuditService` 协议，覆盖全量审计、分类过滤与错误边界。
  - `App/Services/PermissionAuditService.swift`：新增 `PermissionAuditQuery` 与 `PermissionAuditService.auditPermissions(matching:)` 窄接口，返回 `Result<PermissionAuditResult, AppError>`。
- [x] 1.3 明确并实现“只读权限状态、不读取隐私内容、不修改 TCC”的边界约束。
  - `App/Services/PermissionAuditService.swift` 协议注释固定服务边界；`App/Infrastructure/Permissions/README.md` 补充第一阶段实现约束，明确不可读取不等于未授权、日志不得包含路径和原始数据库行。
- [x] 1.4 为状态枚举、默认值、排序和 `Sendable` 边界编写测试。
  - `Tests/OmnipoTests/PermissionAuditModelsTests.swift`：覆盖类别顺序、不可读取原因稳定码、状态访问器、ID/名称归一化、summary 钳制、结果排序、Codable 往返与查询默认值。
- [x] 1.5 执行构建与测试并更新任务状态。
  - 2026-07-07 执行 `xcodebuild test -scheme Omnipo -destination 'platform=macOS' -only-testing:OmnipoTests/PermissionAuditModelsTests -only-testing:OmnipoTests/ModelTests -only-testing:OmnipoTests/SystemMonitorModelsTests -only-testing:OmnipoTests/ClipboardModelTests`，结果 `TEST SUCCEEDED`。

## 2. 权限数据源与聚合

- [ ] 2.1 在 `Infrastructure/Permissions` 下实现 Permission Audit 聚合器骨架。
- [ ] 2.2 实现窄边界的只读 TCC snapshot provider 或等价数据源入口。
- [ ] 2.3 为首批支持的权限类别实现 provider，并定义不可读取原因映射。
- [ ] 2.4 聚合不同 provider 结果，支持按类别独立降级。
- [ ] 2.5 为数据源读取、聚合、部分失败和不可读取状态编写测试。
- [ ] 2.6 执行构建与测试并更新任务状态。

## 3. 主窗口 Permission Audit 页面

- [ ] 3.1 用真实 Permission Audit 页面替换现有占位页。
- [ ] 3.2 实现摘要区、权限类别过滤和应用搜索。
- [ ] 3.3 实现结果列表、状态标签和不可读取说明。
- [ ] 3.4 为空状态、部分可读/部分不可读和完全不可读场景补充 UI 反馈。
- [ ] 3.5 为浅色/深色、键盘可达性和 VoiceOver 基础体验补充验证。
- [ ] 3.6 执行构建与测试并更新任务状态。

## 4. 日志、隐私与验收

- [ ] 4.1 审计全部 Permission Audit 日志事件，确认无应用路径、应用名列表和底层数据库内容泄漏。
- [ ] 4.2 验证审计流程不会触发新的系统权限请求，也不会修改任何授权状态。
- [ ] 4.3 验证不可读取不会误报为未授权。
- [ ] 4.4 人工验证至少一组可读取类别结果和一组不可读取降级结果。
- [ ] 4.5 审阅任务清单，确保完成状态和验收证据准确。
- [ ] 4.6 验收后将 Permission Audit 规范合并到 `openspec/specs/permission-audit/spec.md` 并归档 change。
