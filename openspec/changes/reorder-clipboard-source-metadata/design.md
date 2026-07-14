# Design: 剪贴板来源应用标签

## Context

`ClipboardItem.sourceApplicationID` 保存可选 bundle identifier，现有界面通过 `ApplicationDisplayNameResolver` 显示名称。应用已经提供共享的 `ApplicationResourceCache`，可在主线程中按 bundle identifier 有界缓存应用 URL 和 `NSImage`。

## Decisions

### 1. 使用共享缓存加载图标

新增一个轻量 SwiftUI 来源标签，在 `.task` 中从 `ApplicationResourceCache` 加载图标，避免在 `body` 重绘期间调用 `NSWorkspace`。图标无法解析时显示系统 `app` 符号。

### 2. 主页面与浮动面板共用同一标签

来源标签放在 Clipboard UI 模块内并供两套行视图复用。主页面从 `DependencyContainer` 取得缓存；浮动面板由 `ClipboardPanelController` 注入同一个缓存实例。

### 3. 来源信息保持可选

只有非空的 `sourceApplicationID` 才显示来源标签。名称继续优先使用本地化应用名，无法解析时显示 bundle identifier，不新增持久化字段或网络查询。

## Risks

- 应用已卸载或 bundle identifier 不可解析时没有真实图标；使用明确的通用应用图标降级。
- 元数据行可用宽度有限；来源名称保持单行并允许截断，后续元数据仍可显示。
