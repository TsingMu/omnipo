# Design：主窗口与 Dashboard 重设计

## 设计目标

参考图提供的是信息层级和气质，而不是品牌复刻。Omnipo 采用原生 macOS `NavigationSplitView`、系统侧栏材质和语义色，在详情区使用柔和渐变背景与材质卡片。主窗口保持桌面应用的指针、键盘、缩放和辅助功能体验。

## 信息架构

侧栏保留八个稳定 `AppDestination`，按以下分组展示：

- 概览：总览。
- 效率工具：快速启动、剪切板。
- 系统工具：磁盘清理、应用卸载、权限审计、微信管理、系统监控。

每个侧栏行最多包含一个图标、一个中文标题和一行简短说明。选择仍由 `RootView` 的单一 `selection` 驱动，持久化键和 Launcher 命令映射不变。

## Dashboard 结构

Dashboard 使用可滚动的纵向内容，最大内容宽度约 760 点：

1. 品牌区：Omnipo 图形标识、名称和一句本地优先说明。
2. 状态卡：显示“启动磁盘 / 尚未扫描”，并明确提示前往磁盘清理页开始扫描。
3. 快捷入口：磁盘扫描、应用卸载、权限审计、微信管理四个按钮。
4. 安全说明：强调所有敏感操作均需用户主动确认。

状态卡不直接访问文件系统或系统容量 API。真实指标必须等待后续 `DiskUsageService` change；当前版本不得用演示数字冒充用户数据。

## 导航数据流

`RootView` 拥有 `selection`。`AppDestination.detailView(onNavigate:)` 将窄导航 closure 传给 Dashboard；快捷按钮只写入该 selection。导航变化继续复用既有设置持久化与脱敏日志路径，不新增全局状态。

## 视觉系统

- 侧栏使用原生 `.sidebar` 列表，不绘制不透明自定义底色。
- 详情区使用低对比度的系统语义渐变；卡片使用 `.regularMaterial` 和细描边。
- 主操作采用一致的圆角矩形、语义 SF Symbols 与 accent tint。
- 文字使用系统动态字体和 `primary`/`secondary`，不锁定浅色主题。
- 最小窗口下快捷入口自适应为两列或单列，内容可纵向滚动。

## 文件结构

- `RootView.swift`：根布局、选择与分组侧栏。
- `DashboardView.swift`：Dashboard 高层组合。
- `DashboardComponents.swift`：品牌、状态卡、快捷入口等专用子视图。
- `AppDestination.swift`：稳定目的地元数据和详情路由。

## 风险与降级

- 过度自定义会削弱 macOS 原生侧栏行为，因此保留 `List` 与系统选中态。
- 小窗口可能压缩四个快捷入口，因此使用自适应网格并保留 ScrollView。
- 当前没有真实磁盘服务，状态卡统一显示尚未扫描并只提供导航，不隐式启动任务。
