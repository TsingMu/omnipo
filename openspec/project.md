# Omnipo 项目约定

## 项目愿景

Omnipo 是一款原生 macOS 管家应用，以本地优先、透明可控和安全保守为核心原则，统一提供快捷启动、剪切板管理、磁盘分析与清理、应用卸载、隐私权限审计、微信空间分析和系统监控能力。

## 产品范围

项目计划按以下阶段演进：

1. 项目基础与 OpenSpec 初始化。(✅ 已完成 2026-06-19,规范见 [application-foundation](specs/application-foundation/spec.md),change 归档于 `changes/archive/initialize-project-foundation/`)
2. Launcher 与 Clippo 集成。
3. Dashboard 与应用权限审计。
4. 全局扫描与清理。
5. 拖拽卸载。
6. 微信空间管理。
7. 系统监控。

每次只推进一个 change。功能实现前必须先完成对应 change 的 `proposal.md`、`design.md`、`tasks.md` 和 `specs/<capability>/spec.md`。

## 技术基线

- 开发语言：Swift 6。
- UI：SwiftUI 优先，仅在 SwiftUI 无法可靠覆盖的系统交互中使用 AppKit。
- 最低系统版本：macOS 14。
- 工程形态：单一 Xcode macOS App Target 起步，不预先拆分 Swift Package。
- 并发模型：Swift Concurrency、结构化并发、Actor 和可取消任务。
- 状态管理：Observation；窗口局部状态与应用共享状态分离。
- 设置存储：`UserDefaults`、`@AppStorage`，复杂数据通过可替换的本地存储实现。
- 日志：`OSLog.Logger`，不得记录剪切板内容、用户文件名、聊天数据等隐私信息。
- 测试：服务协议可注入，核心模型与服务使用 XCTest 或 Swift Testing 测试。
- 第三方依赖：默认不引入；仅在原生方案明显不足且 change 设计已说明时采用。

## 架构约定

应用采用分层、模块化架构：

```text
App/
  Application/
  UI/
    Dashboard/
    Launcher/
    Clipboard/
    Cleaner/
    Uninstaller/
    PermissionAudit/
    WeChatManager/
    SystemMonitor/
  Services/
  Models/
  Infrastructure/
    Database/
    FileSystem/
    Permissions/
    AppDiscovery/
    Diagnostics/
  Shared/
    Components/
    Extensions/
    Utilities/
```

### 分层职责

- `UI` 只负责展示和用户交互，不直接访问文件系统、TCC 数据库或底层系统接口。
- `Services` 定义业务能力协议和用例边界。
- `Infrastructure` 提供服务协议的系统级实现。
- `Models` 保存跨层使用的值模型、错误、进度和结果类型。
- `Application` 负责应用入口、依赖装配、导航和应用级状态。
- `Shared` 仅保存确实跨功能复用的轻量组件，不形成无边界的工具箱。

### 服务边界

计划中的主要服务包括：

- `ShortcutService`
- `SearchService`
- `ClipboardService`
- `DiskUsageService`
- `CleanerService`
- `UninstallerService`
- `PermissionAuditService`
- `WeChatStorageService`
- `SystemMonitorService`
- `SettingsService`
- `LoggingService`

UI 依赖服务协议，不依赖具体系统实现。长时间扫描与高频采样通过 Actor 隔离可变状态，并支持取消、节流与生命周期停止。

## UI 与窗口约定

- 主窗口使用 `WindowGroup`。
- 主界面使用 `NavigationSplitView`，以稳定的侧边栏选择驱动详情区域。
- 设置使用独立 `Settings` Scene，不嵌入主导航。
- Launcher 搜索面板在对应 change 中评估并采用独立 `NSPanel`。
- 优先使用系统语义色、原生侧边栏和系统材质，自动适配浅色与深色模式。
- 所有主要功能必须同时考虑鼠标、键盘、菜单和辅助功能可访问性。

## 核心模型约定

计划中的共享模型包括：

- `SearchResult`
- `ClipboardItem`
- `DiskVolumeInfo`
- `CleanableItem`
- `AppBundleInfo`
- `PermissionCategory`
- `AppPermissionGrant`
- `PermissionAuditResult`
- `WeChatStorageCategory`
- `SystemMetricSnapshot`
- `ScanResult`
- `OperationLog`
- `AppError`
- `TaskProgress`

模型应优先使用不可变值类型，并在跨并发域使用时满足 `Sendable`。

## 安全与隐私原则

- 扫描、分析、监控和剪切板记录默认完全在本地完成。
- 不上传用户路径、文件名、剪切板内容、微信数据或隐私授权信息。
- 不解析微信聊天内容。
- 权限审计只读取授权状态，不读取对应隐私内容。
- 不绕过 macOS 安全机制，不修改其他应用的 TCC 授权记录。
- 删除前必须明确确认；可行时优先移动到废纸篓。
- 高风险内容、共享容器和归属不明确的文件默认不勾选。
- 系统目录、微信聊天数据和共享 Group Containers 采用保守降级策略。
- 无法访问的数据必须展示原因，不把“无法读取”误报为“未授权”或“无数据”。

## OpenSpec 工作流

1. 从产品目标中选择且仅选择一个 change。
2. 先完成 proposal、design、tasks 和 delta spec。
3. 审阅需求、风险、非目标和降级策略。
4. 按 `tasks.md` 顺序实施，并在每项完成后将 `[ ]` 更新为 `[x]`。
5. 每个实现步骤结束时保持工程可编译，并执行与风险相称的测试。
6. change 验收后，将增量规范合并到 `openspec/specs/` 并归档 change。

涉及删除、隐私权限、微信数据或 TCC 数据库的 change，设计文档必须单列风险、系统限制与降级策略。

