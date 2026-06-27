# Design：revise-system-monitor-tabbed-app-usage

## 设计目标

把系统监控从“单页多卡片”调整为“纵览 + 资源专项标签页”的结构，同时在纵览页补上当前 APP 使用排行。设计继续坚持三条边界：

1. **只读与低权限**：展示当前运行应用的资源快照，不提供进程控制，不申请额外隐私权限。
2. **当前态而非历史追踪**：APP 使用情况只表示当前采样周期的资源占用，不统计使用时长、不持久化历史。
3. **单一采样源**：顶部标签切换只改变展示层，不启动重复采样任务；所有页面消费同一 `SystemMetricSnapshot` 与 APP 使用快照。

## 信息架构

系统监控页顶部新增标签卡：

- `纵览`
- `CPU`
- `内存`
- `能耗`
- `磁盘`
- `网络`

标签卡使用 SwiftUI 原生分段控件或与现有视觉风格一致的 tab strip。当前选中页必须可通过键盘和 VoiceOver 访问，选中态不得只依赖颜色。

### 纵览页

纵览页包含两个区域：

1. 整机摘要：展示 CPU、内存、能耗、磁盘、网络的紧凑状态卡或摘要行。
2. APP 使用情况：展示当前运行应用的资源占用排行，默认按使用量降序。

### 资源专项页

CPU、内存、能耗、磁盘、网络页分别展示现有卡片中的详细内容。专项页可复用当前卡片组件，但每页只聚焦一个维度，避免用户在长列表中查找。

## APP 使用情况范围

首版 APP 使用情况覆盖“可归属到用户可识别 `.app` 的运行中应用”。系统进程、守护进程、无 bundle 归属的命令行进程默认不显示；如果某些进程无法归属到应用，计入降级统计或忽略，不展示为伪造应用。

### 可展示字段

每条 APP 使用记录建议包含：

- 应用名称。
- bundle identifier（仅作为内部稳定标识；UI 可按需要隐藏）。
- 应用图标；不可用时使用通用应用占位图标。
- 当前使用量，用于默认排序。
- CPU 当前占用。
- 内存当前占用。
- 可用时展示网络上下行速率；不可用时不展示假数据。
- 最近采样时间。

### 使用量定义

`usageAmount` 是面向排序的当前采样值，不是历史使用时长。MVP 可采用以下稳定规则：

1. 优先以 CPU 当前占用作为主要使用量。
2. CPU 相同或接近时以内存占用作为次级排序。
3. 仍相同时按应用名称升序，保证排序稳定。

后续 change 可引入加权综合分，但必须重新定义权重与可解释性。首版 UI 文案应避免把 `usageAmount` 表述成“使用时长”。

## 数据模型

新增或扩展模型：

```text
AppUsageSnapshot {
    capturedAt: Date
    records: [AppUsageRecord]
    unavailableReason: AppUsageUnavailableReason?
}

AppUsageRecord {
    id: String
    displayName: String
    bundleIdentifier: String?
    iconAvailability: AppIconAvailability
    cpuPercent: Double?
    memoryBytes: Int64?
    networkBytesInPerSec: Double?
    networkBytesOutPerSec: Double?
    usageAmount: Double
}

AppUsageUnavailableReason {
    processListUnavailable
    resourceUsageUnavailable
    appAttributionUnavailable
    unknown
}
```

`AppUsageSnapshot.records` 必须在服务层或 store 层默认按 `usageAmount` 降序排序，避免 UI 多处重复排序。所有模型保持 `Sendable` + `Equatable`。

## 采样边界

APP 使用情况需要应用归属与资源数据两类信息：

- 应用归属：使用 `NSWorkspace.shared.runningApplications` 获取运行中应用名称、bundle id、bundle URL 与图标来源。
- CPU / 内存：使用公开进程信息 API 读取当前运行应用对应进程的资源快照；实现时优先封装在 `AppUsageSampler` 中，避免 UI 直接接触底层 API。
- 网络：首版可不做进程级网络归属。若无法通过公开 API 可靠归属到应用，网络列显示不可用或省略，不得把整机网络速率分摊到应用。

采样器必须支持单次快照与前后两次差值计算。任何单个应用读取失败都只影响该记录；整体失败时返回 `AppUsageSnapshot.unavailableReason`。

## 服务与状态

现有 `SystemMonitorService` 可有两种实现方向：

1. 将 APP 使用情况纳入 `SystemMetricSnapshot`。
2. 新增 `AppUsageSnapshot` 并由 `SystemMonitorStore` 与整机快照并行持有。

推荐采用第二种，原因是 APP 使用情况是纵览页的增强模块，不应污染五维度整机模型。`SystemMonitorStore` 负责把同一采样周期内的整机快照与 APP 使用快照暴露给 UI。

```text
SystemMonitorStore
    selectedTab: SystemMonitorTab
    snapshot: SystemMetricSnapshot?
    appUsage: AppUsageAvailability
    sortedAppUsageRecords: [AppUsageRecord]
```

`selectedTab` 是窗口局部状态，不需要持久化。切换标签不得调用 `service.start`；只有页面进入、离开、刷新和采样间隔变化影响采样生命周期。

## UI 行为

### 顶部标签卡

- 标签卡位于系统监控标题区下方、内容区上方。
- 切换标签保留当前采样间隔与刷新按钮状态。
- 刷新按钮在任一标签页可见，触发同一轮整机指标与 APP 使用快照刷新。

### APP 使用情况列表

- 位于纵览页整机摘要下方。
- 默认按使用量降序。
- 列表为空时显示“当前没有可展示的运行中应用”或等价空状态。
- 不可用时显示降级原因，不展示示例应用。
- 行内容需适配窄宽度：应用名称可截断，数值列保持可读，不互相遮挡。

### 专项页

- CPU 页展示 CPU 总占用、user/system/idle 拆分。
- 内存页展示已用、可用、压缩与总量。
- 能耗页展示电池状态与整机能耗不可用说明。
- 磁盘页展示容量摘要，继续复用 `DiskUsageService` 数据源。
- 网络页展示整机接口上下行速率；不宣称提供进程级网络排行。

## 隐私与日志

- APP 使用记录仅保存在内存中的当前快照，不写数据库、不导出、不上传。
- OSLog 只记录稳定事件码，例如 `appUsage.sample.started`、`appUsage.sample.failed`，不得记录应用名称、bundle id、进程 id、CPU 百分比、内存字节数或网络速率。
- 不读取窗口标题、文档名、URL、文件内容或其他应用私有数据。
- 不申请辅助功能、输入监控、完全磁盘访问或自动化权限。

## 性能约束

- APP 使用采样与整机采样共享同一默认间隔，默认 5 秒，范围仍为 1 到 30 秒。
- 单次 APP 使用采样必须限制在当前运行应用集合内，不递归扫描 `/Applications`。
- 快速刷新或切换采样间隔时取消旧任务，并只接受当前 generation 的结果。
- APP 图标加载应缓存或按需读取，避免每次采样重复重建大量图标对象。

## 错误与降级

### 进程列表不可用

APP 使用区块显示“APP 使用情况暂不可用”及原因；CPU、内存等整机指标继续展示。

### 单应用资源不可读

该应用记录可省略不可读字段，或从列表中剔除；不得用 0 伪装成功。

### 应用归属失败

无法归属到 `.app` 的进程默认不展示。UI 可显示一条汇总说明，例如“部分系统进程未纳入 APP 排行”，但不展示进程名或 pid。

## 测试策略

- 模型测试：`usageAmount` 排序规则、相同使用量时名称升序、不可用原因 stable code。
- 采样测试：fake running applications + fake process stats，覆盖成功、单应用失败、整体失败、无可展示应用。
- Store 测试：标签切换不重启采样；刷新会同时更新整机快照与 APP 使用情况；generation 过滤旧 APP 使用结果。
- UI 状态测试：纵览页显示 APP 使用区块；默认排序降序；不可用和空状态不伪造记录；专项页只展示对应维度。
- 回归测试：现有系统监控采样间隔、刷新、离开停止、隐私日志规则保持不变。

## 备选方案

### 使用历史前台应用时长作为 APP 使用情况

不采用。历史前台时长需要持续监听应用激活，容易变成用户行为追踪，且与“当前资源使用情况”目标不一致。

### 展示所有进程

不采用。所有进程列表会把页面推向完整活动监视器，包含大量系统守护进程和命令行进程，解释成本与隐私敏感度更高。

### 按整机网络速率分摊到 APP

不采用。没有可靠公开来源时不能把整机网络速率分配给应用；宁可省略或降级。
