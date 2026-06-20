# Tasks：修复主窗口标题栏内容重叠

## 1. OpenSpec

- [x] 1.1 编写 proposal、design、tasks 和 main-dashboard 增量规范。

## 2. 侧栏布局

- [x] 2.1 增加可测试的侧栏顶部安全区布局计算。（证据：`SidebarLayout.contentTopMargin(safeAreaTop:)`）
- [x] 2.2 将实际顶部安全区应用到侧栏滚动内容，保持原生列表行为。（证据：`SidebarView` 通过 `GeometryReader` 和 `contentMargins` 调整原生 List 的滚动内容）

## 3. 验证

- [x] 3.1 增加安全区布局计算测试。（证据：`ModelTests.test_sidebarLayout_usesCurrentTitlebarSafeArea`）
- [x] 3.2 执行完整构建与测试并记录验收证据。（证据：2026-06-20 真实应用窗口截图确认无重叠；macOS Debug 全量 `xcodebuild test` 结果 `TEST SUCCEEDED`）
