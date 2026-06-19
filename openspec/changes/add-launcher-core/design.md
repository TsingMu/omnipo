# 设计：Launcher 核心能力

## 背景

Launcher 同时跨越全局键盘事件、独立浮动面板、异步搜索、系统应用发现、Spotlight 查询和应用内导航。SwiftUI 适合承载查询状态、结果列表和键盘选择，但不能独立提供可靠的 Alfred 式全局面板生命周期，因此需要一个很窄的 AppKit 边界。

本设计保持 SwiftUI 为状态和内容的主要所有者，仅让 AppKit 负责 `NSPanel`、窗口激活、焦点与屏幕定位。系统搜索能力封装在服务层，UI 不直接调用 Carbon、`NSWorkspace` 或 `NSMetadataQuery`。

## 目标

- 无需辅助功能权限即可注册全局快捷键。
- 提供可配置、可恢复、能报告冲突的快捷键服务。
- 提供键盘优先、低延迟、可重复唤起的搜索面板。
- 支持中文拼音输入法 marked text 尚未提交时直接搜索，并保持系统候选交互完整。
- 通过预热应用索引和分批发布结果，使本地应用结果不被 Spotlight 文件查询阻塞。
- 统一应用、文件和功能命令搜索结果模型。
- 支持异步提供者并防止过期结果覆盖当前查询。
- 用稳定命令标识连接现有主窗口导航。
- 保持搜索数据本地处理且不进入日志。

## 非目标

- 不实现剪切板搜索。
- 不扫描文件内容或维护自有索引。
- 不承诺绕过系统设置、Spotlight 索引状态或沙盒限制搜索所有文件。
- 不在本 change 中支持自定义命令、脚本执行、Shell 命令或插件。
- 不实现搜索历史、云同步、使用分析或个性化学习排序。
- 不通过 `CGEventTap` 监听所有键盘输入。

## 总体架构

```text
Carbon Hot Key
      │
      ▼
ShortcutService ──事件──> LauncherCoordinator
                               │
                  show/hide ───┤
                               ▼
                       LauncherPanelController
                          NSPanel + NSHostingView
                               │
                               ▼
                         LauncherStore
                     query / selection / state
                               │
                               ▼
                         SearchService
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       CommandProvider  ApplicationProvider  FileProvider
              │                │                │
              └────────────────┴────────────────┘
                               │
                               ▼
                       CommandExecutor
                               │
                               ▼
                主窗口 AppDestination 导航
```

### 依赖方向

- UI 依赖 `ShortcutService`、`SearchService` 与命令执行协议。
- Infrastructure 实现 Carbon 快捷键、应用发现、Spotlight 查询和 AppKit 面板。
- `SearchResult` 等模型不依赖 `NSImage`、`NSMetadataItem` 或其他不可发送的系统对象。
- `DependencyContainer` 只负责组合具体实现，不承载搜索状态。

## 建议目录

```text
App/
  Application/
    LauncherCoordinator.swift
    LauncherCommandExecutor.swift
  UI/
    Launcher/
      LauncherView.swift
      LauncherPanelView.swift
      LauncherSearchField.swift
      LauncherResultList.swift
      LauncherResultRow.swift
      LauncherStore.swift
    Settings/
      ShortcutSettingsSection.swift
  Services/
    ShortcutService.swift
    SearchService.swift
  Models/
    KeyboardShortcut.swift
    SearchResult.swift
    LauncherCommand.swift
  Infrastructure/
    Shortcut/
      CarbonShortcutService.swift
    Search/
      DefaultSearchService.swift
      CommandSearchProvider.swift
      ApplicationSearchProvider.swift
      SpotlightFileSearchProvider.swift
    AppDiscovery/
      SystemApplicationDiscovery.swift
    Launcher/
      LauncherPanelController.swift
```

目录是实现指导，不要求为了结构完整创建无内容文件。

## 模型设计

### KeyboardShortcut

`KeyboardShortcut` 是可持久化、可比较、满足 `Sendable` 的值模型，至少包含：

- 物理键标识或稳定 key code。
- 修饰键集合。
- 面向用户的显示文本。
- 是否满足最低有效约束。

默认值为 Option + Space。首版只接受一个非修饰键加至少一个受支持修饰键，拒绝仅修饰键、无修饰键和系统保留组合。

持久化时保存稳定的键码和修饰键位掩码，不保存与当前键盘布局绑定的临时对象。显示文本可根据当前布局生成，但持久化身份不得依赖本地化字符串。

### SearchResult

`SearchResult` 是不可变、满足 `Identifiable`、`Hashable` 与 `Sendable` 的值模型，至少包含：

- 稳定结果 ID。
- `application`、`file`、`command` 类型。
- 标题与可选副标题。
- 匹配分数。
- 来源标识。
- 可发送的图标描述，而不是直接持有 `NSImage`。
- 执行载荷的安全标识。

文件 URL 不得用于日志、分析或稳定 ID 的明文输出。若执行需要 URL，应由受控载荷或提供者解析，并限制在当前进程内存中。

### LauncherCommand

使用稳定枚举标识内置命令：

- `openClipboard`
- `scanDisk`
- `uninstallApplication`
- `auditPermissions`
- `inspectWeChatStorage`
- `openSystemMonitor`

命令标题和关键词可本地化，执行逻辑只依赖稳定标识，不依赖显示文案。

## ShortcutService

### 协议职责

- 提供当前配置和默认配置。
- 注册、替换和注销全局快捷键。
- 发布快捷键触发事件。
- 区分快捷键冲突、无效组合、系统注册失败和服务不可用。
- 在替换失败时保持旧注册有效。

### 实现选择

使用 Carbon `RegisterEventHotKey` 实现。该方式只注册明确组合，不监听全部键盘输入，因此不需要辅助功能或输入监控权限。

不使用 `CGEventTap`，因为本 change 只需要一个全局热键，持续监听全局键盘事件会扩大权限和隐私面。

### 原子替换策略

1. 校验候选快捷键。
2. 尝试注册候选快捷键。
3. 注册成功后再注销旧快捷键。
4. 更新内存状态和本地设置。
5. 若注册失败，释放候选资源，继续保留旧快捷键并返回明确错误。

若系统 API 无法同时保留两个注册，具体实现必须提供等价的回滚：旧快捷键注销后候选注册失败时，立即重新注册旧快捷键。设计和测试必须覆盖该路径。

### 生命周期

- 服务随应用进程创建并由组合根持有。
- 应用启动后读取本地设置并注册；不存在设置时使用 Option + Space。
- 服务销毁或应用终止时注销 Carbon handler 和 hot key reference。
- 多次启动注册必须幂等，不重复安装事件处理器。

## 快捷键设置录制

设置窗口增加 Launcher 快捷键区域：

- 展示当前有效快捷键。
- 提供进入录制状态、取消录制和恢复默认值操作。
- 录制期间只处理设置控件中的局部键盘事件，不安装新的全局键盘监听。
- Escape 取消录制，Delete 或清除操作的产品语义在实现前由任务明确测试。
- 候选组合无效或冲突时展示原因，UI 恢复显示当前有效快捷键。
- 只有注册成功后才持久化新值。

## SearchService

### 协议职责

- 接收查询文本和查询上下文。
- 异步返回一批或多批搜索结果。
- 支持取消上一查询。
- 对不同提供者的错误进行隔离和降级。
- 不记录查询文本、文件名或路径。

### 查询策略

每次输入变化生成单调递增的查询代次：

1. 取消上一代查询任务。
2. 对用户输入做内存中的轻量规范化。
3. 命令提供者立即返回本地结果。
4. 应用提供者从已预热的本地索引返回首批结果。
5. 文件提供者经过短暂 debounce 后执行，不阻塞命令和应用首批结果。
6. 每批结果携带查询代次和是否为最终批次的状态。
7. `LauncherStore` 只接受当前代次结果，并增量合并不同提供者的批次。
8. 合并、去重并生成稳定排序。

为了避免每个按键触发昂贵 Spotlight 查询，文件提供者使用短暂 debounce。命令和已缓存应用结果不应被同一 debounce 阻塞。

### 输入法组合文本

Launcher 必须区分已提交文本与输入法 marked text。中文拼音输入法仍显示候选窗口时，用户输入的拉丁字母也属于有效查询，不要求先确认候选或切换输入法。

搜索输入状态至少包含：

- `displayedText`：搜索框当前显示的完整文本，保留系统输入法的组合态表现。
- `effectiveQuery`：仅用于当前进程内匹配的规范化查询。
- `isComposing`：当前是否存在 marked text。

普通 SwiftUI `TextField` 若不能在目标 macOS 版本上稳定发布 marked text，应使用窄 `NSViewRepresentable` 包装 `NSTextField`，通过 Field Editor 的 `NSTextView.hasMarkedText()`、`markedRange()` 和文本变化通知读取组合状态。不得通过全局事件监听或自行拼接 `keyDown` 字符模拟输入法。

查询规范化保留原始形式，同时生成去除拼音分词空格、撇号和宽度差异的紧凑形式。例如输入法显示 `we cha` 时，可生成 `wecha` 用于前缀匹配；搜索框仍显示系统提供的原始组合文本。

组合期间的局部键盘事件必须优先交给输入法：

- Return 用于确认候选，不执行 Launcher 结果。
- Up/Down 用于移动输入法候选，不移动 Launcher 选择。
- Escape 优先取消当前组合；不存在 marked text 时才关闭 Launcher。

### 分批结果与低延迟预算

搜索聚合采用“本地优先、远端元数据补充”的分批模型：

1. 命令和已缓存应用在内存中完成匹配并立即发布首批结果。
2. Spotlight 文件查询独立 debounce，完成后合并为后续批次。
3. 文件查询失败或达到超时，不延迟、清空或撤回已经显示的本地结果。
4. 新查询到达时，取消旧聚合任务并显式停止旧 `NSMetadataQuery`。

在固定测试数据和预热索引条件下，本地应用匹配的服务层目标为 P95 不超过 50ms；用户可见首批本地结果目标为 100ms 内。该预算不包含首次应用索引构建和系统 Spotlight 延迟，但首次构建不得阻塞输入主线程。

### 排序原则

排序至少考虑：

1. 完全匹配。
2. 前缀匹配。
3. 单词边界匹配。
4. 子串或基础模糊匹配。
5. 结果类型优先级。
6. 稳定次级排序，避免列表跳动。

空查询默认只显示内置命令和可选的有限应用建议，不枚举大量文件。首版不进行基于用户历史的学习排序。

### 去重原则

- 命令按稳定命令 ID 去重。
- 应用优先按 Bundle Identifier，缺失时使用规范化应用 URL 的进程内标识。
- 文件按标准化 URL 的进程内标识去重。
- 去重标识不得进入公开日志。

## 搜索提供者

### CommandSearchProvider

- 完全在内存中工作。
- 空查询返回全部六个内置命令。
- 支持中文标题、英文标题和有限关键词匹配。
- 不执行命令，只生成结果。

### ApplicationSearchProvider

- 使用系统元数据和 `NSWorkspace` 能力发现可启动应用。
- 不自行递归遍历整个文件系统。
- 缓存应用的安全元数据，并在应用启动或 Launcher 首次显示前异步预热。
- 使用 single-flight 刷新；缓存为空或过期时，同一时刻只允许一个应用发现任务运行，其他查询复用该任务或已有快照。
- 索引保留本地化显示名、`CFBundleDisplayName`、`CFBundleName`、可执行文件名和 Bundle Identifier 等别名，不因选择显示标题而丢弃其他可搜索名称。
- 对中文应用名称预计算去声调全拼、紧凑全拼和拼音首字母，例如 `微信` 生成 `wei xin`、`weixin` 和 `wx`；转换在索引构建时完成，不在每次按键时重复执行。
- 启动应用使用 `NSWorkspace` 的公开 API。
- 应用缺少图标、Bundle Identifier 或无法启动时提供明确降级。

应用 URL 与图标由 `@MainActor ApplicationResourceCache` 统一解析和持有，缓存键为 Bundle Identifier，并使用固定容量的 LRU 淘汰策略。`NSImage` 不进入可发送模型或 Actor；SwiftUI 结果行只在 `.task(id:)` 中请求资源并保存局部显示状态，不在 `body` 重绘期间同步调用 `NSWorkspace`。

缓存监听 `NSWorkspace` 的文件操作、卷挂载与卸载通知。收到可能改变应用位置或可用性的通知后，缓存整体失效并通过窄回调触发 `ApplicationIndex` single-flight 后台刷新；通知内容、应用路径和 Bundle Identifier 不写入日志。应用执行器复用同一缓存中的 URL，缓存未命中时才调用工作区 API 解析。

### SpotlightFileSearchProvider

- 使用 `NSMetadataQuery` 查询文件元数据。
- 不读取文件内容。
- 限制返回数量，避免无界结果和 UI 压力。
- 将通知回调桥接为可取消的异步边界。
- 查询取消、面板关闭或新查询到达时停止旧 `NSMetadataQuery`。
- 仅返回系统允许访问或公开的元数据。

## NSPanel 与 SwiftUI 边界

### SwiftUI 的限制

Launcher 需要跨应用唤起、无 Dock 导航依赖、居中于当前屏幕、可靠成为键盘焦点、失去焦点时关闭，并在重复热键时切换显示。这些窗口行为不能仅依靠普通 SwiftUI `WindowGroup` 稳定表达。

### 最小 AppKit 边界

使用一个 `@MainActor LauncherPanelController`：

- 唯一拥有长生命周期 `NSPanel`。
- 用 `NSHostingView` 承载 `LauncherPanelView`。
- 提供 `show()`、`hide()` 和 `toggle()` 窄接口。
- 负责当前屏幕定位、窗口层级、激活和第一响应者。
- 观察窗口失去 key 状态并触发隐藏。
- 不保存查询结果、不执行搜索、不承担业务路由。

SwiftUI 的 `LauncherStore` 是查询、结果、选择、加载状态和错误状态的唯一事实来源。不得在 `NSPanel` controller 中复制这些状态。

### 面板行为

- 快捷键触发时显示在当前鼠标所在屏幕或当前活动窗口所在屏幕的可见区域上部居中位置。
- 已显示时再次触发快捷键关闭面板。
- 显示后搜索字段立即成为第一响应者。
- Escape 关闭并清理当前瞬态查询。
- 失去 key 状态时关闭；执行结果后默认关闭。
- 面板关闭后取消未完成搜索，避免后台继续工作。
- 面板不进入普通窗口恢复流程，不持久化敏感查询状态。

具体 style mask、level 与 collection behavior 在实现任务中通过人工验收确定，但不得造成面板始终覆盖全屏应用或抢占其他应用焦点后无法恢复。

## LauncherStore

`LauncherStore` 标注为 `@MainActor @Observable`，负责：

- 查询文本。
- 当前查询代次。
- 已合并结果。
- 当前选中结果 ID。
- loading、empty、partial failure 状态。
- 键盘选择移动和执行请求。
- 面板关闭时清理与取消。

选择使用稳定结果 ID，而不是数组下标。结果异步更新后：

- 若原选择仍存在，保持选择。
- 若原选择消失，选择第一个可执行结果。
- 无结果时清除选择。

## 键盘与辅助功能

- 输入普通字符更新查询。
- 输入法 marked text 变化同样更新有效查询，但不强制提交候选。
- Up/Down 在可执行结果间循环或按规范定义的边界移动。
- Return 执行当前选择。
- Escape 关闭面板。
- Tab 行为保持可访问，不通过全局键盘监听拦截系统必要导航。
- 每个结果提供类型、标题和必要副标题的 VoiceOver 标签。
- 颜色、选中态和焦点不得只依赖颜色差异。

当输入法处于组合状态时，Return、Up/Down 和 Escape 遵循“输入法优先”规则，不得被 Launcher 快捷操作提前消费。

键盘事件优先使用 SwiftUI 命令、焦点和局部事件处理；只有搜索字段或列表无法可靠覆盖的局部行为才使用窄 AppKit bridge。

## 命令执行与导航

`LauncherCommandExecutor` 只接收稳定命令 ID，并将其映射到 `AppDestination`：

| Launcher 命令 | 目标 |
| --- | --- |
| 打开剪切板 | `.clipboard` |
| 扫描磁盘 | `.cleaner` |
| 卸载应用 | `.uninstaller` |
| 权限审计 | `.permissionAudit` |
| 查看微信占用 | `.wechatManager` |
| 打开系统监控 | `.systemMonitor` |

执行时：

1. 激活 Omnipo。
2. 打开或前置主窗口。
3. 更新主窗口导航目标。
4. 隐藏 Launcher 面板。

本 change 只导航到现有页面，不触发对应功能的扫描、删除或权限读取。

应用结果交给应用启动执行器，文件结果交给系统默认打开行为。执行失败通过统一 `AppError` 显示安全原因，不把完整路径写入日志。

## 设置与依赖装配

### SettingsService 扩展

增加类型安全的快捷键设置键，保存：

- key code。
- modifier mask。

只有新组合注册成功后才写入。读取到损坏或不支持的值时：

- 不崩溃。
- 回退到 Option + Space。
- 记录不含原始设置值的稳定诊断事件。

### DependencyContainer 扩展

组合根新增：

- `ShortcutService`
- `SearchService`
- `LauncherPanelController` 或其窄协议
- `LauncherCommandExecutor`

为避免 `DependencyContainer` 变成业务状态容器，`LauncherStore` 由 Launcher 协调层创建和持有，不作为任意全局可变状态暴露。

## 并发模型

- Carbon 事件和所有面板操作切换到 `MainActor`。
- `LauncherStore` 位于 `MainActor`。
- 搜索聚合与可发送结果在异步任务中执行。
- 不可发送的 `NSMetadataQuery`、`NSMetadataItem`、`NSWorkspace` 或 AppKit 对象封装在对应基础设施隔离域内，不跨 Actor 泄漏。
- 每次查询使用结构化任务；新查询和面板关闭会取消旧任务。
- 提供者必须协作检查取消，不在取消后继续发布结果。

## 错误与降级策略

### 快捷键冲突

- 明确展示“该快捷键已被系统或其他应用占用”。
- 保留上一次有效配置。
- 若首次默认快捷键注册失败，应用仍可通过主窗口使用 Launcher，并在设置中提示重新配置。

### Spotlight 不可用或未完成索引

- 命令与应用搜索继续可用。
- 文件分区显示不可用、索引中或受限原因。
- 不回退到递归扫描磁盘。

### App Sandbox 或隐私限制

- 只使用系统公开 API 返回允许访问的结果。
- 无权访问时展示受限状态，不请求无关权限。
- 不以完全磁盘访问作为 Launcher 的前置条件。

### 面板焦点失败

- 尝试激活应用并让搜索字段成为第一响应者。
- 若无法获得焦点，关闭面板并保留主窗口入口，不安装全局键盘事件窃听作为补偿。

### 部分提供者失败

- 单个提供者失败不得清空其他成功结果。
- UI 展示非阻塞的部分失败提示。
- 日志只记录提供者类型和稳定错误代码。

## 隐私与安全

- 搜索词仅存在于进程内存，不持久化。
- 不记录搜索词、文件名、文件路径或结果标题。
- 文件搜索只查询元数据，不读取文件内容。
- 不上传搜索行为或结果。
- 文件和应用打开使用系统公开 API。
- 不执行 Shell 字符串，不解释搜索词为命令行。
- 不使用辅助功能、输入监控或完全磁盘访问权限。
- 面板关闭时清理瞬态查询与结果。

## 性能约束

- 空查询不得触发无界文件搜索。
- 文件结果设置合理上限，首版建议不超过 50 条候选进入 UI。
- 输入 debounce 仅作用于昂贵提供者。
- 应用元数据允许内存缓存，但必须可刷新且不保存隐私查询。
- 应用索引异步预热并合并并发刷新，不允许快速输入触发重复目录扫描。
- 本地命令与应用以首批结果发布，不等待 Spotlight 文件提供者完成。
- 应用路径和图标使用有界缓存，不在每次结果行重绘时重复解析。
- Spotlight debounce 后执行；任务取消必须传播到 `NSMetadataQuery.stop()`，不能只丢弃最终结果。
- 面板关闭后停止搜索和不必要的后台工作。
- 搜索不得造成主线程文件遍历或明显输入卡顿。

## 测试策略

### 单元测试

- 快捷键合法性、序列化和默认值。
- 快捷键替换成功、冲突和回滚。
- 命令目录完整性与关键词匹配。
- 搜索结果合并、排序、去重和稳定性。
- 查询代次拒绝过期结果。
- marked text、已提交文本和紧凑拼音查询的状态转换。
- 中文名称全拼、紧凑拼音、首字母及英文别名匹配。
- 输入法组合期间 Return、Up/Down、Escape 不触发 Launcher 操作。
- 延迟文件提供者不阻塞本地应用首批结果。
- 应用索引并发刷新保持 single-flight。
- 取消查询后不再发布结果。
- 选择在异步结果变化后的保持与回退。
- 六个命令到 `AppDestination` 的映射。
- 日志事件不包含查询词、文件名或路径。

### 集成测试

- 使用受控 mock provider 验证并发批次与部分失败。
- 使用可替换 Shortcut backend 验证注册生命周期，不在单元测试抢占真实全局快捷键。
- Spotlight 集成测试只验证适配器行为，不依赖开发机存在特定私人文件。

### 人工验收

- 从其他应用按 Option + Space 打开面板。
- 重复快捷键、Escape、失焦均能正确关闭。
- 多显示器和不同 Space 下位置合理。
- 搜索框自动聚焦，Up/Down/Return 可完整操作。
- 中文拼音输入法下输入 `wechat`，不确认候选即可显示微信；候选窗口、确认和取消行为正常。
- 冷启动首次唤起无主线程扫描卡顿，预热后应用结果明显先于文件结果出现。
- 快捷键冲突提示且旧快捷键继续有效。
- 六个命令打开正确页面。
- Spotlight 不可用时降级文案清晰。
- 浅色、深色和 VoiceOver 基础可用。

## 备选方案

### 使用 SwiftUI Window Scene 作为 Launcher

不采用。普通 Scene 难以稳定满足跨应用热键唤起、当前屏幕定位、第一响应者、失焦隐藏和重复热键切换等组合行为。

### 使用 CGEventTap 实现全局快捷键

不采用。该方案会扩大键盘监听范围，并可能引入辅助功能或输入监控权限，不符合最小权限原则。

### 引入第三方快捷键或模糊搜索库

暂不采用。首版所需能力可以通过 Carbon 和小型本地排序器实现；若后续需求明显超出原生方案，再通过独立 change 评估。

### 自建文件索引

不采用。自建索引会增加磁盘遍历、隐私、存储、一致性和后台负载风险；本 change 使用 Spotlight 并接受系统限制。
