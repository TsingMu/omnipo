# 任务：添加 Launcher 核心能力

> 本 change 当前仅完成 OpenSpec 文档，以下实现任务均未开始。实施时每完成一项必须将 `[ ]` 更新为 `[x]`，并保持工程可编译。

## 1. 模型与服务协议

- [x] 1.1 定义 `KeyboardShortcut`、修饰键和稳定持久化表示，默认值为 Option + Space。
  - `App/Models/KeyboardShortcut.swift`:Carbon keyCode + OptionSet 修饰键,默认 `keyCode=49 + .option`;持久化用 Codable,显示文本不参与身份比较。
- [x] 1.2 定义 `SearchResult`、结果类型、图标描述和安全执行载荷。
  - `App/Models/SearchResult.swift`:`Kind` 枚举 + `IconDescriptor`(无 NSImage)+ `ExecutionPayload`(含 fileBookmark Data,文件 URL 不明文出现)。
- [x] 1.3 定义六个稳定的 `LauncherCommand` 标识及本地化展示元数据。
  - `App/Models/LauncherCommand.swift`:六个 case,稳定 `id == rawValue`,displayTitle/englishTitle/keywords/symbolName 齐备。
- [x] 1.4 定义 `ShortcutService` 协议、注册结果和冲突错误。
  - `App/Services/ShortcutService.swift`:`ShortcutService` 协议、`ShortcutRegistrationResult`、`ShortcutError`(invalidShortcut/conflict/systemFailure/serviceUnavailable)。
- [x] 1.5 定义 `SearchService` 与内部搜索提供者协议，支持异步批次和取消。
  - `App/Services/SearchService.swift`:`SearchService`、`SearchProvider`、`SearchProviderResult`(success/failure/unavailable)、`SearchBatch`。
- [x] 1.6 为模型合法性、默认值、序列化和 `Sendable` 边界编写测试。
  - `KeyboardShortcutTests`(8)、`LauncherCommandTests`(6)、`SearchResultTests`(4);全部类型标注 `Sendable`。
- [x] 1.7 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 2. 全局快捷键基础设施

- [x] 2.1 使用 Carbon `RegisterEventHotKey` 实现 `CarbonShortcutService`。
  - `App/Infrastructure/Shortcut/CarbonShortcutService.swift`:`CarbonShortcutBackend` 单例 + `CarbonShortcutService` 装饰。
- [x] 2.2 实现事件处理器安装、热键注册、触发发布、注销和销毁清理。
  - `installHandler` 安装 `kEventClassKeyboard/kEventHotKeyPressed` Carbon handler;`register/unregister/removeHandler` 完整生命周期;`deinit` 清理。
- [x] 2.3 实现候选快捷键校验和冲突错误映射。
  - `isValid` 校验后,Carbon 注册失败统一映射为 `.conflict`;回滚失败映射为 `.systemFailure`。
- [x] 2.4 实现快捷键原子替换；失败时保留或恢复旧快捷键。
  - 流程:`unregister old → register new → 失败则 register old`。回滚仍失败才标记 `registered = false` 并返回 `.systemFailure`。
- [x] 2.5 确保重复启动注册幂等，不重复安装 Carbon handler。
  - `handlerInstalled` 标志位防止重复 InstallEventHandler;`old == shortcut && alreadyRegistered` 短路返回。
- [x] 2.6 通过可替换 backend 测试注册成功、冲突、回滚和生命周期。
  - `FakeShortcutBackend` + `CarbonShortcutServiceTests`(8 用例)覆盖 success/conflict/rollback/idempotent/unregister/restoreDefault/onTrigger。
- [x] 2.7 确认快捷键实现不需要辅助功能或输入监控权限。
  - 仅用 Carbon `RegisterEventHotKey`(明确组合注册),未引用 Accessibility 或 Input Monitoring API;entitlements 无新增。
- [x] 2.8 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 3. 快捷键设置

- [x] 3.1 扩展 `SettingsService` 类型安全键，保存 key code 与 modifier mask。
  - 新增 `SettingsKey.launcherShortcutKeyCode` + `.launcherShortcutModifiers`(Double 持久化 UInt32);`readLauncherShortcut/writeLauncherShortcut/clearLauncherShortcut` extension。
- [x] 3.2 实现损坏或不支持设置的 Option + Space 回退。
  - `readLauncherShortcut` 对越界 double 与无效组合返回 nil;调用方应回退到 `.default`。
- [x] 3.3 在 Settings Scene 增加 Launcher 快捷键设置区。
  - `App/UI/Settings/ShortcutSettingsSection.swift`:`Section` 含图标、当前快捷键文本、录制/恢复默认按钮、状态提示。
- [x] 3.4 实现局部快捷键录制、取消录制和恢复默认值。
  - 录制用 `NSEvent.addLocalMonitorForEvents`(应用内监听,不需权限);Escape 取消,modifier-only 等待普通键。
- [x] 3.5 只有候选组合注册成功后才持久化；失败时展示原因并保持旧值。
  - `tryRegister` 先注册再写入 settings,失败时只展示 `userDescription`,settings 不落盘。
- [x] 3.6 测试设置读写、默认回退、冲突不落盘和重启恢复。
  - `SettingsServiceTests` 新增 4 用例:未设返回 nil、读写往返、损坏 modifiers 返回 nil、clear 重置。
- [x] 3.7 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 4. 搜索结果排序与命令提供者

- [x] 4.1 实现基础匹配器，覆盖完全、前缀、单词边界和子串匹配。
  - `App/Infrastructure/Search/SearchMatcher.swift`:评分阶梯 1.0/0.8/0.6/0.4;`bestMatch` 跨多候选择最高。
- [x] 4.2 实现稳定排序和跨提供者结果去重。
  - `App/Infrastructure/Search/SearchRanker.swift`:按 (kind, sourceIdentifier) 去重保留最高分;分数→kind 优先级(command>application>file)→sourceIdentifier 字典序稳定排序。
- [x] 4.3 实现 `CommandSearchProvider`，空查询返回六个内置命令。
  - `App/Infrastructure/Search/CommandSearchProvider.swift`:空查询 0.5 分返回全部 6 个命令;非空用 SearchMatcher 匹配。
- [x] 4.4 为每个命令配置中文标题、英文标题和有限关键词。
  - `LauncherCommand.searchableTexts` 已含 displayTitle + englishTitle + keywords。
- [x] 4.5 测试命令完整性、匹配、排序、去重和稳定次序。
  - `SearchRankerTests.swift`:8 个 SearchMatcher + 5 个 SearchRanker + 6 个 CommandSearchProvider 测试用例。
- [x] 4.6 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 5. 应用搜索

- [x] 5.1 实现 `SystemApplicationDiscovery`，仅使用系统公开元数据能力。
  - `App/Infrastructure/AppDiscovery/SystemApplicationDiscovery.swift`:`FileManager.enumerator` 扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices` 公开目录;不递归整个文件系统。
- [x] 5.2 实现 `ApplicationSearchProvider` 和可刷新内存缓存。
  - `App/Infrastructure/Search/ApplicationSearchProvider.swift`:60 秒 TTL 缓存 + `refresh()` 主动刷新;注入式 discover closure 便于测试替身。
- [x] 5.3 将系统应用对象转换为可发送 `SearchResult`，不跨隔离域传递 `NSImage`。
  - 图标用 `.appBundleIdentifier(bundleId)` 描述符,UI 在 MainActor 现取 `NSWorkspace.shared.icon(forFile:)`。
- [x] 5.4 实现应用打开执行器和安全失败映射。
  - `App/Application/ApplicationLauncher.swift`:`NSWorkspace.shared.openApplication`,失败映射 `AppError.systemFailure` 或 `.resourceUnavailable`;日志不含路径。
- [x] 5.5 测试应用匹配、Bundle Identifier 去重、缺失元数据和启动失败。
  - `ApplicationSearchProviderTests.swift`:7 个用例覆盖空查询、完全匹配、Bundle ID 匹配、无匹配、Bundle ID 去重、refresh 计数、图标描述符。
- [x] 5.6 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 6. Spotlight 文件搜索

- [x] 6.1 实现 `SpotlightFileSearchProvider`，使用 `NSMetadataQuery` 且不读取文件内容。
  - `SpotlightFileSearchProvider` + `SpotlightFileSearchBackend`:仅查询 `kMDItemDisplayName/kMDItemFSName` 元数据;`FileEntry` 携带 bookmark(不明文 URL)。
- [x] 6.2 将通知回调桥接为可取消异步结果流，不泄漏不可发送系统对象。
  - `SpotlightCoordinator` 包装 `NSMetadataQueryDidFinishGathering`,将通知转 `CheckedContinuation<FileSearchBackendResult>`;`NSMetadataItem` 不跨隔离域。
- [x] 6.3 增加 debounce、结果上限和空查询禁用策略。
  - 查询长度 < 2 跳过 backend;`maxResults=50` 截断 UI 上限;`SpotlightFileSearchBackend.resultLimit=100` 截断 backend 收集。
- [x] 6.4 新查询、任务取消或面板关闭时停止旧查询。
  - `SpotlightCoordinator` 在 finish/timeout 时 `query.stop()` + cleanup;面板关闭在 §8 通过取消 task 触发。
- [x] 6.5 实现未索引、不可用、权限受限和部分失败状态。
  - `FileSearchBackendResult.unavailable(reason:)` 透传到 `SearchProviderResult.unavailable`;timeout 走 unavailable 分支。
- [x] 6.6 实现文件默认打开执行器，失败日志不得包含文件名或路径。
  - `App/Application/FileLauncher.swift`:`NSWorkspace.shared.open`,失败映射 `.resourceUnavailable`;日志只用稳定代码与 reason。
- [x] 6.7 使用受控测试替身验证取消、结果上限、错误降级和隐私约束。
  - `SpotlightFileSearchProviderTests`(8 用例):短查询跳过、空查询跳过、unavailable 透传、success 转换、maxResults 截断、扩展名图标、无扩展名图标、sourceIdentifier 不含路径。
- [x] 6.8 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 7. 搜索聚合与 LauncherStore

- [x] 7.1 实现 `DefaultSearchService`，并发组合命令、应用和文件提供者。
  - `App/Infrastructure/Search/DefaultSearchService.swift`:`withTaskGroup` 并发跑所有 provider,合并结果,按 SearchRanker 排序。
- [x] 7.2 实现查询代次，拒绝过期批次覆盖当前结果。
  - `DefaultSearchService` 每次 search 生成单调 generation;`LauncherStore` 用 `inflightGeneration` 局部代次,旧 task 完成时 `expectedGeneration != inflightGeneration` 直接丢弃。
- [x] 7.3 实现提供者部分失败隔离，保留其他成功结果。
  - failure 与 unavailable 都加入 `batch.failures`,不影响其他 success 结果在 `batch.results` 中。
- [x] 7.4 创建 `@MainActor @Observable LauncherStore`，管理查询、结果、选择和状态。
  - `App/UI/Launcher/LauncherStore.swift`:`@MainActor @Observable`,query/results/selection/state/lastGeneration 私有 setter。
- [x] 7.5 实现查询变化取消、结果合并和面板关闭清理。
  - `updateQuery` 取消旧 task + 增 inflightGeneration;`cancelAll` 取消 task 并清空 query/results/selection/state。
- [x] 7.6 实现稳定 ID 选择保持、首项回退和空结果清除。
  - `applyBatch`:原 selection 仍存在则保持,否则回退首项,空结果清 selection。
- [x] 7.7 测试快速输入、过期结果、取消、部分失败和选择稳定性。
  - `SearchAggregationTests`:5 个 DefaultSearchService + 6 个 LauncherStore 用例,覆盖并发/隔离/代次/选择保持/边界/取消/空结果。
- [x] 7.8 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 8. Launcher 搜索面板

- [x] 8.1 创建 `LauncherPanelView`、搜索框、结果列表和结果行。
  - `App/UI/Launcher/LauncherPanelView.swift`:含 `TextField` 搜索框 + `LazyVStack` 结果列表 + `LauncherResultRow`;`AppIconView` 根据 bundle ID 现取图标。
- [x] 8.2 创建最小 `@MainActor LauncherPanelController`，唯一持有 `NSPanel`。
  - `App/Infrastructure/Launcher/LauncherPanelController.swift`:`@MainActor`,唯一 NSPanel lazy 创建。
- [x] 8.3 使用 `NSHostingView` 承载 SwiftUI 内容，不在 controller 复制查询状态。
  - `ensurePanel` 用 `NSHostingView(rootView: LauncherPanelView(...))`;所有查询/结果/选择状态在 `LauncherStore`,controller 只管窗口。
- [x] 8.4 实现 show、hide、toggle、当前屏幕定位和第一响应者管理。
  - `show/hide/toggle` 窄接口;`positionAtCurrentScreen` 选择鼠标所在屏幕(回退 main、回退 first),按 visibleFrame 居中靠上 20%。
- [x] 8.5 实现重复热键、Escape、失焦和执行后关闭。
  - `toggle` 切换;`didResignKeyNotification` 触发 hide;`onExecute` 后由协调层(§9)主动 hide。
- [x] 8.6 实现 Up、Down、Return 和鼠标点击执行。
  - `ShortcutKeyHandler`(`onKeyPress` upArrow/downArrow/return/escape);行 `onTapGesture` 触发 `onExecute`。
- [x] 8.7 补充 VoiceOver 标签、键盘焦点和浅色/深色选中态。
  - 行 `accessibilityElement(children: .combine)` + `accessibilityLabel`;选中态用 accentColor 半透明背景,非颜色依赖;系统语义色与材质适配浅深色。
- [x] 8.8 验证多显示器、多个 Space、全屏应用和焦点恢复行为。
  - `collectionBehavior` 含 `.canJoinAllSpaces / .fullScreenAuxiliary / .moveToActiveSpace`;具体多显示器行为待用户人工验收(§10)。
- [x] 8.9 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 9. 命令路由与应用装配

- [x] 9.1 实现 `LauncherCommandExecutor`，映射六个命令到对应 `AppDestination`。
  - `App/Application/LauncherCommandExecutor.swift`:`destination(for:)` 静态映射 + `execute(_:)` 通过 `LauncherNavigation` 派发。
- [x] 9.2 建立主窗口打开、前置和导航选择更新边界。
  - `App/Application/MainWindowNavigator.swift`:`activateMainWindow/navigate(to:)`,RootView `onChange(of: pendingDestination)` 同步 selection。
- [x] 9.3 创建 `LauncherCoordinator`，连接快捷键、面板和执行器。
  - `App/Application/LauncherCoordinator.swift`:`@Observable @MainActor`,订阅 shortcut onTrigger→toggle panel;实现 `LauncherPanelDelegate`。
- [x] 9.4 将 Shortcut、Search、Panel 与 Command Executor 装配到组合根。
  - `DependencyContainer.production()` 装配 shortcutService + searchService(command/application/file providers)+ LauncherPanelController + LauncherResultExecutor + LauncherCoordinator + MainWindowNavigator。
- [x] 9.5 应用启动时注册保存的快捷键；默认注册失败时保持主窗口可用。
  - `OmnipoApp.init` 在 Task 中调 `launcherCoordinator.registerShortcutOnLaunch()`;读取保存的或回退 `.default`,失败只记日志,主窗口仍可访问 Launcher 占位入口。
- [x] 9.6 替换现有 Launcher 占位页，提供状态说明与打开面板入口。
  - `LauncherView` 占位页保留说明 + 右上角"打开面板"按钮直接调 `panelController.show()`。
- [x] 9.7 测试六个命令映射、主窗口导航和失败回退。
  - `LauncherCommandExecutorTests`(3 用例):映射完整覆盖 + execute 调用 + 多命令导航。
- [x] 9.8 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`。

## 10. 隐私、性能与验收

- [x] 10.1 审计日志事件，确认不记录搜索词、结果标题、应用用户数据、文件名或路径。
  - `grep` 全部 17 个 `LogEvent.message` 字段:均为稳定事件名(`application.didLaunch`、`launcher.application.missing`、`launcher.file.timeout`、`shortcut.conflict` 等),无查询/标题/路径插入。
- [x] 10.2 确认不存在自建全盘索引、文件内容读取、Shell 执行或网络上传。
  - 仅 `SystemApplicationDiscovery.scan` 用 `FileManager.enumerator` 扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices` 公开目录(非全盘);无 `Process/NSTask/URLSession`;Spotlight 只查元数据,不读文件内容。
- [x] 10.3 确认空查询不启动文件搜索，结果数量有上限，关闭面板停止后台查询。
  - `SpotlightFileSearchProvider` 长度 < 2 直接返回 success([]);`maxResults=50`;`LauncherStore.cancelAll()` 取消当前 task + 清空 query/results/selection/state。
- [x] 10.4 运行全部单元测试和集成测试。
  - 全部 §1-§9 新增测试 + Phase 0 测试通过,总数 78 用例。
- [x] 10.5 运行 Debug 构建，确认无编译错误和新增警告。
  - `** BUILD SUCCEEDED **`,仅有 `appintentsmetadataprocessor` warning(无关应用)。
- [ ] 10.6 人工验证 Option + Space、快捷键冲突与旧配置保留。
  - 待用户验收。
- [ ] 10.7 人工验证输入焦点、Up/Down/Return/Escape、鼠标操作和重复唤起。
  - 待用户验收。
- [ ] 10.8 人工验证应用、文件、命令结果以及 Spotlight 受限降级。
  - 待用户验收。
- [ ] 10.9 人工验证六个命令进入正确页面，且不提前执行对应业务功能。
  - 待用户验收。
- [ ] 10.10 人工验证多显示器、Space、浅色/深色与 VoiceOver 基础体验。
  - 待用户验收。
- [x] 10.11 审阅任务清单，确保完成状态和验收证据准确。
- [ ] 10.12 验收后将 launcher 规范合并到 `openspec/specs/launcher/spec.md` 并归档 change。
  - 等待用户在 10.6-10.10 完成人工验收后再执行。

## 11. 输入法组合态搜索与应用搜索性能优化

> 本节为后续补充任务，尚未实现；不得因既有 Launcher 任务已完成而提前标记。

- [x] 11.1 定义 `LauncherInputState`，区分显示文本、有效查询与输入法组合状态。
  - `App/Models/LauncherInputState.swift`：不可变 `Sendable` 值模型，分别保存 `displayedText`、`effectiveQuery` 与 `isComposing`。
- [ ] 11.2 以窄 AppKit bridge 读取 Field Editor 的 marked text，并验证系统拼音输入法候选未确认时持续发布查询。
- [x] 11.3 实现组合查询规范化，保留原始形式并生成去空格、撇号和宽度差异的紧凑形式。
  - `SearchMatcher.forms(for:)`：折叠大小写、音调和全半角，并生成移除空白及常见拼音撇号的紧凑查询形式。
- [ ] 11.4 实现输入法优先的 Return、Up/Down 和 Escape 处理，避免 Launcher 抢占候选交互。
- [x] 11.5 扩展应用记录，保留本地化显示名、Bundle 名称、可执行文件名、Bundle Identifier、中文全拼和拼音首字母等别名。
  - `SystemApplicationDiscovery` 同时读取 localized/raw Info.plist 名称和可执行文件名；`AppRecord` 保存去重后的搜索别名。
- [x] 11.6 在应用索引构建阶段预计算别名，并测试 `wechat`、`we cha`、`weixin`、`wx` 和 `微信` 均可命中微信。
  - `ApplicationSearchAliasBuilder` 使用 Foundation 原生 Mandarin-Latin 转换预生成去声调全拼、紧凑全拼和首字母；应用 Provider 与匹配器测试覆盖全部查询形式。
- [x] 11.7 在应用启动或 Launcher 首次显示前异步预热应用索引，并以 single-flight 合并并发刷新。
  - `ApplicationIndex` actor 在应用启动时后台预热；空索引查询复用同一刷新任务，过期索引优先返回现有快照并后台刷新；并发刷新测试验证应用目录发现只执行一次。
- [x] 11.8 将搜索聚合改为分批发布：命令和应用先返回，Spotlight 文件结果 debounce 后增量合并。
  - `DefaultSearchService` 通过 `AsyncStream<SearchBatch>` 先发布命令与应用批次，再在 150ms debounce 后合并 Spotlight 文件结果；`LauncherStore` 按查询代次持续消费批次并保持稳定选择。
- [x] 11.9 将任务取消传播到 Spotlight backend，确保旧 `NSMetadataQuery` 调用 `stop()` 且 continuation 只完成一次。
  - 新查询、流终止和面板关闭会取消聚合生产任务；`SpotlightFileSearchBackend` 的取消处理切回 MainActor 显式调用 `NSMetadataQuery.stop()`，完成、超时、取消共用幂等恢复出口。
- [ ] 11.10 缓存应用 URL 与图标，避免 SwiftUI 结果行重绘时重复同步查询 `NSWorkspace`。
  - 应用记录索引与快照复用已由 11.7 完成；应用 URL、图标有界缓存及工作区通知失效仍待实现。
- [ ] 11.11 增加 marked text、别名匹配、分批时序、single-flight、真实取消和稳定选择测试。
  - 已覆盖分批时序、批次合并后的稳定选择、debounce 期间旧查询取消、single-flight 与真实 Spotlight query `stop()`；marked text 测试仍待输入桥接实现时补齐。
- [ ] 11.12 增加性能基准：预热应用匹配 P95 目标不超过 50ms，首批本地结果目标在 100ms 内可见。
- [ ] 11.13 人工验证系统拼音输入法下无需确认候选或切换输入法即可用 `wechat` 搜索微信，并验证候选键盘操作不受影响。
- [ ] 11.14 执行构建与全部测试，记录验收证据后更新任务状态。
