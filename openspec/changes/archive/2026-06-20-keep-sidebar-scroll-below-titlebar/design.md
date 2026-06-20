# Design：固定侧栏滚动视口于标题栏下方

## 根因

`contentMargins(..., for: .scrollContent)` 调整的是 ScrollView/List 内容布局，而不是列表视口。系统为恢复或显示选中行而改变滚动偏移时，可以把这段顶部内容 margin 滚出屏幕，因此它不能充当永久标题栏避让区。

## 方案

真实窗口验证表明，统一工具栏侧栏中的 `GeometryReader.safeAreaInsets.top` 可能小于 `NSWindow` 的真实标题栏/工具栏高度。因此使用一个最小 `NSViewRepresentable` 只读桥获取窗口的 `frame.height - contentLayoutRect.height`，并与 SwiftUI 安全区取较大值。桥只发布数值，不持有或修改窗口。

`SidebarView` 将得到的实际高度放在 List 外层：

1. 外层 `VStack` 顶部放置不可交互、辅助功能隐藏的透明安全区占位。
2. 原生 sidebar List 填充剩余空间。
3. List 的滚动视口由 VStack 物理限制在标题栏下方，不再使用可滚走的 `contentMargins`。
4. 在真实标题栏高度之后保留一个分组标题净空，防止原生 Section 吸顶绘制向视口上方延伸并碰到窗口按钮。该值是侧栏内容节奏常量，不用于推测标题栏高度。

安全区值继续由纯值函数规整为非负数并在两个来源间取最大值，从而适配不同标题栏高度和显示环境。

## 保持不变

- AppKit 边界只读取窗口内容布局，不修改 `NSWindow`，SwiftUI 继续拥有布局状态。
- `NavigationSplitView`、toolbar、选择恢复和 Launcher 导航路径不变。
- 侧栏背景仍由系统材质提供。

## 验证

- 自动化测试覆盖 SwiftUI/AppKit 高度取值、分组标题净空、零值和异常负值安全区。
- 真实应用依次选择总览、快速启动和剪切板，验证首行位置不随滚动偏移越过安全区。
- 缩放窗口后重复选择，确认占位随实际安全区而非固定常量变化。
