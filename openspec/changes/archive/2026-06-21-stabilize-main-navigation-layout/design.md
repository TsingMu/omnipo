# Design：稳定主窗口全部导航与详情布局

## 根因

### 侧栏位移

`List(selection:)` 同时拥有选择和滚动策略。选择变化时，AppKit/SwiftUI source list 会自行调整 content offset；窗口标题栏占位或列表高度变化会放大这一行为。因此继续对 List 增加 margin、inset 或滚动纠正会与系统自动滚动竞争，无法保证连续点击时稳定。

### 详情裁切

`NavigationSplitView` 的详情内容可以延伸到统一工具栏下方。当前只有侧栏读取了真实 `NSWindow.contentLayoutRect`，详情页没有共享该指标。七个占位页都从自身顶部开始绘制，Dashboard 则依赖偶然足够的内部 padding，二者都缺少根级边界。

## 侧栏方案

侧栏继续位于 `NavigationSplitView` 的 sidebar 列，保留系统材质，但内容使用 `ScrollView + LazyVStack`：

- 分组标题和行顺序由 `AppDestination.Section` 与 `AppDestination.allCases` 生成。
- 每行使用 plain Button 写入根选择状态，不允许容器根据选择改变滚动偏移。
- 选中行使用 accent tint 和白色语义前景；未选中行使用系统语义色。
- 行保留图标、标题、说明、`nav.<rawValue>` 标识和 selected 辅助功能 trait。
- 容器处理 Up/Down move command；纯值导航函数负责边界钳制，键盘切换时才按需滚动选中行。
- 鼠标点击、Launcher 导航和恢复选择不主动改变侧栏滚动位置。

## 根级窗口指标

保留窄 `NSViewRepresentable` 只读桥，但从 `SidebarView` 私有状态提升到 `RootView`：

- AppKit 仅计算 `window.frame.height - window.contentLayoutRect.height`。
- SwiftUI `RootView` 拥有 `windowTitlebarHeight`。
- `MainWindowLayout` 纯值函数将 AppKit 高度与 SwiftUI safe area 合并并规整异常值。
- 桥不持有、不修改 `NSWindow`，窗口 resize 时只发布高度值。

## 详情方案

详情列增加根级 `VStack`：顶部为真实标题栏高度的透明、不可交互、辅助功能隐藏占位，下面才是 `selection.detailView`。这样：

- Dashboard 与所有共享占位页使用同一个稳定内容原点。
- 页面内部无需各自猜测 toolbar 高度。
- 导航标题仍由系统 toolbar 展示，详情业务视图不感知窗口对象。

## 文件结构

- `RootView.swift`：窗口指标状态、详情稳定容器和导航。
- `SidebarView.swift`：稳定滚动侧栏、选中态与键盘导航。
- `WindowLayoutMetrics.swift`：窄 AppKit 读取桥和纯值布局计算。
- `PlaceholderFeatureView.swift`、`DashboardView.swift`：保持页面内部职责，不再自行处理窗口标题栏。

## 风险与验证

- 自定义 ScrollView 不再继承 List 自动键盘选择，因此显式实现 Up/Down，并测试首尾钳制。
- 窄窗口可能无法同时显示全部入口，因此保留滚动，键盘移动时滚动到目标行。
- 真实 `.app` 依次恢复八个目的地并截图，检查侧栏首个分组坐标和详情顶部完整性。
