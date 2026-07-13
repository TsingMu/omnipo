# Omnipo 项目约定

## 项目愿景

Omnipo 是一款原生 macOS 管家应用，以本地优先、透明可控和安全保守为核心原则，统一提供快捷启动、剪切板管理、磁盘分析与清理、应用卸载、隐私权限审计、微信空间分析和系统监控能力。

## 产品范围

项目按以下阶段演进，当前基线状态如下：

1. ✅ 项目基础与 OpenSpec 初始化（2026-06-19 完成）。
2. ✅ Launcher 与剪切板管理（Launcher 于 2026-06-25 完成，剪切板于 2026-07-06 完成）。
3. ✅ Dashboard 与应用权限审计（Dashboard 于 2026-06-21 完成，权限审计于 2026-07-07 完成）。
4. 🟡 全局扫描与清理（只读磁盘容量及授权目录大文件扫描于 2026-06-25 完成；只读筛选、会话 review 与 Finder 定位工作台已于 2026-07-13 完成验收并归档；通用清理执行不在范围内）。
5. 🟡 应用卸载（应用发现、关联文件分析、确认及移入废纸篓于 2026-07-09 完成；拖拽导入入口尚未实现）。
6. ✅ 微信空间管理（只读空间分析于 2026-07-11 完成；当前基线不删除或修改微信数据）。
7. ✅ 系统监控（基础监控于 2026-06-26 完成，分栏与应用用量修订于 2026-06-29 完成）。

### 当前基线

- **版本**：0.2.0（本地稳定基线）
- **基线日期**：2026-07-13
- **工程状态**：Debug 构建、全量 XCTest、OpenSpec 严格校验及本机人工验收均通过。
- **能力范围**：八个主导航入口均已接入；开机启动以系统有效状态为准；可选子系统支持非致命降级；目录授权可恢复；后台监控与有限扫描遵循明确生命周期。
- **未交付范围**：通用磁盘清理执行、应用拖拽卸载入口、发布签名与公证流程不属于此基线。
- **规格索引**：已验收能力位于 `openspec/specs/`，对应 change 位于 `openspec/changes/archive/`。
- **磁盘分析基线**：支持授权目录的大文件扫描、本地筛选与排序、会话内候选复核及 Finder 定位；不执行删除或清理操作。

### 本地使用已知限制

- 当前基线只面向单台本地 Mac，不包含 Developer ID 签名、公证、安装包、自动更新、云端 CI 或遥测。
- 剪贴板本地存储初始化失败时只禁用剪贴板能力，不自动删除、迁移或重建数据库；恢复底层环境后需重新启动应用。
- 已保存目录被移动、授权撤销或 bookmark 损坏时需要用户重新选择目录；应用不会绕过 macOS security scope 或 TCC。
- 磁盘和微信能力保持只读元数据分析，不提供通用磁盘清理或微信数据删除；大文件工作台只覆盖当前授权目录的最多 50 条结果，筛选、选择和忽略状态仅保留在当前会话。
- 用户启动的有限扫描不承诺在应用退出后继续运行；卸载仍要求明确确认并优先移入废纸篓。

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
- `LargeFileRevealService`
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
