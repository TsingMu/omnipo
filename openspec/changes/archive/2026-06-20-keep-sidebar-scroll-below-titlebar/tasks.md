# Tasks：固定侧栏滚动视口于标题栏下方

## 1. OpenSpec

- [x] 1.1 编写 proposal、design、tasks 和 main-dashboard 增量规范。

## 2. 侧栏视口

- [x] 2.1 增加只读窗口内容布局桥，并将真实顶部安全区移至 List 外部固定占位。（证据：`WindowTitlebarHeightReader`、`WindowTitlebarProbeView` 和 `SidebarLayout.viewportTopInset`）
- [x] 2.2 保持原生侧栏选择、分组、滚动和辅助功能行为。（证据：`SidebarView` 仍使用原生 `.sidebar` List，透明占位禁止命中并从辅助功能树隐藏）

## 3. 验证

- [x] 3.1 更新安全区布局测试以表达固定视口语义。（证据：`ModelTests.test_sidebarLayout_keepsViewportBelowCurrentTitlebarSafeArea` 覆盖 SwiftUI/AppKit 高度、分组净空与异常值）
- [x] 3.2 验证总览、快速启动和剪切板切换后的真实窗口布局。（证据：2026-06-20 分别恢复快速启动和剪切板并截取真实 `.app` 窗口，两种状态均无标题栏重叠）
- [x] 3.3 执行完整构建与测试并记录验收证据。（证据：2026-06-20 macOS Debug 全量 `xcodebuild test` 结果 `TEST SUCCEEDED`）
