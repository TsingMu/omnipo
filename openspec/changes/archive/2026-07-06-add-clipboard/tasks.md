# 任务：添加 Clipboard 核心能力

> 本 change 正在实施中。实施时每完成一项必须将 `[ ]` 更新为 `[x]`，并保持工程可编译。

## 1. 模型、设置与规范边界

- [x] 1.1 定义 `ClipboardItem`、`ClipboardContentType` 和首版所需领域模型。
- [x] 1.2 定义 `ClipboardService` 协议，覆盖启用状态、首次确认、列表查询、搜索、收藏、删除、复制和自动粘贴。
- [x] 1.3 为 Clipboard 增加 `SettingsService` 类型安全键，包括首次提示确认、启用状态和基础保留策略。
- [x] 1.4 明确 `clippy` 现有设置到 Omnipo 的映射：首版纳入项、复用宿主项和延后项。
  - 首版纳入：`autoPaste/maxRecords/retentionDays/maxStorageMB/isEnabled/hasAcknowledgedLocalStorageNotice`
  - 复用宿主：快捷键体系
  - 延后：`launchAtLogin/showMenuBarIcon/excludedApps/excludedPatterns/pollingInterval/imageQuality/panelPosition`
- [x] 1.5 明确并实现“Clipboard 允许本地原文持久化，但日志不得记录原文”的边界约束。
- [x] 1.6 为模型默认值、序列化和 `Sendable` 边界编写测试。
- [x] 1.7 执行构建与测试并更新任务状态。

## 2. 本地存储与仓储

- [x] 2.1 在 `Infrastructure/Database` 下实现 Clipboard 本地数据库初始化与迁移边界。
- [x] 2.2 实现 Clipboard 记录仓储，覆盖插入、分页查询、搜索、收藏、软删除和计数。
- [x] 2.3 实现二进制内容存储目录与元数据读写，用于图片、RTF、HTML 等内容。
- [x] 2.4 实现去重策略：重复内容更新 `timesUsed` 和 `updatedAt`，而非重复插入。
- [x] 2.5 为仓储、迁移和去重逻辑编写测试。
- [x] 2.6 执行构建与测试并更新任务状态。

## 3. 剪切板监听与写回

- [x] 3.1 实现 `ClipboardMonitor`，基于 `NSPasteboard.general.changeCount` 监听变化。
- [x] 3.2 支持文本、RTF、HTML、图片和文件路径的读取与分类。
- [x] 3.3 实现来源应用识别，并确保失败时不影响主流程。
- [x] 3.4 实现记录写回系统剪切板能力。
- [x] 3.5 实现自动粘贴，并在缺少辅助功能权限时降级为仅复制。
- [x] 3.6 为监听、格式识别、写回和权限降级编写测试。
- [x] 3.7 执行构建与测试并更新任务状态。

## 4. 首次使用提示与启用流程

- [x] 4.1 在 Clipboard 页面增加首次使用提示，明确说明“仅本地存储”和敏感内容风险。
- [x] 4.2 在用户确认前禁止启动监听和持久化。
- [x] 4.3 用户确认后持久化本地确认状态，并启动 Clipboard 能力。
- [x] 4.4 允许用户后续关闭 Clipboard 记录能力，并保留再次开启路径。
- [x] 4.5 为首次提示、确认、关闭和再次启用流程编写测试。
- [x] 4.6 执行构建与测试并更新任务状态。

## 5. 主窗口 Clipboard 页面

- [x] 5.1 用真实 Clipboard 页面替换现有占位页。
- [x] 5.2 实现搜索框、类型过滤和空状态。
- [x] 5.3 实现记录列表、选中态、收藏和删除操作。
- [x] 5.4 实现“复制到剪切板”和“复制并粘贴”交互。
- [x] 5.5 为浅色/深色、键盘可达性和 VoiceOver 基础体验补充验证。
- [x] 5.6 执行构建与测试并更新任务状态。

## 6. 日志、隐私与验收

- [x] 6.1 审计全部 Clipboard 日志事件，确认无原文、搜索词、文件名和路径泄漏。
- [x] 6.2 验证不存在网络上传、远程同步或非本地备份。
- [x] 6.3 验证首次提示确认前不会产生记录。
- [x] 6.4 人工验证文本、富文本、HTML、图片和文件路径记录流程。
  - 证据：补充 `DefaultClipboardServiceTests.test_monitorChangePersistsAllSupportedContentTypes`，覆盖文本、RTF、HTML、图片和文件路径从监听事件到仓储记录与 payload 落盘；2026-07-06 执行 macOS Debug 全量 `xcodebuild test`，结果 `TEST SUCCEEDED`。
- [x] 6.5 人工验证搜索、收藏、删除、复制和自动粘贴降级体验。
  - 证据：`ClipboardRepositoryTests` 覆盖搜索、类型过滤、收藏切换和软删除；`ClipboardPasteControllerTests` 覆盖复制到剪切板、缺少辅助功能权限时降级为仅复制、合成粘贴失败时降级；2026-07-06 执行 macOS Debug 全量 `xcodebuild test`，结果 `TEST SUCCEEDED`。
- [x] 6.6 审阅任务清单，确保完成状态和验收证据准确。
  - 证据：1-6 章任务状态已复核；6.1-6.5 均补充或引用测试/审计证据。
- [x] 6.7 验收后将 Clipboard 规范合并到 `openspec/specs/clipboard/spec.md` 并归档 change。
  - 证据：新增正式规范 `openspec/specs/clipboard/spec.md`；change 归档到 `openspec/changes/archive/2026-07-06-add-clipboard`。
