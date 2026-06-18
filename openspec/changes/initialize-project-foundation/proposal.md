# Change：初始化项目基础

## 为什么需要此变更

当前仓库没有 macOS 应用工程、应用入口、基础导航、服务骨架或统一的横切模型。后续 Launcher、Clippo、清理、卸载、权限审计和监控功能都会依赖稳定的工程边界。如果直接从业务功能开始，容易造成 UI 与系统 API 强耦合、错误处理不一致、长任务无法统一取消，以及不同功能重复实现设置和日志能力。

因此，Phase 0 先建立一个最小但可演进、持续可编译的原生 macOS 工程基础。

## 变更内容

- 初始化 Swift 6、SwiftUI、macOS 14+ 的 Xcode macOS App 工程。
- 建立 `Application`、`UI`、`Services`、`Models`、`Infrastructure` 和 `Shared` 分层目录。
- 创建主窗口和基于 `NavigationSplitView` 的基础导航。
- 为后续八个功能提供占位入口，但不实现业务能力。
- 创建独立的 Settings Scene。
- 定义 `SettingsService` 与 `LoggingService` 协议及基础本地实现。
- 定义统一错误模型 `AppError`。
- 定义统一任务进度模型 `TaskProgress`。
- 建立项目级构建、运行和最小测试入口。

## 影响范围

### 新增能力

- `application-foundation`：提供应用启动、导航、依赖装配、设置、日志、错误与进度基础。

### 受影响的未来能力

- Launcher、Clipboard、Dashboard、Disk Cleaner、App Uninstaller、Permission Audit、WeChat Manager、System Monitor 将复用本变更建立的边界。

## 非目标

- 不实现全局快捷键或搜索面板。
- 不集成 Clippo 代码或迁移其数据。
- 不读取磁盘、TCC、微信或系统性能数据。
- 不扫描或删除任何文件。
- 不申请辅助功能、完全磁盘访问或其他隐私权限。
- 不引入数据库和第三方依赖。
- 不在 Phase 0 拆分多个 Swift Package 或多个 App Target。

## 成功标准

- 工程可通过 Debug 构建。
- 应用启动后显示主窗口与原生侧边栏导航。
- 八个功能入口均可选择并显示明确的“尚未实现”占位页面。
- 设置窗口可由系统标准入口打开。
- 设置、日志、统一错误和进度模型具有可测试的最小实现。
- 不触发文件扫描、删除、隐私数据读取或权限提升。

