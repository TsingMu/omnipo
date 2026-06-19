# 任务：初始化项目基础

> 本 change 已完成 OpenSpec 文档、Phase 0 实现与全部 UI 验收,所有任务已 `[x]`。规范将合并到 `openspec/specs/application-foundation/spec.md`,change 归档到 `openspec/changes/archive/initialize-project-foundation/`。

## 1. 工程初始化

- [x] 1.1 创建 Swift 6、macOS 14+ 的 Xcode macOS App 工程。
- [x] 1.2 创建 App Target 与 Unit Test Target,并配置唯一 Bundle Identifier。
  - App: `com.omnipo.app`,Tests: `com.omnipo.app.tests`。
- [x] 1.3 启用 App Sandbox,不添加额外隐私权限和高权限 entitlement。
  - `App/Resources/Omnipo.entitlements` 仅包含 `com.apple.security.app-sandbox` 与 `com.apple.security.files.user-selected.read-write`。
- [x] 1.4 创建与设计一致的 Application、UI、Services、Models、Infrastructure、Shared 目录骨架。
- [x] 1.5 添加适用于 Xcode、Swift 和 macOS 构建产物的 `.gitignore`。
- [x] 1.6 执行首次 Debug 构建并记录结果。
  - `bash ./script/build_and_run.sh build` 返回 `** BUILD SUCCEEDED **`。

## 2. 应用入口与基础导航

- [x] 2.1 创建 `OmnipoApp`,使用带稳定 ID 的 `WindowGroup` 作为主窗口。
  - `WindowGroup(id: "omnipo.main")`。
- [x] 2.2 定义 `AppDestination`,覆盖 Dashboard、Launcher、Clipboard、Cleaner、Uninstaller、Permission Audit、WeChat Manager 和 System Monitor。
- [x] 2.3 创建 `NavigationSplitView` 根布局和原生 sidebar 样式。
- [x] 2.4 为每个功能创建轻量占位页面,不调用任何真实扫描、监控或权限 API。
  - 所有功能视图通过共享 `PlaceholderFeatureView` 呈现,不触发文件扫描、TCC 访问或高频采样。
- [x] 2.5 创建独立 `Settings` Scene 与基础设置页面。
- [x] 2.6 验证导航选择稳定、窗口可调整大小且浅色/深色模式可读。
  - 选择保存在 `@State selection`,仅在 onChange 时写入 settings;使用系统语义色与原生 sidebar 自动适配外观。
  - 已完成:Dashboard 默认选中、8 个入口、导航持久化(WeChat Manager 重启恢复)、应用进程启动成功、Settings 窗口弹出、浅色/深色模式切换可读、窗口尺寸调整。

## 3. 设置服务

- [x] 3.1 定义 `SettingsService` 协议和类型安全的基础设置键。
- [x] 3.2 使用 `UserDefaults` 实现本地设置服务。
- [x] 3.3 提供隔离的测试存储,避免测试污染用户默认设置。
  - `UserDefaultsSettingsService.testing(suiteName:)` 每次生成独立 suite 并清理残留。
- [x] 3.4 编写设置读写、默认值和隔离性测试。
  - `SettingsServiceTests` 覆盖默认值、读写往返、删除、批量重置、nil 清理与标准 suite 隔离。

## 4. 日志服务

- [x] 4.1 定义日志等级、分类与 `LoggingService` 协议。
- [x] 4.2 使用 `OSLog.Logger` 实现本地结构化日志。
- [x] 4.3 建立隐私字段禁止清单,不记录剪切板内容、用户路径、文件名或微信数据。
  - `PrivacyRedaction`:forbiddenKeys + forbiddenPathSubstrings + allowedContextKeys 白名单 + 文件名启发式;`OSLogLoggingService` 把动态 context 值标记为 `.private`,即便字符串脱敏漏过 OSLog 也不会原样落盘。
- [x] 4.4 为日志事件映射和脱敏约束编写最小测试。
  - `LoggingServiceTests` 覆盖禁止键、各类路径模式(/Users/、/Volumes/、/tmp/、~/、file://)、未知键、文件扩展名、白名单键、消息脱敏。

## 5. 统一模型

- [x] 5.1 定义 `AppError` 的稳定错误代码、用户描述与恢复建议。
- [x] 5.2 定义 `TaskProgress`、任务状态和确定/不确定进度表达。
  - 字段使用 `public private(set)`,提供 `markRunning`、`markCompleted`、`markFailed`、`markCancelled`、`updateProgress` 受控转换;`validate(...)` 提供严格校验。
- [x] 5.3 定义基础 `OperationLog`,确保不默认携带敏感载荷。
- [x] 5.4 为错误描述、取消状态和进度边界编写单元测试。

## 6. 依赖装配与应用状态

- [x] 6.1 创建 `DependencyContainer` 并装配 Settings 与 Logging 服务。
  - `@Observable @MainActor final class DependencyContainer` 提供协议类型的注入。
- [x] 6.2 创建最小 `AppState`,只保存真正的应用级状态。
  - 当前仅保存 `lastOpenedDestination`,后续 change 增量扩展。
- [x] 6.3 将窗口选择保持在 scene 或根视图范围,避免全局共享窗口局部状态。
  - `RootView.selection` 为 `@State`,不放入 `AppState`。
- [x] 6.4 确认 UI 仅依赖服务协议,不直接构造 Infrastructure 实现。
  - UI 通过 `@Environment(DependencyContainer.self)` 取得 `any SettingsService` / `any LoggingService`。

## 7. 构建与运行入口

- [x] 7.1 创建 `script/build_and_run.sh`,统一停止、构建和启动流程。
- [x] 7.2 支持 run、debug、logs、telemetry 和 verify 模式。
  - 另外提供 build、test、stop 模式;`logs` 与 `telemetry` 通过 `/usr/bin/log` 显式调用系统日志命令,避免与同名辅助函数冲突。
- [x] 7.3 创建 `.codex/environments/environment.toml` 并配置 Run action。
  - 使用 Codex Run 约定格式:顶层 `version` + `name` + `[setup]` + `[[actions]]`,Run action 指向 `./script/build_and_run.sh run`。
- [x] 7.4 通过统一脚本执行构建与进程验证。
  - `bash ./script/build_and_run.sh build` 与 `bash ./script/build_and_run.sh test` 均通过。

## 8. Phase 0 验收

- [x] 8.1 运行全部单元测试。
  - `** TEST SUCCEEDED **`,28 个测试用例全部通过。
- [x] 8.2 运行 Debug 构建且无编译错误。
- [x] 8.3 启动应用并验证主窗口、八个导航入口和设置窗口。
  - 已完成:UI 走查确认主窗口显示、Dashboard 默认选中、8 个 sidebar 入口完整、导航持久化(WeChat Manager 重启恢复)、应用进程启动且 `CFBundleIdentifier = com.omnipo.app`、Settings 窗口(`Cmd+,`)弹出、浅色/深色模式切换可读、窗口尺寸调整可用。
- [x] 8.4 确认应用未扫描文件、未删除数据、未读取 TCC 或微信数据、未申请额外权限。
  - 代码审阅无 `NSFileManager` 扫描、无 TCC/隐私 API 调用、无第三方依赖;entitlements 仅含 sandbox 与用户选择读写。
- [x] 8.5 审阅本任务清单,确保所有已完成任务状态准确。
- [x] 8.6 验收后将 application-foundation 规范合并到 `openspec/specs/` 并归档 change。
  - 2026-06-19 完成:规范合并到 `openspec/specs/application-foundation/spec.md`,change 归档到 `openspec/changes/archive/initialize-project-foundation/`。
