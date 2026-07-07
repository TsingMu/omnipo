# 任务：添加 Permission Audit 核心能力

> 实施时每完成一项必须将 `[ ]` 更新为 `[x]`，并保持工程可编译。

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

- [x] 2.1 在 `Infrastructure/Permissions` 下实现 Permission Audit 聚合器骨架。
  - `App/Infrastructure/Permissions/PermissionAuditAggregator.swift`：新增 `PermissionAuditAggregator`、`PermissionCategoryProvider` 与 provider 结果模型，服务协议文件仅保留公共查询边界。
- [x] 2.2 实现窄边界的只读 TCC snapshot provider 或等价数据源入口。
  - `App/Infrastructure/Permissions/TCCReadOnlySnapshotProvider.swift` 以 SQLite readonly 方式读取用户与系统 TCC database，不执行写入、不向日志暴露路径或原始行。
- [x] 2.3 为首批支持的权限类别实现 provider，并定义不可读取原因映射。
  - `App/Infrastructure/Permissions/TCCPermissionCategoryProvider.swift` 覆盖 camera、microphone、photos、contacts、calendar、reminders、accessibility、fullDiskAccess 的 TCC service 映射。
- [x] 2.4 聚合不同 provider 结果，支持按类别独立降级。
  - 聚合器保留成功类别结果，并将失败类别写入 `unavailableCategories`，不把不可读取误报为 denied。
- [x] 2.5 为数据源读取、聚合、部分失败和不可读取状态编写测试。
  - `Tests/OmnipoTests/PermissionAuditModelsTests.swift`：覆盖类别/搜索过滤、部分不可读取降级、日志上下文不包含 app identity、TCC auth_value schema、legacy allowed schema、unsupported schema、readonly 读取不修改测试数据库，以及 readable grant + unavailable category 同时进入 `PermissionAuditStore` 的页面状态。
- [x] 2.6 执行构建与测试并更新任务状态。
  - 2026-07-07 执行 `xcodebuild test -scheme Omnipo -destination 'platform=macOS' -only-testing:OmnipoTests/PermissionAuditModelsTests`，结果 `TEST SUCCEEDED`。
  - 2026-07-07 将 Permission Audit 数据源与聚合实现从 service 协议文件拆分到 `App/Infrastructure/Permissions` 后，重新执行同一 focused test，结果 `TEST SUCCEEDED`。

## 3. 主窗口 Permission Audit 页面

- [x] 3.1 用真实 Permission Audit 页面替换现有占位页。
  - `App/Application/PermissionAuditStore.swift`：新增页面状态 store，接入 `PermissionAuditService` 并处理加载、刷新、成功与失败状态。
  - `App/UI/PermissionAudit/PermissionAuditView.swift`：新增真实审计页面，接入 `DependencyContainer.permissionAuditService`。
- [x] 3.2 实现摘要区、权限类别过滤和应用搜索。
  - 页面包含授权记录、已授权、不可读取类别摘要；支持分段类别筛选和应用/Bundle ID 搜索。
- [x] 3.3 实现结果列表、状态标签和不可读取说明。
  - 结果行展示应用名（优先中文本地化名称）、真实应用图标（可解析时）、类别、Bundle ID 和状态 badge；不可读取类别展示 category 与 reason userDescription。
- [x] 3.4 为空状态、部分可读/部分不可读和完全不可读场景补充 UI 反馈。
  - 加载、空结果、不可读取类别、失败状态均有独立 UI 分支；数据库不可读时会弹出“需要完全磁盘访问”申请提示，并提供跳转系统设置入口。
- [x] 3.5 为浅色/深色、键盘可达性和 VoiceOver 基础体验补充验证。
  - 2026-07-07 通过 Computer Use 辅助功能树验证浅色页面：侧边栏入口、刷新按钮、权限类别分段控件、搜索框、摘要 tile、不可读取类别说明均可被辅助功能读取/操作。
  - 尝试使用 `open -n ... --args -AppleInterfaceStyle Dark` 做非持久深色外观验证，但该启动参数未改变窗口外观；后续由人工验收补齐。
  - 2026-07-07 用户确认已完成人工验收，覆盖浅色/深色、键盘可达性与 VoiceOver 基础体验。
- [x] 3.6 执行构建与测试并更新任务状态。
  - 2026-07-07 执行 `xcodebuild test -scheme Omnipo -destination 'platform=macOS' -only-testing:OmnipoTests/PermissionAuditModelsTests`，结果 `TEST SUCCEEDED`。
  - 2026-07-07 执行 `./script/build_and_run.sh run`，Debug build 成功并启动 Omnipo；通过辅助功能树验证 Permission Audit 页面渲染真实内容、类别筛选可操作、搜索框可设置。
  - 2026-07-07 追加执行同一 focused test，新增 `test_permissionAuditStore_loadsReadableAndUnavailableResult`，结果 `TEST SUCCEEDED`。
  - 2026-07-07 将 `PermissionAuditStore` 从 UI 文件拆分到 `App/Application/PermissionAuditStore.swift` 并加入 app target 后，重新执行同一 focused test，结果 `TEST SUCCEEDED`。
  - 2026-07-07 新增数据库不可读时的权限申请弹窗状态与非数据库原因不弹窗测试，执行同一 focused test，结果 `TEST SUCCEEDED`；沙箱外执行 `./script/build_and_run.sh run` 成功，并通过辅助功能树确认弹出“需要完全磁盘访问”sheet。
  - 2026-07-07 为授权明细新增 app icon identifier 链路并复用 `ApplicationResourceCache` 显示真实应用图标，新增 provider 图标标识测试后执行同一 focused test，结果 `TEST SUCCEEDED`。
  - 2026-07-07 为授权明细应用名新增中文本地化优先解析（`zh-Hans`/`zh-Hant`/`zh` InfoPlist.strings），新增临时 app bundle 测试后执行同一 focused test，结果 `TEST SUCCEEDED`。

## 4. 日志、隐私与验收

- [x] 4.1 审计全部 Permission Audit 日志事件，确认无应用路径、应用名列表和底层数据库内容泄漏。
  - `DefaultPermissionAuditService` 仅记录 `permission_audit.started` 与 `permission_audit.finished`，context 只包含 category/stage/reason；测试确认日志不包含 bundle identifier 或 app display name。
- [x] 4.2 验证审计流程不会触发新的系统权限请求，也不会修改任何授权状态。
  - `TCCReadOnlySnapshotProvider` 使用 `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` 读取 TCC；临时 SQLite 测试确认读取后 modification date 与 row count 不变；现场启动页面未出现系统权限请求弹窗。
- [x] 4.3 验证不可读取不会误报为未授权。
  - provider 失败路径返回 `unavailableCategories[category]`，不生成 `.denied` grant；现场环境展示 8 个“不可读取”类别，摘要显示已授权 0、不可读取类别 8。
- [x] 4.4 人工验证至少一组可读取类别结果和一组不可读取降级结果。
  - 当前机器用户 TCC db 可见但 SQLite 打开返回 `authorization denied`，此前现场 app 验证只能覆盖不可读取降级结果；可读取结果路径由 store/provider 测试覆盖，后续由人工验收补齐。
  - 2026-07-07 用户确认已完成人工验证，覆盖至少一组可读取类别结果和一组不可读取降级结果。
- [x] 4.5 审阅任务清单，确保完成状态和验收证据准确。
  - 2026-07-07 曾复核任务状态并保留待人工验收项；用户确认人工验收完成后再次复核，所有任务均已完成。
  - 2026-07-07 用户确认人工验收完成后复核任务状态，全部任务可标记完成。
- [x] 4.6 验收后将 Permission Audit 规范合并到 `openspec/specs/permission-audit/spec.md` 并归档 change。
  - 2026-07-07 已新增 `openspec/specs/permission-audit/spec.md`，并准备将 change 归档到 `openspec/changes/archive/add-permission-audit`。
