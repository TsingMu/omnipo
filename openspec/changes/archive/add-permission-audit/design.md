# 设计：Permission Audit 核心能力

## 背景

权限审计是一个高价值但边界微妙的能力。它不像 Clipboard 或磁盘分析那样能主要依赖公开、稳定且面向内容的 API，而是要面对 macOS 权限体系的几个现实：

- 权限种类分散，不同类别可查询方式不同
- 其他应用的授权状态没有一套统一高层 API 可完整枚举
- TCC 结构与可读取性具有系统版本差异
- 在沙盒与系统安全约束下，“能否读取”本身就是能力边界的一部分

因此本设计的关键不是“尽可能多地读到东西”，而是“把能稳定、只读、可解释的结果展示出来，并把不能读的部分明确说清楚”。

## 目标

- 在 Omnipo 内提供真实可用的 Permission Audit 页面。
- 只读枚举本地权限状态，不读取隐私内容本身。
- 用统一模型表达“已授权 / 未授权 / 限制 / 不可读取 / 未知”等状态。
- 显式区分“不可读取”与“未授权”。
- 让实现具备版本容错与权限类别级别的降级能力。

## 非目标

- 不修改 TCC 数据库或任何授权记录。
- 不重置权限、不触发权限弹窗、不代表用户做系统设置变更。
- 不读取通讯录、日历、照片、提醒事项等实际内容。
- 不承诺所有权限类别都能完整枚举第三方应用。
- 不为了枚举结果而绕过系统安全机制。

## 总体策略

### 一、按权限类别分层实现，而不是追求单一万能后端

不同权限类别的读取来源可能不同，因此不应强行抽象成“一次查询所有权限”的黑盒。更稳妥的方式是：

- 定义统一领域模型与展示层协议
- 在基础设施层按权限类别组织 provider
- 聚合层负责合并结果、排序、去重和降级说明

### 二、把“不可读取”作为一等结果

Permission Audit 不能只有“authorized / denied”两态。对于当前系统版本、沙盒边界或数据源限制导致无法判断的情况，必须返回：

- `.unavailable(reason: ...)`

而不是默默当成 `.denied` 或空结果。

### 三、先做只读结果页，再考虑更复杂的跳转或修复建议

首版专注于只读审计和状态说明，不把问题空间扩展到系统设置跳转、修复流程、操作性 CTA。

## 架构设计

```text
PermissionAuditView
        │
        ▼
PermissionAuditStore / ViewState
        │
        ▼
PermissionAuditService
        │
        ▼
PermissionAuditAggregator
   ┌──────┼───────────┬───────────┐
   ▼      ▼           ▼           ▼
Category Providers / TCC Reader / System Capability Readers
```

### 建议目录

```text
App/
  Application/
    PermissionAuditStore.swift
  UI/
    PermissionAudit/
      PermissionAuditView.swift
      PermissionAuditSummaryStrip.swift
      PermissionAuditFilterBar.swift
      PermissionAuditList.swift
      PermissionAuditRow.swift
  Services/
    PermissionAuditService.swift
  Models/
    PermissionCategory.swift
    AppPermissionGrant.swift
    PermissionAuditResult.swift
  Infrastructure/
    Permissions/
      DefaultPermissionAuditService.swift
      PermissionAuditAggregator.swift
      TCC/
        TCCDatabaseLocator.swift
        TCCReadOnlySnapshotProvider.swift
      Providers/
        CameraPermissionProvider.swift
        MicrophonePermissionProvider.swift
        ContactsPermissionProvider.swift
        CalendarPermissionProvider.swift
        RemindersPermissionProvider.swift
        AccessibilityPermissionProvider.swift
        FullDiskAccessPermissionProvider.swift
```

目录是实现指导，不要求一步到位建齐所有 provider。

## 数据模型

### PermissionCategory

统一定义支持展示的权限类别，至少包含：

- camera
- microphone
- photos
- contacts
- calendar
- reminders
- accessibility
- fullDiskAccess

每个类别至少包含：

- 稳定标识
- 显示名
- SF Symbol 或等价图标描述
- 排序顺序

### AppPermissionGrant

表示“一个应用在一个权限类别上的状态”，至少包含：

- `id`
- `bundleIdentifier`
- `displayName`
- `category`
- `status`
- `source`
- `lastUpdatedAt?`

其中 `status` 应为枚举，而不是字符串：

- `.authorized`
- `.denied`
- `.restricted`
- `.notDetermined`
- `.unavailable(reason: PermissionUnavailableReason)`
- `.unknown`

### PermissionAuditResult

表示一次聚合审计结果，至少包含：

- `grants: [AppPermissionGrant]`
- `unavailableCategories: [PermissionCategory: PermissionUnavailableReason]`
- `summary`

## 数据源设计

### TCC 数据读取边界

对于确实依赖 TCC 的权限类别，可使用只读数据源，但必须满足：

- 只读打开
- 不执行任何写入
- 不依赖固定 schema 之外的脆弱假设时，要有版本容错
- 无法读取时返回 `.unavailable(.databaseUnreadable)` 或等价原因

实现上建议把 TCC 访问收敛在一个非常窄的 snapshot provider 内，避免 UI 或聚合层直接感知 SQLite 细节。

### 不同类别的降级

并非所有类别都必须在首版同时具备同等能力。可以按以下策略推进：

- 第一批优先做最容易稳定表达的类别
- 难以稳定枚举的类别先返回 `.unavailable(.unsupportedOnCurrentSystem)` 或 `.unavailable(.permissionLimited)`
- 只要解释明确，就优于给出错误结论

### 应用元数据

对于展示层，优先使用：

- bundle identifier
- 应用显示名

若元数据不完整：

- 允许显示 bundle identifier
- 不因缺图标或缺路径阻塞结果展示

## UI 设计

### 页面结构

主窗口 Permission Audit 页面首版包含：

- 顶部摘要区：总应用数、已授权数量、不可读取类别数
- 权限类别过滤
- 应用名搜索
- 结果列表
- 无结果 / 不可读取说明

### 结果呈现原则

每行至少展示：

- 应用名
- 权限类别
- 状态标签
- 可选的来源说明或不可读取原因简述

视觉上必须让以下几种状态明显可区分：

- 已授权
- 未授权/拒绝
- 未决定
- 不可读取

但不只依赖颜色表达状态。

### 不可读取说明

当整类权限不可读取时，页面应显示：

- 当前类别
- 不可读取原因
- 这是“无法判断”而不是“未授权”

若仅部分数据源不可用，则显示部分结果并附带分类说明。

## 与现有基础设施的衔接

### Permissions Infrastructure

必须复用 [App/Infrastructure/Permissions/README.md](/Users/mouqing/codexProjects/omnipo/App/Infrastructure/Permissions/README.md) 中的边界：

- 只读
- 不修改 TCC
- 不绕过安全机制
- 显式区分不可读取与未授权

### LoggingService

允许记录：

- 审计开始/完成
- 某类别不可读取
- 聚合失败的稳定错误码

禁止记录：

- 应用名列表
- 应用路径
- 底层数据库内容
- 原始查询行

### SettingsService

首版可不增加持久化设置。若后续需要记住过滤条件或展示偏好，应单独评估是否值得持久化。

## 风险与降级策略

### 风险 1：TCC 数据结构变化

策略：

- 把 TCC 读取收敛在窄边界
- 通过版本容错和 schema 容错避免页面整体崩溃
- 无法兼容时返回 `.unavailable`

### 风险 2：系统或沙盒导致无法读取

策略：

- 显示不可读取原因
- 不把空结果解释为未授权
- 页面仍可展示其他可读取类别

### 风险 3：不同权限类别实现不均衡

策略：

- 使用 provider-by-category 设计
- 允许分批交付支持类别
- 用统一状态模型遮蔽底层差异

## 分阶段实施建议

### Phase 1：统一模型与最小只读页面

- `PermissionCategory`
- `AppPermissionGrant`
- `PermissionAuditResult`
- Permission Audit 主窗口页
- 不可读取状态展示

### Phase 2：基础 provider 与聚合

- 首批类别 provider
- 聚合与分类过滤
- 应用搜索

### Phase 3：版本容错与更广类别支持

- 更多权限类别
- 更细粒度原因说明
- 更稳健的系统版本兼容测试

## 验收要点

- 页面不再是占位态
- 审计结果不触发新权限请求
- 不可读取与未授权明确区分
- 不同类别可以独立降级
- 日志无敏感元数据泄漏
