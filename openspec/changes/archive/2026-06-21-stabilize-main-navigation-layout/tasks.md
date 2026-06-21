# Tasks：稳定主窗口全部导航与详情布局

## 1. OpenSpec

- [x] 1.1 编写 proposal、design、tasks 和 main-dashboard/application-foundation 增量规范。

## 2. 根布局

- [x] 2.1 将窗口标题栏指标桥拆分为共享窄 AppKit 边界，并由 RootView 单一持有状态。
- [x] 2.2 为详情列增加固定标题栏安全区，覆盖 Dashboard 与七个功能页。

## 3. 稳定侧栏

- [x] 3.1 使用 ScrollView + LazyVStack 替换选择驱动滚动的 List。
- [x] 3.2 保留分组、选中视觉、辅助功能标识和方向键导航。
- [x] 3.3 确保鼠标选择、恢复选择与 Launcher 导航不主动改变侧栏滚动偏移。

## 4. 验证

- [x] 4.1 增加窗口布局计算和侧栏键盘导航边界测试。
- [x] 4.2 在真实应用中检查全部八个目的地及连续选择布局。验收证据：分别以 dashboard、launcher、clipboard、cleaner、uninstaller、permissionAudit、wechatManager、systemMonitor 为恢复页启动真实应用并截图检查；侧栏分组起点保持一致，详情标题、说明和卡片均未进入工具栏区域。
- [x] 4.3 执行完整构建与测试并记录验收证据。验收证据：`./script/build_and_run.sh verify` 完成 Debug 构建与全量测试，结果为 `TEST SUCCEEDED`；针对 `ModelTests` 的独立测试同样通过。
