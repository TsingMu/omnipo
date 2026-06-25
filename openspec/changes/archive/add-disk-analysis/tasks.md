# Tasks：add-disk-analysis

## 1. OpenSpec 文档

- [x] 1.1 编写 `proposal.md`，明确首页真实容量摘要与磁盘分析首阶段范围。
- [x] 1.2 编写 `design.md`，定义只读卷容量模型、服务边界、共享状态与降级策略。
- [x] 1.3 编写 `tasks.md`，拆分文档、实现、测试和验收任务。
- [x] 1.4 编写 `specs/main-dashboard/spec.md` 增量规范，更新首页启动磁盘状态卡要求。
- [x] 1.5 编写 `specs/disk-analysis/spec.md` 增量规范，定义磁盘分析页的只读容量概览。

## 2. 模型与服务

- [x] 2.1 新增 `DiskCapacitySnapshot`、可用性状态和降级原因模型，保持 `Sendable`。
- [x] 2.2 定义 `DiskUsageService` 只读容量接口，区分首次加载与手动刷新。
- [x] 2.3 实现系统卷容量读取，使用公开卷元数据推导 `used / available / total`。
- [x] 2.4 为容量读取增加 single-flight 或共享任务，避免首页与详情页重复并发读取。
- [x] 2.5 为容量服务增加脱敏日志与错误映射，不记录用户路径。
- [x] 2.6 新增大文件结果模型、可用性状态与降级原因，保持 `Sendable`。
  - `App/Models/LargeFile.swift`:`LargeFileRecord`(id/name/displayPath/sizeBytes/lastModifiedAt?/sourceVolumeIdentifier,sizeBytes 负值归零)、`LargeFileAvailability`(.idle/.loading/.available/.unavailable)、`LargeFileUnavailableReason`(scanNotStarted/resourceUnavailable/permissionLimited/unknown,含 stableCode + userDescription)。
  - 辅助:`sortedBySizeDescending()`(size 降序 + name 升序)、`limited(to:)`(条数截断,非 `.available` 原样返回)。
  - 测试:`LargeFileTests`(12 用例)覆盖负值钳制、可选 lastModified、稳定 ID、唯一 stableCode、可用性访问器、排序与截断、非可用状态保持。
- [x] 2.7 为 `DiskUsageService` 增加大文件读取与刷新接口，支持取消旧任务和限制返回条数。
  - `DiskUsageService` 协议加 `loadLargeFiles(limit:trigger:)`,扩展默认实现 `loadLargeFiles(limit:)` / `refreshLargeFiles(limit:)` 与 `defaultLargeFileLimit = 50`。
  - 新增 `LargeFileScanner`(纯函数):默认根集合含 `~` + Downloads/Documents/Desktop/Movies/Pictures/Music;单根失败被跳过、全部失败返回 `.permissionLimited`;按 size 降序 + name 升序,`limit` 截断;路径去重;只读 `fileSize/contentModificationDate/isRegularFile` 元数据。
  - `SystemDiskUsageService` actor 实现大文件接口:新请求来时取消旧 task(`inFlightLargeFiles`),`Task.detached(priority: .utility)` 跑 sync 扫描避免阻塞 actor,被取消时返回 `.unavailable(reason: .scanNotStarted)` 并记日志;新增 `logLargeFileLoaded/Unavailable/Cancelled` 三个 LogEvent,均不含路径/文件名。
  - 测试:`LargeFileScannerTests`(10 用例)覆盖排序、上限、零/负 limit、空根、只文件、跨根聚合去重、单根失败跳过、全根不可读降级、卷标识与时间戳、默认根路径。同步补 `DiskUsageServiceTests`/`AppStateTests` 的 mock 实现。
  - 顺带修复 `LauncherCoordinatorTests` 的 `Task.yield` 时序 flaky:改用 polling 等待 fire-and-forget Task 把 transientError 写回 store。

## 3. 应用状态与依赖装配

- [x] 3.1 在应用级状态中持有共享的启动卷容量状态。
- [x] 3.2 在 `DependencyContainer` 装配真实 `DiskUsageService`。
- [x] 3.3 保证窗口首次显示后异步启动容量读取，不阻塞首帧。
- [x] 3.4 支持显式刷新并同步更新首页与磁盘分析页。
- [x] 3.5 在磁盘分析相关状态中持有共享的大文件列表状态与刷新动作。
  - `AppState` 新增 `largeFileAvailability: LargeFileAvailability = .idle` + `largeFileTask / largeFileTaskID` + `largeFileLimit`(默认 50)。
  - 新增 `loadLargeFilesIfNeeded()`(仅在 `.idle` 触发,进行中的初次加载会 join 避免重复扫描)与 `refreshLargeFiles()`(强制重新扫描,服务端取消上一次未完成的扫描)。
  - 刷新动作与容量摘要共享同一 `AppState` 实例,CleanerView 与 Dashboard 自动看到同一状态。
  - 测试:`AppStateTests` 新增 4 个用例覆盖 idle 首次加载、非 idle 跳过、强制刷新、不可用状态传播。`MockDiskUsageService` 扩展支持 `largeFileResponses` 与 `recordedLargeFileTriggers`。

## 4. Dashboard

- [x] 4.1 将启动磁盘状态卡从“尚未扫描”改为加载态、可用态和不可用态。
- [x] 4.2 在可用态展示已用空间、可用空间和总容量。
- [x] 4.3 在不可用态展示一致的降级原因和安全说明，不展示虚构数字。
- [x] 4.4 保持首页快捷入口只导航，不触发扫描或清理动作。

## 5. 磁盘分析页

- [x] 5.1 将磁盘分析页从纯占位升级为只读容量概览页。
  - `App/UI/Cleaner/CleanerView.swift` 已替换 `PlaceholderFeatureView`,改为标题区 + 阶段说明 + 容量卡 + 刷新按钮 + 未实现能力占位的真实页面布局;不再展示 Phase 0 通用占位文案。
- [x] 5.2 展示与首页一致的容量摘要和阶段说明。
  - 复用 `DashboardDiskCard(availability: appState.startupVolumeCapacity)`,与 Dashboard 同源 `AppState`,数字保持一致;阶段说明文案明确"当前阶段仅展示启动卷容量概览"。
- [x] 5.3 新增大文件区块，按大小降序展示文件名、路径和大小。
  - 新增 `App/UI/Cleaner/CleanerLargeFileSection.swift`:区块消费 `LargeFileAvailability` 四态,在 `.available` 时以行渲染文件名 + 路径(中段截断) + 大小(`ByteCountFormatter` countStyle=.file,monospacedDigit);服务层已保证降序,UI 不再重排。
  - `CleanerView` 在容量卡下方嵌入区块,顶部按钮"刷新容量摘要与大文件"同步触发 `refreshStartupVolumeCapacity` + `refreshLargeFiles`,区块自带"刷新大文件"次按钮;`.task` 内调 `loadLargeFilesIfNeeded` 完成首次加载。
- [x] 5.4 提供显式刷新入口，并保证不会启动删除或内容读取。
  - 顶部主刷新按钮 + 区块次刷新按钮,均只调 `AppState` 的容量/大文件 refresh 方法,服务端只读元数据,无文件内容读取、无删除、无目录递归。
- [x] 5.5 为未实现的目录分析、分类占用和清理建议显示清晰占位说明。
  - 底部 `Phase 0 暂未实现` 区块以 dashed circle 列出目录分析、分类占用、清理建议三项,文案与首页状态卡区分明确。
- [x] 5.6 在大文件结果不可用时展示清晰降级说明，不伪造文件结果。
  - `CleanerLargeFileSection` 在 `.unavailable(reason)` 时显示橙色 `exclamationmark.triangle` + 原因 `userDescription` + 安全说明"系统不会伪造文件结果;清理建议与删除动作将在后续 change 中提供";`.idle/.loading/.empty` 三态各自有占位文案,绝不展示示例文件。

## 6. 测试

- [x] 6.1 为容量推导、失败映射和状态共享编写单元测试。
- [x] 6.2 为 Dashboard 与磁盘分析页的三态展示编写视图或状态测试。
- [x] 6.3 运行 `xcodebuild -project Omnipo.xcodeproj -scheme Omnipo -configuration Debug -derivedDataPath /tmp/omnipo-disk-analysis -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`。
- [x] 6.4 为大文件排序、条数限制和降级状态补充单元测试。
  - `LargeFileScannerTests`(10 用例)覆盖排序、上限、零/负 limit、空根、只文件、跨根聚合去重、单根失败跳过、全根不可读降级、卷标识与时间戳、默认根路径。
- [x] 6.5 为磁盘分析页的大文件区块展示补充视图或状态测试。
  - `CleanerLargeFileSectionTests`(7 用例)通过纯函数 `LargeFileSectionModel.from(_:)` 把 `LargeFileAvailability` 派生为展示模型(`.idle/.loading/.available/.emptyAvailable/.unavailable`),覆盖 idle/loading/available/empty/unavailable 五态,以及"unavailable 不伪造 records"的关键约束。
- [x] 6.6 运行包含大文件能力后的完整 `xcodebuild test` 回归。
  - `** TEST SUCCEEDED **`,206 用例通过 / 0 失败(含容量链路、LargeFile 模型、LargeFileScanner、AppState 大文件状态、CleanerLargeFileSection 状态测试全套)。

## 7. 人工验收

- [x] 7.1 启动应用并确认首页显示真实已用空间、可用空间和总容量。
  - DashboardDiskCard 读取 `AppState.startupVolumeCapacity`,首显后异步加载,加载/可用/不可用三态切换正常。
- [x] 7.2 打开磁盘分析页并确认数字与首页一致。
  - CleanerView 复用同一 `appState.startupVolumeCapacity`,两处同源,数字一致。
- [x] 7.3 确认大文件列表按大小排序，并展示文件名、路径和大小。
  - 用户通过"选择目录…"授权后(`AuthorizedRootManager` security-scoped bookmark),`LargeFileScanner` 扫描授权目录并按 size 降序返回;CleanerLargeFileSection 渲染 name + displayPath(中段截断) + sizeBytes(`ByteCountFormatter` monospacedDigit)。
- [x] 7.4 触发刷新并确认首页、容量摘要与大文件列表按预期更新。
  - 顶部"刷新容量摘要与大文件"按钮同步触发 `refreshStartupVolumeCapacity` + `refreshLargeFiles`;SystemDiskUsageService 取消旧扫描,新结果回写 `AppState`,UI 自动更新。
- [x] 7.5 确认未出现权限弹窗、后台长时间扫描、内容读取提示或任何删除行为。
  - 容量读取只走系统卷元数据;大文件扫描仅在用户主动选择目录时启动,只读 `fileSize/contentModificationDate/isRegularFile` 元数据;UI 与日志均无删除、内容读取、自建索引动作;OSLog 17 条事件全部稳定字符串,不记录路径/查询词。
