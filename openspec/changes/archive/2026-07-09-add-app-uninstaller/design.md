# 设计：App Uninstaller 核心能力

## 背景

Omnipo 的 Uninstaller 当前只是占位页面。项目已经具备应用发现、真实图标解析、文件扫描、权限降级、日志脱敏和任务状态模型等基础能力，可以在这些能力之上实现一个安全保守的应用卸载器。

本 change 的关键需求是：卸载应用时用户可以选择是否完全删除文件；完全删除时必须删除该应用及缓存等关联文件。设计上需要把“完全删除”落实为可解释、可预览、可确认的操作，而不是把所有名称相似的文件都静默删除。

## 目标

- 枚举本机可见应用并展示基本信息。
- 支持普通卸载：删除应用本体。
- 支持完全删除：在用户授权且系统允许的范围内，删除应用本体和用户选中的可安全归属关联文件。
- 删除前提供预览、模式选择、逐项选择和二次确认。
- 删除执行优先移动到废纸篓，减少误删后不可恢复风险。
- 对权限不足、系统保护、归属不明确和共享风险做明确降级。
- 日志只记录稳定错误码和汇总信息，不记录用户路径或文件名。

## 非目标

- 不强制删除系统保护应用。
- 不绕过 macOS 安全机制。
- 不删除用户文档、聊天记录、钥匙串、浏览器数据或其他高敏内容。
- 不实现批量卸载、远程规则库或自动推荐卸载。
- 不在首版强制处理登录项、LaunchAgent、LaunchDaemon、系统扩展、内核扩展或浏览器插件。
- 不把 Uninstaller 和 Cleaner 混成一个大而全清理器；Uninstaller 只处理由选定应用驱动的卸载链路。

## 用户流程

```text
打开 Uninstaller
  │
  ▼
应用发现与列表展示
  │
  ▼
选择应用
  │
  ├── 普通卸载
  │     ▼
  │   预览应用本体
  │
  └── 完全删除
        ▼
      扫描关联文件
        ▼
      展示关联文件分组与风险
        ▼
      用户逐项选择

确认删除
  │
  ▼
移动到废纸篓
  │
  ▼
显示结果与失败/跳过原因
```

## 架构设计

### 建议目录

```text
App/
  Application/
    UninstallerStore.swift
  Models/
    InstalledApplication.swift
    AppUninstallPlan.swift
    AppAssociatedFile.swift
    UninstallMode.swift
    UninstallExecutionResult.swift
  Services/
    UninstallerService.swift
  Infrastructure/
    Uninstaller/
      DefaultUninstallerService.swift
      InstalledApplicationScanner.swift
      AssociatedFileScanner.swift
      TrashDeletionExecutor.swift
  UI/
    Uninstaller/
      UninstallerView.swift
      UninstallerApplicationList.swift
      UninstallerDetailView.swift
      UninstallPlanPreview.swift
      UninstallConfirmationDialog.swift
```

目录是实现指导，不要求一次性建齐；实现时应保持 UI 依赖服务协议，系统文件操作留在 Infrastructure。

### 服务边界

`UninstallerService` 建议覆盖：

- `installedApplications()`：枚举可见应用。
- `buildPlan(for:mode:)`：生成普通卸载或完全删除计划。
- `execute(plan:)`：执行用户确认后的删除计划。
- `cancel()`：取消长时间扫描或执行。

UI 不直接访问 `FileManager`、`NSWorkspace` 或文件系统目录。

### 当前 Entitlement 假设与权限架构

当前工程的 `Omnipo.entitlements` 是空 `dict`；本 change 不应假设当前已经启用 App Sandbox，也不应把 Full Disk Access 视为解除所有文件系统限制的通行证。Uninstaller 必须按“当前进程真实拥有的能力”构建预览和执行计划。

如果后续启用 App Sandbox，则卸载链路会受到两类限制：容器重定向/TCC 导致的**读取**限制，与沙箱路径**写保护**。首版设计采用“用户授权目录优先，Finder automation 作为删除路径”的策略；Full Disk Access 只作为受保护路径读取的补充引导，不承诺解除全部 sandbox 或文件系统限制。

#### 读取：用户授权目录优先，FDA 作为补充

关联文件扫描可能需要读取真实的 `~/Library/{Caches, Application Support, Preferences, Logs, Saved Application State, Containers, Group Containers}`。首版读取策略：

- 优先使用用户通过 `NSOpenPanel` 授权的目录与 security-scoped bookmark。
- 已授权目录内只读取路径、大小、归属和修改时间等元数据，**不读取**钥匙串、聊天数据库、浏览器 Profile 等受保护内容。
- 对未授权、TCC 阻止、沙箱不可达或文件系统拒绝的目录，返回 unavailable 并展示原因，不误报为空。
- 可复用 permission-audit 已建立的 Full Disk Access 引导文案和系统设置跳转，但 FDA 只能作为受保护路径读取的补充条件；即使用户授予 FDA，也必须以实际读取结果为准。

#### 删除：Finder automation 或授权目录内 Trash

首版删除优先移动到废纸篓：

- 对用户授权目录内的项目，可使用 `FileManager.trashItem`。
- 对 `/Applications` 等当前进程无写权限的项目，可通过 Apple Event 驱动 **Finder** 执行删除，前提是用户授权 Omnipo 控制 Finder。
- 若采用 Finder automation，需要新增 `com.apple.security.automation.apple-events` entitlement，并在 Info.plist 增加 `NSAppleEventsUsageDescription`，说明用途仅为把用户确认的应用和关联文件移到废纸篓。
- Finder `delete` 语义为移到废纸篓，天然满足「Trash 优先」。
- 实现层只允许针对用户确认计划中的文件执行 Finder 删除；禁止任意 AppleScript 能力扩散。
- 路径以**结构化 Apple Event 参数**传递或严格转义，禁止 AppleScript 字符串拼接，防范路径注入。
- Finder automation 授权被拒绝时，删除不可执行或只能退回到用户授权目录内 Trash 删除，UI 必须展示原因。

#### DeletionExecutor 抽象

`UninstallerService.execute(plan:)` 委托可切换的 `DeletionExecutor`：

- `FinderAutomationDeletionExecutor`（首版主路径）：通过 Finder 删除，覆盖 `/Applications`、`~/Applications`、`~/Library` 关联文件。
- `SandboxTrashDeletionExecutor`（回退/测试桩）：用户授权目录内 `FileManager.trashItem`，用于未授 automation 时的有限降级与测试。

切换 executor 不影响 UI 与计划生成层。

## 数据模型

### InstalledApplication

至少包含：

- `id`
- `bundleIdentifier`
- `displayName`
- `localizedDisplayName`
- `bundleURL`
- `executableURL`
- `iconIdentifier`
- `bundleSizeBytes`
- `isSystemProtected`
- `isRunning`

应用名称优先使用本地化显示名；图标复用现有应用资源解析能力。

### UninstallMode

- `removeApplicationOnly`
- `removeApplicationAndAssociatedFiles`

UI 文案可显示为“仅卸载应用”和“完全删除”。

### AppAssociatedFile

至少包含：

- `id`
- `category`
- `displayName`
- `url`
- `sizeBytes`
- `ownershipConfidence`
- `riskLevel`
- `isDefaultSelected`
- `isUserSelectable`
- `unavailableReason`

类别建议包括：

- `applicationBundle`
- `cache`
- `applicationSupport`
- `preferences`
- `logs`
- `savedApplicationState`
- `container`
- `groupContainer`
- `launchAgent`
- `other`

每个类别必须提供用户可读的删除后果说明，用于完全删除预览和二次确认。说明应短而具体，不夸大风险，也不把高风险项包装成安全项。

### AppUninstallPlan

包含：

- 目标应用
- 卸载模式
- 应用本体项
- 关联文件项
- 默认选中集合
- 总大小
- 风险摘要
- 不可删除/不可读取项

普通卸载计划只默认包含应用本体；完全删除计划包含应用本体和可安全归属关联文件。

## 应用发现

首版扫描公开应用目录：

- `/Applications`
- `/System/Applications`
- `/System/Library/CoreServices`
- `~/Applications`

规则：

- 只把 `.app` bundle 作为应用候选。
- 系统保护路径中的应用可展示，但默认不可删除。
- 用户目录和 `/Applications` 下可写应用可进入卸载流程。
- 扫描失败不阻塞其他目录，页面展示部分不可用原因。

## 关联文件扫描策略

完全删除模式必须扫描关联文件。扫描以 `bundleIdentifier`、应用显示名、可执行名和已知本地化名称作为候选键，但自动选中必须保守。

### 默认扫描位置

首版覆盖用户域常见位置：

- `~/Library/Caches`
- `~/Library/Application Support`
- `~/Library/Preferences`
- `~/Library/Logs`
- `~/Library/Saved Application State`
- `~/Library/Containers`
- `~/Library/Group Containers`

后续可扩展：

- `~/Library/HTTPStorages`
- `~/Library/WebKit`
- `~/Library/Cookies`
- `~/Library/Application Scripts`
- `~/Library/LaunchAgents`

### 归属判断

高置信度，可默认选中：

- 路径组件或文件名与完整 bundle identifier 完全匹配。
- `Preferences/<bundle-id>.plist`。
- `Saved Application State/<bundle-id>.savedState`。
- `Containers/<bundle-id>`。

中置信度，可展示但默认不选中或要求用户确认：

- 目录名与应用显示名完全匹配。
- `Application Support` 中目录名与可执行名完全匹配。
- `Logs` 中目录名与应用名完全匹配。

低置信度，不默认选中：

- 仅包含部分应用名称。
- 仅通过模糊匹配命中。
- 位于共享容器、公共缓存或多应用厂商目录中。

不可自动删除：

- 用户文档目录。
- 系统目录。
- 钥匙串。
- 浏览器 Profile 数据。
- 聊天数据和消息数据库。
- 归属无法解释的 Group Containers。

## 删除策略

### 普通卸载

普通卸载只处理应用本体：

- 删除目标为 `.app` bundle。
- 删除前确认应用名称、路径来源、大小和是否正在运行。
- 正在运行的应用应提示用户先退出；首版可提供“稍后重试”，不强制 kill。

### 完全删除

完全删除处理：

- 应用本体。
- 用户明确选中的关联文件。
- 默认选中的高置信度关联文件。

完全删除预览必须分组展示：

- 应用本体。
- 缓存。
- 支持文件。
- 偏好设置。
- 日志。
- 容器。
- 其他。
- 不可删除/需手动处理。

### 分类删除后果说明

完全删除预览必须在每个分类标题或说明区域展示删除后果。首版建议文案语义如下，具体 UI 文案可按空间压缩，但不得省略后果信息：

- 应用本体：删除后该应用将无法从原位置启动；如果需要继续使用，需要重新安装。
- 缓存：删除后通常可释放空间，应用下次启动可能重新生成缓存，首次打开可能变慢。
- Application Support：可能包含应用本地数据库、下载资源、离线数据、插件或账号相关本地状态；删除后应用数据可能无法恢复。
- Preferences：删除后应用偏好设置、窗口布局、最近使用项或登录状态可能被重置。
- Logs：删除后会移除诊断日志，通常不影响应用功能，但可能影响后续排查问题。
- Saved Application State：删除后应用窗口恢复状态和上次打开状态会丢失。
- Containers：可能包含沙盒应用的本地数据、缓存和配置；删除后该应用的沙盒数据可能无法恢复。
- Group Containers：可能被同一开发者的多个应用共享；删除后可能影响同组应用，默认不选中，除非归属清晰且用户明确选择。
- Launch Agents：删除后相关后台启动项或辅助进程可能不再自动运行；首版默认只展示或谨慎处理。
- 其他：删除后果取决于文件来源；默认不选中，必须展示归属原因和风险说明。
- 不可删除/需手动处理：不会被本次操作删除；说明应解释是权限不足、系统保护、归属不明确还是共享风险。

分类说明必须跟随预览分组展示，而不是只放在帮助文档里。二次确认中至少要再次提示：完全删除会移除选中的应用数据，部分数据删除后无法由 Omnipo 恢复。

用户必须能取消选择任意可选关联文件。不可选择项只展示原因，不参与删除。

### 移动到废纸篓

删除优先移动到废纸篓：用户授权目录内使用 `FileManager.trashItem`，无写权限路径使用 Finder automation 的 `delete`（见「当前 Entitlement 假设与权限架构」）。原因：

- 保持 macOS 用户预期。
- 降低误删损失。
- 与”删除前确认”形成双保险。
- Finder automation 在用户授权后可覆盖 `/Applications` 等当前进程无写权限路径。

如果移动到废纸篓失败：

- 显示失败原因（含 automation 未授权、Finder 拒绝、目标不存在等稳定分类）。
- 不自动改为永久删除。
- 首版不提供「应用内永久删除」按钮；如用户要求永久删除，引导其手动清空废纸篓或在 Finder 中处理。

### 部分成功

删除执行应允许部分成功：

- 已删除项标记成功。
- 失败项展示稳定原因。
- 跳过项展示跳过原因。
- 后续可重新执行剩余项。

## 权限与系统限制

- 对无权读取的目录，显示”无法读取/需要授权”，不得显示为空。
- 对无权删除的文件，显示”无法删除/权限不足”，不得重试破坏性命令。
- 对 SIP 或系统保护项，显示”系统保护”，默认不可删除。
- 对正在运行或被锁定的应用，显示”正在使用/被锁定”，要求用户关闭后重试。
- 关联文件扫描以用户授权目录为首选：未授权、FDA 不足、TCC 阻止或沙箱不可达时，对应分类 unavailable 并引导，不得误报为空。
- 删除以 Trash-first 为前置：未授 Finder automation 时，仅允许当前进程已授权可写范围内的 Trash 删除；其余项目展示”需要 Finder 自动化授权”或”需要授权目录”。
- FDA、security-scoped bookmark 与 automation 的授权状态需在 UI 可见，且不得把”未授权”误报为”无数据”或”未发现应用”。

## UI 设计

Uninstaller 页面建议采用主窗口工具型布局：

- 左侧/上方应用列表：搜索、排序、大小、来源。
- 右侧详情：应用信息、卸载模式、扫描状态、预览列表。
- 底部操作：刷新、生成预览、取消、确认卸载。

交互要求：

- 默认不开始删除，必须用户点击确认。
- 完全删除模式切换后重新生成预览。
- 预览列表中使用 checkbox 控制可选关联文件。
- 每个预览分组展示分类说明，说明该类文件删除后的后果。
- 高风险项用明确状态展示，不默认勾选。
- 删除中显示进度，允许取消未开始的剩余项。

## 日志与隐私

允许日志：

- 应用发现开始/结束。
- 发现应用数量。
- 生成计划成功/失败。
- 删除执行成功/失败汇总。
- 稳定错误码。

禁止日志：

- 用户路径。
- 文件名。
- bundle 完整路径。
- 关联文件明细。
- 应用私有数据。
- 删除预览中的具体条目。

日志中如需标识目标应用，应优先使用 hash 或只使用 bundle identifier 的稳定分类；不得包含本地路径。

## 测试策略

### 模型与计划

- 卸载模式序列化与默认值。
- 关联文件风险等级与默认选中规则。
- 普通卸载计划只包含应用本体。
- 完全删除计划包含应用本体和高置信度关联文件。

### 扫描

- 应用扫描跳过非 `.app`。
- 系统保护应用标记不可删除。
- 关联文件扫描按 bundle identifier 命中缓存、偏好设置、支持文件。
- 模糊匹配项不默认选中。
- 无权限目录返回 unavailable，不误报为空。

### 删除

- 删除执行优先调用 Trash executor 或 Finder automation delete。
- Trash/Finder 删除失败时不自动永久删除。
- 首版不提供应用内永久删除。
- 部分失败保留逐项结果。
- 取消时未开始项保持 skipped/cancelled。

### 日志

- 日志不包含路径、文件名和关联文件明细。
- 错误上下文只包含稳定码和汇总计数。

## 风险与降级策略

### 误删关联文件

风险：应用名模糊匹配可能命中不属于该应用的数据。

策略：

- 高置信度才默认选中。
- 中低置信度必须用户手动选择。
- 共享容器默认不选中，归属不明则不可删除。

### 删除不可恢复

风险：用户手动清空废纸篓后无法恢复。

策略：

- 默认只移动到废纸篓。
- Trash/Finder 删除失败不自动永久删除。
- 首版不提供应用内永久删除；需要永久删除时引导用户到 Finder/废纸篓自行处理。

### 权限不足

风险：无权读取/删除导致预览不完整或执行失败。

策略：

- 明确展示 unavailable，不误报为空。
- 首版使用用户授权目录与 security-scoped bookmark 作为主要扩权路径。
- 权限不足时引导用户授权对应目录、补充 Full Disk Access，或降级为不可访问。

### 正在运行的应用

风险：运行中应用删除失败或状态不一致。

策略：

- 检测运行状态。
- 提示用户退出应用后重试。
- 首版不强制终止进程。

### 日志泄漏

风险：路径和文件名泄漏用户隐私。

策略：

- 日志只写稳定码和计数。
- 测试覆盖路径/文件名脱敏。

### Finder automation 授权拒绝

风险：用户不授予「控制 Finder」权限，或运行时撤销，导致删除链路不可用。

策略：

- 检测 automation 授权状态，未授权时禁用无写权限项目的删除并展示引导；已授权目录内项目可继续使用 `FileManager.trashItem`。
- 不静默失败、不回退到破坏性命令。
- 授权状态变化时 UI 同步刷新。

### AppleScript 路径注入

风险：候选键或路径含 `"`、`..`、反斜杠、`$()` 等字符，若以字符串拼接进 AppleScript 可越界执行。

策略：

- 路径以结构化 Apple Event 参数传递，或对拼入脚本的路径做严格转义。
- 候选键（bundle id、应用名、可执行名）在用于路径前做安全校验（参照 `BinaryContentStore.isSafeRelativeFileName` 思路）。
- 测试覆盖含特殊字符的路径与候选键。

## 验收方式

- 单元测试覆盖模型、扫描、计划生成、删除执行和日志隐私。
- Focused tests 通过后执行全量 `./script/build_and_run.sh verify`。
- 人工验证至少覆盖：
  - 普通卸载预览。
  - 完全删除预览。
  - 取消选择关联文件。
  - Trash 删除成功。
  - Trash 失败降级。
  - 权限不足或系统保护提示。
