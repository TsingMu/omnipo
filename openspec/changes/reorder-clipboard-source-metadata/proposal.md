# Change: 调整剪贴板来源应用元数据展示

## Why

剪贴板主页面与浮动面板目前把来源应用作为普通文字混排在内容类型和时间之间，来源识别不够直观，而且两处顺序不一致。

## What Changes

- 将来源应用信息移动到剪贴板内容预览下方的元数据行首位。
- 在来源应用名称前显示对应 macOS 应用图标。
- 主页面与浮动面板使用一致的顺序、回退图标和名称解析规则。
- 没有来源应用信息时保持现有内容类型和时间展示，不伪造来源。

## Impact

- Affected spec: `clipboard`
- Affected code: `ClipboardView`, `ClipboardPanelView`, `ClipboardPanelController`, `DependencyContainer`
- Data model and persistence: unchanged
