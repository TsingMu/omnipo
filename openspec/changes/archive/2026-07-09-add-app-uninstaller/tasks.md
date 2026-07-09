# 任务：添加 App Uninstaller 核心能力

> 本 change 正在规划中。实施时每完成一项必须将 `[ ]` 更新为 `[x]`，并保持工程可编译。

## 1. 模型、服务与规范边界

- [x] 1.1 定义 `InstalledApplication`、`UninstallMode`、`AppAssociatedFile`、`AppUninstallPlan`、`UninstallExecutionResult` 等领域模型。
- [x] 1.2 定义 `UninstallerService` 协议，覆盖应用发现、计划生成、删除执行和取消；定义 `DeletionExecutor` 协议作为可切换删除抽象（首版 `FinderAutomationDeletionExecutor` 与 `SandboxTrashDeletionExecutor`）。
- [x] 1.3 定义关联文件分类、风险等级、归属置信度、不可用原因和默认选中规则。
- [x] 1.4 为每个关联文件分类定义用户可读的删除后果说明。
- [x] 1.5 明确普通卸载与完全删除的行为边界：普通卸载只删除应用本体；完全删除删除应用本体和用户选中的关联文件。
- [x] 1.6 明确删除优先移动到废纸篓；首版不提供应用内永久删除。
- [x] 1.7 为模型默认值、排序、汇总大小、分类删除后果说明、`Sendable`/序列化边界编写测试。
- [x] 1.8 明确当前 entitlement 假设：当前工程 entitlements 为空；如采用 Finder automation，需要新增 Apple Events entitlement 与 `NSAppleEventsUsageDescription`；FDA 仅作为受保护路径读取补充引导，不能作为全量文件访问承诺。
- [x] 1.9 执行 focused tests 并更新任务状态。

## 2. 应用发现

- [x] 2.1 实现 `InstalledApplicationScanner`，扫描 `/Applications`、`/System/Applications`、`/System/Library/CoreServices`、`~/Applications`。
- [x] 2.2 只识别 `.app` bundle，读取 bundle identifier、本地化名称、可执行路径、大小、图标标识和来源位置。
- [x] 2.3 标记系统保护应用、不可删除应用和正在运行应用。
- [x] 2.4 对不可读目录做部分降级，不阻塞其他目录结果。
- [x] 2.5 接入现有应用图标/本地化名称解析能力。
- [x] 2.6 为应用发现、系统保护标记、不可读目录降级和去重编写测试。
- [x] 2.7 执行 focused tests 并更新任务状态。

## 3. 完全删除关联文件扫描

- [x] 3.1 实现 `AssociatedFileScanner`，按 bundle identifier、应用显示名、可执行名和别名生成候选键；优先使用用户授权目录和 security-scoped bookmark，未授权、TCC 阻止、FDA 不足或沙箱不可达时返回 unavailable 并引导，不误报为空。
- [x] 3.2 扫描 `~/Library/Caches`、`Application Support`、`Preferences`、`Logs`、`Saved Application State`、`Containers`、`Group Containers`。
- [x] 3.3 将关联文件分为缓存、支持文件、偏好设置、日志、保存状态、容器、共享容器、其他等类别。
- [x] 3.4 实现归属置信度：完整 bundle id 命中为高置信度；应用名/可执行名完全命中为中置信度；模糊命中为低置信度。
- [x] 3.5 默认选中应用本体和高置信度关联文件；中低置信度、共享容器和高风险项默认不选中。
- [x] 3.6 对用户文档、系统目录、钥匙串、聊天数据库、浏览器 Profile 等高敏内容默认跳过或标记不可删除。
- [x] 3.7 为关联文件扫描、默认选中、不可读降级和高风险跳过编写测试。
- [x] 3.8 执行 focused tests 并更新任务状态。

## 4. 卸载计划与删除执行

- [x] 4.1 实现普通卸载计划生成，只包含应用本体。
- [x] 4.2 实现完全删除计划生成，包含应用本体和可安全归属的关联文件。
- [x] 4.3 支持用户在计划中逐项选择/取消选择关联文件，并重新计算总大小和风险摘要。
- [x] 4.4 实现 `FinderAutomationDeletionExecutor`，通过 Apple Event 驱动 Finder `delete` 删除（移废纸篓），用于当前进程无写权限但用户已确认的项目；路径以结构化参数传递或严格转义，禁止 AppleScript 字符串拼接。
- [x] 4.5 实现 `SandboxTrashDeletionExecutor`，仅处理用户授权目录内可写项目。
- [x] 4.6 实现 Trash/Finder 删除失败降级：不自动永久删除，首版不提供应用内永久删除。
- [x] 4.7 实现逐项结果：成功、失败、跳过、取消、权限不足、系统保护。
- [x] 4.8 对正在运行应用提示退出后重试，首版不强制终止进程。
- [x] 4.9 为计划生成、Finder automation 删除、automation 授权拒绝降级、授权目录 Trash、路径注入防护、永久删除不提供、部分成功和取消路径编写测试。
- [x] 4.10 执行 focused tests 并更新任务状态。

## 5. 主窗口 Uninstaller 页面

- [x] 5.1 用真实 Uninstaller 页面替换 `PlaceholderFeatureView`。
- [x] 5.2 实现应用列表、搜索、刷新、空状态、加载状态和部分失败提示。
- [x] 5.3 实现应用详情，展示图标、名称、bundle id、路径来源、大小、运行状态和保护状态。
- [x] 5.4 实现卸载模式选择：仅卸载应用、完全删除。
- [x] 5.5 实现完全删除预览按分类分组展示和逐项 checkbox。
- [x] 5.6 在每个完全删除预览分类中展示该类文件删除后的影响或后果。
- [x] 5.7 实现二次确认弹窗，文案明确区分普通卸载与完全删除，并再次提示选中应用数据删除后可能无法由 Omnipo 恢复。
- [x] 5.8 实现执行进度、结果汇总、失败/跳过原因和重试入口。
- [x] 5.9 验证浅色/深色、键盘可达性和 VoiceOver 基础体验。
- [x] 5.10 执行 focused tests 并更新任务状态。

## 6. 日志、隐私与验收

- [x] 6.1 审计 Uninstaller 日志，确认不包含用户路径、文件名、关联文件明细或应用私有数据；确认目录授权、FDA 补充状态与 Finder automation 授权状态在 UI 可见且不误报为"无数据"。
- [x] 6.2 验证完全删除预览中的路径只显示在 UI，不进入日志。
- [x] 6.3 验证权限不足、系统保护、归属不明确和共享容器风险均有明确 UI 状态。
- [x] 6.4 人工验证普通卸载预览和确认流程。
- [x] 6.5 人工验证完全删除预览按分类展示，并且每个分类都注明删除后果。
- [x] 6.6 人工验证完全删除预览、取消选择关联文件和删除结果。
- [x] 6.7 人工验证 Trash 失败时不会自动永久删除。
- [x] 6.8 执行全量 `./script/build_and_run.sh verify`。
- [x] 6.9 审阅任务清单，确保完成状态和验收证据准确。
- [x] 6.10 验收后将 App Uninstaller 规范合并到 `openspec/specs/app-uninstaller/spec.md` 并归档 change。
