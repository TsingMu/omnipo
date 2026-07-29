# Tasks

## 1. Specification

- [x] 1.1 定义图片小图预览的展示范围、异步读取边界、降级行为和非目标。

## 2. Service And Infrastructure

- [ ] 2.1 为 `ClipboardService` 增加异步图片缩略图读取接口，并为不可用服务实现一致降级。
- [ ] 2.2 在 `DefaultClipboardService` 中读取现有 image payload，并使用 ImageIO 生成有界缩略图。
- [ ] 2.3 增加有总成本上限的进程内缩略图缓存，避免列表重建时重复读取和解码。
- [ ] 2.4 为有效图片、非图片、缺失 payload、损坏图片和不可用服务增加单元测试。

## 3. User Interface

- [ ] 3.1 实现主页面与浮动面板共用的图片缩略图组件，支持取消、占位和辅助功能描述。
- [ ] 3.2 在主 Clipboard 页面图片记录中显示 48 × 48 pt 等比缩略图，非图片记录保持现有图标。
- [ ] 3.3 在 Clipboard 浮动面板图片记录中显示 40 × 40 pt 等比缩略图，并保持现有选择与双击行为。
- [ ] 3.4 确认加载和失败状态不改变记录的复制、自动粘贴、收藏或删除能力。

## 4. Verification

- [ ] 4.1 运行 Clipboard 相关 XCTest。
- [ ] 4.2 运行完整 Debug 构建与全量 XCTest。
- [ ] 4.3 运行 `openspec validate --all --strict`。
- [ ] 4.4 人工验证横图、竖图、透明图片、损坏图片、快速滚动、浅色/深色模式，以及主页面与浮动面板的一致性。
