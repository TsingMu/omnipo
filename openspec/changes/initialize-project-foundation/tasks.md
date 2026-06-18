# 任务：初始化项目基础

> 本 change 当前仅完成 OpenSpec 文档。以下实现任务尚未开始；实施时每完成一项必须立即将 `[ ]` 更新为 `[x]`，并保持工程可编译。

## 1. 工程初始化

- [ ] 1.1 创建 Swift 6、macOS 14+ 的 Xcode macOS App 工程。
- [ ] 1.2 创建 App Target 与 Unit Test Target，并配置唯一 Bundle Identifier。
- [ ] 1.3 启用 App Sandbox，不添加额外隐私权限和高权限 entitlement。
- [ ] 1.4 创建与设计一致的 Application、UI、Services、Models、Infrastructure、Shared 目录骨架。
- [ ] 1.5 添加适用于 Xcode、Swift 和 macOS 构建产物的 `.gitignore`。
- [ ] 1.6 执行首次 Debug 构建并记录结果。

## 2. 应用入口与基础导航

- [ ] 2.1 创建 `OmnipoApp`，使用带稳定 ID 的 `WindowGroup` 作为主窗口。
- [ ] 2.2 定义 `AppDestination`，覆盖 Dashboard、Launcher、Clipboard、Cleaner、Uninstaller、Permission Audit、WeChat Manager 和 System Monitor。
- [ ] 2.3 创建 `NavigationSplitView` 根布局和原生 sidebar 样式。
- [ ] 2.4 为每个功能创建轻量占位页面，不调用任何真实扫描、监控或权限 API。
- [ ] 2.5 创建独立 `Settings` Scene 与基础设置页面。
- [ ] 2.6 验证导航选择稳定、窗口可调整大小且浅色/深色模式可读。

## 3. 设置服务

- [ ] 3.1 定义 `SettingsService` 协议和类型安全的基础设置键。
- [ ] 3.2 使用 `UserDefaults` 实现本地设置服务。
- [ ] 3.3 提供隔离的测试存储，避免测试污染用户默认设置。
- [ ] 3.4 编写设置读写、默认值和隔离性测试。

## 4. 日志服务

- [ ] 4.1 定义日志等级、分类与 `LoggingService` 协议。
- [ ] 4.2 使用 `OSLog.Logger` 实现本地结构化日志。
- [ ] 4.3 建立隐私字段禁止清单，不记录剪切板内容、用户路径、文件名或微信数据。
- [ ] 4.4 为日志事件映射和脱敏约束编写最小测试。

## 5. 统一模型

- [ ] 5.1 定义 `AppError` 的稳定错误代码、用户描述与恢复建议。
- [ ] 5.2 定义 `TaskProgress`、任务状态和确定/不确定进度表达。
- [ ] 5.3 定义基础 `OperationLog`，确保不默认携带敏感载荷。
- [ ] 5.4 为错误描述、取消状态和进度边界编写单元测试。

## 6. 依赖装配与应用状态

- [ ] 6.1 创建 `DependencyContainer` 并装配 Settings 与 Logging 服务。
- [ ] 6.2 创建最小 `AppState`，只保存真正的应用级状态。
- [ ] 6.3 将窗口选择保持在 scene 或根视图范围，避免全局共享窗口局部状态。
- [ ] 6.4 确认 UI 仅依赖服务协议，不直接构造 Infrastructure 实现。

## 7. 构建与运行入口

- [ ] 7.1 创建 `script/build_and_run.sh`，统一停止、构建和启动流程。
- [ ] 7.2 支持 run、debug、logs、telemetry 和 verify 模式。
- [ ] 7.3 创建 `.codex/environments/environment.toml` 并配置 Run action。
- [ ] 7.4 通过统一脚本执行构建与进程验证。

## 8. Phase 0 验收

- [ ] 8.1 运行全部单元测试。
- [ ] 8.2 运行 Debug 构建且无编译错误。
- [ ] 8.3 启动应用并验证主窗口、八个导航入口和设置窗口。
- [ ] 8.4 确认应用未扫描文件、未删除数据、未读取 TCC 或微信数据、未申请额外权限。
- [ ] 8.5 审阅本任务清单，确保所有已完成任务状态准确。
- [ ] 8.6 验收后将 application-foundation 规范合并到 `openspec/specs/` 并归档 change。

