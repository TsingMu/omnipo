# 设计：Clipboard 核心能力

## 背景

`../clippy` 已经验证了 macOS 本地剪切板历史工具的核心链路，但它是一个以菜单栏和独立面板为中心的单功能应用。Omnipo 则是一个以主窗口导航和统一依赖装配为中心的多能力桌面应用。两者在产品形态上的差异，决定了本次工作应迁移“核心能力”，而不是复刻“应用外壳”。

同时，本 change 的隐私策略已经明确：沿用 `clippy` 现有策略，不排除密码或其他敏感内容，不做内容脱敏；但必须在首次启用时明确提示“仅本地存储”，并且日志永不记录原文。

## 目标

- 在 Omnipo 内提供真实可用的 Clipboard 页面。
- 保留 `clippy` 已验证的本地监听、去重、搜索、收藏和复制回剪切板能力。
- 使用 Omnipo 现有设置、日志和依赖装配体系，避免平行子系统。
- 首次启用前通过明确确认告知用户：剪切板原文将仅保存在本地。
- 为后续独立面板/状态栏增强保留扩展点，但不让首版交付被它们阻塞。

## 非目标

- 不迁移 `clippy` 的独立 `@main App`、`AppDelegate`、状态栏壳和菜单结构。
- 不在本 change 中做云同步、跨设备同步、远程备份或智能分析。
- 不实现内容脱敏、密码识别、正则敏感信息排除或默认跳过密码管理器来源。
- 不要求首版必须具备独立全局面板；主窗口内页优先。

## 总体迁移策略

### 一、直接复用思路，适配实现

以下模块可作为主要迁移来源，但需要改名、重组和协议化：

- `ClipRecord` / `ClipContentType`
- `ClipboardMonitor`
- `ClipRepository`
- `PasteSimulator`
- `SourceTracker`

这些逻辑的价值在于：内容识别、去重、格式恢复、搜索和复制回剪切板都已在真实工具里跑通过。

### 二、不直接迁移独立应用外壳

以下模块不应原样迁入：

- `ClipboardXApp.swift`
- `AppDelegate.swift`
- `StatusBarManager`
- `HotKeyManager`
- `SettingsView` 的独立产品壳

原因：

- Omnipo 已有自己的应用入口和依赖容器。
- Omnipo 已有 Carbon 快捷键实现，不需要再引入 `HotKey` 双体系。
- 状态栏和独立面板属于产品增强，不应阻塞剪切板核心能力落地。

### 三、设置项做数据化迁移，不做界面级搬运

`clippy` 的设置页是围绕独立剪切板产品组织的 Tab 结构；Omnipo 的设置则是统一宿主应用的 `Settings` Scene。两者整合时，应迁移“设置语义和持久化值”，而不是直接复制 `SettingsView` / `SettingsViewModel`。

整合原则：

- 设置值迁入 Omnipo 的 `SettingsService`
- Clipboard 设置 UI 作为 Omnipo 现有设置页中的一个分区或独立 section
- 不保留 `clippy` 的独立 Tab、独立 ViewModel 和即时写回 `UserDefaults` 风格
- 与 Omnipo 现有能力重复的设置优先复用宿主实现，而不是保留平行配置

## 架构设计

```text
NSPasteboard.general changeCount
              │
              ▼
   ClipboardMonitor / ClipboardCaptureService
              │
              ▼
      ClipboardRepository / BinaryStore
              │
      ┌───────┴────────┐
      ▼                ▼
ClipboardHistoryStore  PasteSimulator
      │                │
      ▼                ▼
 ClipboardView      System Pasteboard
```

### 建议目录

```text
App/
  Application/
    ClipboardHistoryStore.swift
  UI/
    Clipboard/
      ClipboardView.swift
      ClipboardFirstRunNotice.swift
      ClipboardSearchBar.swift
      ClipboardRecordList.swift
      ClipboardRecordRow.swift
  Services/
    ClipboardService.swift
  Models/
    ClipboardItem.swift
    ClipboardContentType.swift
  Infrastructure/
    Database/
      Clipboard/
        ClipboardDatabase.swift
        ClipboardRepository.swift
    Clipboard/
      ClipboardMonitor.swift
      PasteSimulator.swift
      BinaryContentStore.swift
      SourceApplicationTracker.swift
```

目录是实现指导，不要求先把所有文件一次性建齐。

## 数据与隐私策略

### 首次使用提示

首次进入 Clipboard 页面时，若用户尚未确认本能力：

- 显示不可忽略的首次说明。
- 文案必须明确表达：
  - 剪切板内容会被记录。
  - 数据仅保存在本机。
  - 应用不会上传这些内容。
  - 剪切板中可能包含密码、验证码、链接、文件路径等敏感内容，请用户自行决定是否启用。
- 用户确认前不得开始后台监听和持久化。

确认状态通过 `SettingsService` 保存在本地。

### 原文存储策略

本 change 明确允许本地持久化剪切板原文。需要同步修正对数据库说明的适用边界：

- “不得记录剪切板原文”不再适用于 `clipboard` 能力的数据层。
- 该约束继续适用于日志、调试输出、统计事件和其他非 Clipboard 能力。
- Clipboard 数据只允许保存在本地受控存储，不得出现在日志、埋点、崩溃附加文本或网络请求中。

### 敏感信息策略

- 不实现密码管理器默认排除。
- 不实现正则敏感规则过滤。
- 不对文本内容做脱敏或截断存储。
- 风险通过首次启用提示和本地存储承诺来告知，而不是通过内容识别兜底。

### 日志策略

允许记录：

- 监听启动/停止
- 数据库初始化成功/失败
- 自动粘贴权限缺失
- 记录保存失败的稳定错误码

禁止记录：

- 剪切板原文
- 搜索关键字
- 文件路径和文件名
- 来源应用的敏感上下文

## 持久化设计

### 存储方案

沿用 `clippy` 的“结构化数据库 + 二进制文件目录”方案：

- 结构化记录：SQLite
- 图片/HTML/RTF 等二进制内容：本地文件
- 设置：`SettingsService`

### 选型结论

首选继续使用 SQLite + 仓储抽象。原因：

- `clippy` 现有表结构与查询路径较成熟。
- 搜索、分页、收藏、删除和后续清理策略都更适合结构化存储。
- 单纯 `UserDefaults` 不适合历史记录体量。

实施前检查确认当前工程没有 Swift Package、CocoaPods、Cartfile 或既有 GRDB/FMBD/SQLite 封装。首版不新增第三方数据库依赖，采用系统 `SQLite3` + Clipboard 仓储封装；该实现细节只停留在 `Infrastructure/Database/Clipboard` 内，不扩散到 UI 层。

### 数据模型

首版至少需要：

- `ClipboardItem`
  - `id`
  - `contentHash`
  - `contentType`
  - `textPreview`
  - `sourceApplicationID`
  - `isFavorite`
  - `isDeleted`
  - `timesUsed`
  - `createdAt`
  - `updatedAt`
- `ClipboardBinaryPayload`
  - `recordID`
  - `storagePath`
  - `originalFormat`
  - `fileSize`

`ClipboardItem` 是 Omnipo 的对外领域模型；是否内部继续保留接近 `ClipRecord` 的表结构，不影响 UI 协议。

### 去重与更新

沿用 `clippy` 的核心规则：

- 文本类按规范化内容 hash 去重。
- 图片类按数据 hash 去重。
- 命中重复时不新增记录，而是更新 `timesUsed` 和 `updatedAt`。

## 监听与格式支持

### 监听方式

首版继续采用轮询 `NSPasteboard.general.changeCount` 的方式，因为：

- 简单稳定
- 已在 `clippy` 验证
- 不要求额外系统权限

轮询周期保守起步，可先沿用 `clippy` 级别，再根据实际压力调优。

### 支持内容类型

首版支持：

- 纯文本
- 富文本（RTF）
- HTML
- 图片
- 文件路径

不支持的类型可以忽略，不阻塞其他记录。

## UI 设计

### 主窗口内页优先

首版 Clipboard 直接落在 Omnipo 主窗口详情页中，包含：

- 首次使用提示
- 搜索框
- 类型过滤
- 记录列表
- 空状态
- 收藏/删除操作
- 复制到系统剪切板
- 自动粘贴按钮或快捷操作

### 交互原则

- 默认展示最近记录。
- 搜索应为本地即时过滤/查询。
- 选中一条记录时，用户可执行“复制”或“复制并粘贴”。
- 没有辅助功能权限时，“复制并粘贴”要降级并明确提示。

### 后续增强留口

本设计允许后续继续增加：

- 独立浮动面板
- 全局呼出
- 状态栏最近记录菜单

但这些增强必须复用同一数据与服务层，不再另起一套剪切板子系统。

## 与 Omnipo 现有基础设施的衔接

### SettingsService

首版新增至少以下设置键：

- `clipboard.isEnabled`
- `clipboard.hasAcknowledgedLocalStorageNotice`
- `clipboard.autoPaste`
- `clipboard.maxRecords`
- `clipboard.retentionDays`
- `clipboard.maxStorageMB`

设置值仍通过 Omnipo 现有 `SettingsService` 持久化，不保留 `clippy` 的 `AppSettings.shared` 单例读取边界。

### Clippo 现有设置的映射策略

#### 首版纳入 Omnipo 的 Clipboard 设置

- `autoPaste` → `clipboard.autoPaste`
- `maxRecords` → `clipboard.maxRecords`
- `retentionDays` → `clipboard.retentionDays`
- `maxStorageMB` → `clipboard.maxStorageMB`
- 新增 `clipboard.isEnabled`
- 新增 `clipboard.hasAcknowledgedLocalStorageNotice`

这些设置直接服务于首版 Clipboard 能力，且与当前产品策略一致，应进入 Omnipo 主设置页。

#### 保留能力但不沿用原实现

- `hotKeyConfig`
- `panelPosition`

原因：

- `hotKeyConfig` 属于全局快捷键体系，Omnipo 已有 `ShortcutService` 和对应设置区，不能继续沿用 `clippy` 的 `HotKeyManager` / `HotKeyConfig` 双体系。
- `panelPosition` 仅在未来存在独立 Clipboard 面板时才有意义；首版主窗口内页不需要暴露该设置。

#### 首版不整合的设置项

- `launchAtLogin`
- `showMenuBarIcon`
- `excludedApps`
- `excludedPatterns`
- `pollingInterval`
- `imageQuality`

原因：

- `launchAtLogin`、`showMenuBarIcon` 属于整应用外壳设置，不应由 Clipboard 功能单独接管。
- `excludedApps`、`excludedPatterns` 与当前“不过滤敏感内容，只做首次本地提示”的产品策略冲突。
- `pollingInterval`、`imageQuality` 更接近实现细节和高级调优参数，不适合作为首版用户设置暴露。

### Settings UI 组织

不复制 `clippy` 的 `TabView(通用/存储/排除规则/高级)`。Omnipo 侧使用统一设置页，新增 `ClipboardSettingsSection` 或等价分区，至少包含：

- 启用 Clipboard 历史
- 本地存储提示的当前状态
- 自动粘贴
- 最大保留条数
- 保留天数
- 最大存储空间

这样可以保持 Omnipo 设置页的一致性，避免用户面对第二套产品级设置界面。

### ShortcutService

不迁移 `clippy` 的 `HotKeyManager`。若后续要支持独立剪切板面板呼出，应复用 Omnipo 现有快捷键能力或在其之上扩展。

### LoggingService

不保留 `clippy` 自定义 Logger 分类作为对外边界。实现层可使用同一日志服务输出稳定代码和无敏感上下文事件。

## 风险与降级策略

### 风险 1：用户复制了极敏感内容

策略：

- 不做内容识别拦截。
- 在首次启用时清晰告知。
- 后续允许用户手动关闭 Clipboard 或清空历史。

### 风险 2：辅助功能权限缺失

策略：

- 复制回剪切板仍可用。
- 自动粘贴降级为仅复制。
- 只在用户主动执行自动粘贴时提示授权。

### 风险 3：存储增长过快

策略：

- 引入最大记录数/保留天数等本地清理策略。
- 收藏记录默认不被自动清理。

### 风险 4：迁移造成架构重复

策略：

- 不直接搬独立 App 壳。
- 所有新能力走 Omnipo 的依赖容器、设置和日志边界。

## 分阶段实施建议

### Phase 1：最小可用主窗口页

- 首次使用提示
- 文本历史记录
- 搜索
- 收藏/删除
- 复制回剪切板
- Omnipo 设置页中的 Clipboard 基础设置

### Phase 2：扩展富内容与来源应用

- RTF / HTML / 图片 / 文件路径
- 来源应用识别
- 二进制内容落盘
- 视需要评估是否增加更细粒度的高级设置

### Phase 3：自动粘贴与增强入口

- 辅助功能权限引导
- 复制并粘贴
- 评估独立面板与状态栏入口
- 若引入独立面板，再评估 `panelPosition`、独立快捷键和状态栏设置的整合方式

## 验收要点

- 首次提示真实出现，确认前不记录内容。
- 确认后能稳定记录并展示历史。
- 搜索、收藏、删除和复制回剪切板可用。
- 自动粘贴缺权限时正确降级。
- 日志检查中不存在剪切板原文和搜索词。
