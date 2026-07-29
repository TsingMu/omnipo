# Change: 为剪贴板图片记录增加小图预览

## Why

剪贴板已经能够在本地保存图片内容，但主页面和浮动面板目前只显示通用图片图标与“图片”文字。用户无法在多条图片记录之间快速识别目标内容，往往需要逐条复制后再确认。

## What Changes

- 在 Clipboard 主页面和浮动面板的图片记录行首显示小图预览。
- 图片保持原始宽高比，并在固定的缩略图区域内等比缩放，不裁切主要内容。
- 缩略图从现有本地 image payload 异步生成，不增加网络访问或新的持久化字段。
- 缩略图加载、解码失败或 payload 缺失时显示通用图片图标，并保持记录操作可用。
- 非图片记录继续使用现有内容类型图标与布局。
- 为缩略图读取、降级和隐私边界增加自动化测试与人工验收。

## Non-Goals

- 不提供图片全尺寸查看、编辑、导出或 Quick Look。
- 不生成或持久化独立的缩略图文件。
- 不改变图片捕获、去重、保留期限、存储上限或写回剪贴板行为。
- 不为历史图片执行批量预生成或后台迁移。

## Impact

- Affected spec: `clipboard`
- Affected code: `ClipboardService`, `DefaultClipboardService`, `ClipboardView`, `ClipboardPanelView`
- Data model and database schema: unchanged
- Local storage: reuse existing image payload; no additional persistent files
