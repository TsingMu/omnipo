# Tasks：主窗口与 Dashboard 重设计

## 1. OpenSpec

- [x] 1.1 编写 proposal、design、tasks 和 main-dashboard 增量规范。

## 2. 主窗口导航

- [x] 2.1 为八个稳定目的地补充中文侧栏标题、说明与分组元数据。（证据：`AppDestination.Section`、`title`、`sidebarSubtitle` 和 `section`）
- [x] 2.2 将 RootView 侧栏改为原生分组列表，并保持选择、恢复和 Launcher 导航行为不变。（证据：`SidebarView` 使用原生 sidebar List；`RootView` 保留选择恢复与 Launcher 工具栏入口）

## 3. Dashboard

- [x] 3.1 实现自适应 Dashboard 背景、品牌区和未扫描状态卡。（证据：`DashboardView`、`DashboardBrandHeader`、`DashboardDiskCard`）
- [x] 3.2 实现四个快捷导航入口，不触发任何业务操作。（证据：`DashboardShortcut` 仅映射目的地，`DashboardShortcutGrid` 仅调用导航闭包）
- [x] 3.3 拆分 Dashboard 专用组件，避免根视图膨胀。（证据：新增 `DashboardComponents.swift`）

## 4. 验证

- [x] 4.1 增加目的地分组和快捷导航映射测试。（证据：`ModelTests.test_appDestination_sectionsCoverAllDestinationsOnce`、`test_dashboardShortcuts_mapToSafeNavigationDestinations`）
- [x] 4.2 执行完整构建与测试并记录验收证据。（证据：2026-06-20 执行 macOS Debug 全量 `xcodebuild test`，结果 `TEST SUCCEEDED`）
