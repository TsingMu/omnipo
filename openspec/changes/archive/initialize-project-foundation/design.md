# 设计：初始化项目基础

## 背景

Omnipo 同时包含普通窗口、全局搜索面板、后台采样、长时间扫描和敏感文件操作。Phase 0 不实现这些业务行为，但必须先确定状态所有权、服务依赖方向和系统能力边界，避免后续功能互相渗透。

## 目标

- 建立可编译、可测试的原生 macOS 应用骨架。
- 使用稳定的桌面导航模型承载后续功能。
- 让 UI 依赖服务抽象，而不是直接依赖系统实现。
- 统一设置、日志、错误与任务进度表达。
- 保持 Phase 0 足够小，不提前实现后续 change。

## 非目标

- 不提供真实 Dashboard 指标。
- 不建立高频后台任务或常驻菜单栏能力。
- 不决定 Clippo 最终数据库迁移方案。
- 不建立 TCC 数据读取实现。
- 不设计删除执行器、授权辅助工具或特权进程。

## 总体架构

依赖方向如下：

```text
Application ──装配──> UI ──依赖──> Services 协议
                         │
                         └────────> Models

Infrastructure ──实现──> Services 协议
Infrastructure ─────────> Models
```

`Services` 不依赖 UI，`Models` 不依赖具体基础设施。系统 API 封装在 `Infrastructure` 中，由应用入口完成依赖装配。

## 工程与部署选择

- 使用 Xcode macOS App 工程，产品名暂定为 `Omnipo`。
- 使用 Swift 6 语言模式，最低部署目标为 macOS 14。
- Phase 0 仅建立一个 App Target 和一个 Unit Test Target。
- 不使用第三方依赖，降低启动阶段的构建和供应链复杂度。
- 默认使用 App Sandbox；后续需要访问用户选择范围之外路径时，必须由对应 change 重新评估 entitlement、用户授权和降级路径。

## 目录设计

```text
App/
  Application/
    OmnipoApp.swift
    AppState.swift
    AppDestination.swift
    DependencyContainer.swift
  UI/
    Root/
    Settings/
    Dashboard/
    Launcher/
    Clipboard/
    Cleaner/
    Uninstaller/
    PermissionAudit/
    WeChatManager/
    SystemMonitor/
  Services/
    SettingsService.swift
    LoggingService.swift
  Models/
    AppError.swift
    TaskProgress.swift
    OperationLog.swift
  Infrastructure/
    Database/
    FileSystem/
    Permissions/
    AppDiscovery/
    Diagnostics/
    Settings/
    Logging/
  Shared/
    Components/
    Extensions/
    Utilities/
```

Phase 0 只创建实际需要的 Swift 文件。空目录可通过说明文件保留，但不得为了目录完整性创建无意义的类型。

## Scene 与导航设计

### 主窗口

主窗口使用带稳定标识的 `WindowGroup`，默认显示 Dashboard。窗口采用系统标准标题栏和可调整尺寸，不在 Phase 0 定制无边框窗口或标题栏。

### 主导航

主界面采用 `NavigationSplitView`：

- 侧边栏保存明确、稳定的 `AppDestination` 选择。
- 行样式使用原生 sidebar list，每行一个 SF Symbol 和一个标题。
- 详情区域根据选择展示功能占位页面。
- 不采用 iOS 风格的层层 push 导航。
- 窗口级选择使用 scene 范围状态，不放入全局单例。

### 设置

设置使用独立 `Settings` Scene。Phase 0 只提供通用设置外壳和少量可验证的本地偏好，不提前加入快捷键、剪切板容量或监控刷新频率设置。

## 状态与依赖装配

- 应用共享状态使用 `@Observable` 类型，并由应用入口持有。
- 服务通过 `DependencyContainer` 集中创建，以协议类型暴露给上层。
- 简单窗口选择保留在窗口 Scene 或根视图中，不污染应用共享状态。
- 禁止使用任意可变的全局单例作为功能间通信方式。

## SettingsService

### 职责

- 以类型安全键读写轻量、本地、非敏感设置。
- 为测试提供内存实现或可注入的独立 `UserDefaults` suite。
- 不保存剪切板历史、扫描结果或大体积结构化数据。

### 基础实现

基础实现使用 `UserDefaults`。读写接口限制在明确支持的设置类型，不暴露任意对象存储。服务可标注为 `@MainActor`，因为设置主要由 UI 交互驱动且读写量很小。

## LoggingService

### 职责

- 统一 debug、info、notice、warning 和 error 等级。
- 使用 subsystem 与 category 区分模块。
- 对外接收结构化、已脱敏的事件信息。

### 基础实现

基础实现使用 `OSLog.Logger`。日志消息不得包含剪切板原文、用户文件路径、微信账号信息、文件名或隐私内容。错误日志默认记录错误代码和安全上下文，不直接输出底层敏感描述。

## 统一错误模型

`AppError` 作为跨功能错误外壳，至少区分：

- 参数或状态无效。
- 操作被用户取消。
- 权限不足。
- 资源不可访问。
- 系统 API 失败。
- 数据损坏或格式不支持。
- 未知错误。

错误包含稳定代码、面向用户的本地化描述、可选恢复建议和安全的诊断上下文。底层错误仅在不泄露隐私的前提下作为 cause 保留。

## 统一任务进度模型

`TaskProgress` 至少表达：

- 唯一任务标识。
- 当前阶段和面向用户的状态文案。
- pending、running、completed、failed、cancelled 状态。
- 已完成与总工作量；总量未知时支持不确定进度。
- 是否允许取消。
- 可选的 `AppError`。

模型为不可变值类型并满足 `Sendable`，后续扫描服务通过 `AsyncStream<TaskProgress>` 或等价异步序列发布更新。

## 构建与验证

- 建立项目本地 `script/build_and_run.sh`，作为停止旧进程、构建和启动应用的统一入口。
- 建立 `.codex/environments/environment.toml`，将 Run action 指向该脚本。
- 构建脚本支持基础运行，并为 debug、logs、telemetry、verify 模式预留明确入口。
- 使用确定的本地 DerivedData 路径，避免脚本猜测构建产物。
- 单元测试覆盖设置服务隔离性、错误描述和进度状态约束。

## 风险与降级策略

### App Sandbox 与未来扫描能力

风险：清理、卸载、微信分析和部分审计功能可能需要访问沙盒外数据。

策略：Phase 0 不扩大权限。每个后续 change 单独证明所需访问范围，优先使用用户选择、Security-Scoped Bookmark 和系统公开机制；无法访问时展示原因并降级，不通过私有手段绕过。

### TCC 与权限审计

风险：macOS 没有稳定的公开 API 可完整枚举其他应用的全部隐私授权；TCC 数据库结构和可读性可能随系统版本变化。

策略：Phase 0 不读取 TCC。未来 `add-permission-audit` 必须采用只读、版本容错和显式“不可读取”状态；不得修改数据库，不得把读取失败解释为未授权。

### 删除与敏感数据

风险：错误的基础抽象可能让后续模块绕过确认流程或直接永久删除。

策略：Phase 0 不提供通用“任意路径删除”接口。Cleaner 和 Uninstaller 的安全策略必须在各自 change 中设计，并优先移动到废纸篓。

### 过度抽象

风险：在没有真实功能前定义大量空协议和通用框架会增加维护成本。

策略：Phase 0 仅定义 Settings 与 Logging 两个真实横切服务；其余服务等对应 change 到来时再创建。

## 备选方案

### 立即拆分多个 Swift Package

暂不采用。当前没有稳定模块边界和独立发布需求，过早拆包会增加资源、可见性与构建配置成本。后续当模块拥有明确 API 和独立测试价值时再评估。

### 使用单一 ContentView 与全局环境对象

不采用。该方案初期简单，但会迅速把导航、系统服务与功能状态聚集到同一处，不适合多功能 macOS 工具。

### 使用第三方依赖注入或日志框架

暂不采用。Phase 0 的协议、构造器注入和 `OSLog` 已足够，且更利于保持工程轻量。

