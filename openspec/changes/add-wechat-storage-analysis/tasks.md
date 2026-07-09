# Tasks: Add WeChat Storage Analysis

> 本 change 先实现只读微信空间分析，不实现删除或清理。每完成一项必须更新 `[ ]` 为 `[x]`，并保持工程可编译。

## 1. 规范与边界

- [ ] 1.1 定义 `wechat-storage` capability 规范，明确只读、元数据扫描和不解析聊天内容。
- [ ] 1.2 明确非目标：不删除、不清理、不解析数据库、不读取文件内容、不上传数据。
- [ ] 1.3 定义 WeChat 根、分类、扫描结果、不可用原因和隐私日志边界。
- [ ] 1.4 审阅已存在日志脱敏禁止字段，确认覆盖微信账号、消息、联系人、路径和文件名。

## 2. 模型与服务协议

- [ ] 2.1 创建 `WeChatStorageRoot`、`WeChatStorageCategory`、`WeChatStorageGroup`、`WeChatStorageScanResult` 等模型。
- [ ] 2.2 创建 `WeChatStorageService` 协议，覆盖扫描、刷新和取消。
- [ ] 2.3 为分类展示名、隐私说明、排序、汇总大小和不可用原因编写模型测试。

## 3. 根发现与扫描

- [ ] 3.1 实现 `WeChatStorageRootResolver`，只检查窄范围候选路径和用户授权目录。
- [ ] 3.2 实现 `WeChatStorageScanner`，只读取文件系统元数据，不打开或解析文件内容。
- [ ] 3.3 实现路径分类推断：缓存、媒体与文件、日志、数据库与本地状态、备份、配置、其他。
- [ ] 3.4 实现部分失败降级：不可读根生成 issue，不阻塞其他可读根。
- [ ] 3.5 实现扫描取消和 top group 数量限制。
- [ ] 3.6 使用临时 fixture 目录测试根发现、分类汇总、不可读降级、取消和空状态。

## 4. 服务实现与依赖装配

- [ ] 4.1 实现 `DefaultWeChatStorageService`，串联根发现、扫描、聚合和错误映射。
- [ ] 4.2 接入 `DependencyContainer`，让 UI 依赖服务协议。
- [ ] 4.3 确认扫描不写入任何 WeChat 数据目录、不创建索引数据库、不产生删除动作。
- [ ] 4.4 执行 focused tests 并更新任务状态。

## 5. WeChat Manager UI

- [ ] 5.1 用真实 WeChat Manager 页面替换占位视图。
- [ ] 5.2 实现刷新、扫描中、成功、空状态、部分不可用和失败状态。
- [ ] 5.3 展示总可见占用、分类占用、top storage groups 和不可用根说明。
- [ ] 5.4 展示隐私边界：只统计文件元数据，不读取聊天内容或联系人。
- [ ] 5.5 对 raw path 做弱化展示，避免把可能含账号或联系人信息的路径作为主文案。
- [ ] 5.6 验证浅色/深色、键盘可达性和 VoiceOver 基础体验。

## 6. 日志、隐私与验收

- [ ] 6.1 审计 WeChat Storage 日志，确认不包含用户路径、文件名、账号、联系人、消息或数据库内容。
- [ ] 6.2 人工验证无 WeChat 数据时显示“未发现”而不是错误。
- [ ] 6.3 人工验证存在可读 fixture 或真实授权根时显示分类占用。
- [ ] 6.4 人工验证不可读根显示明确原因，不误报为 0 B 或无数据。
- [ ] 6.5 执行全量 `./script/build_and_run.sh verify`。
- [ ] 6.6 审阅任务清单，确保完成状态和验收证据准确。
- [ ] 6.7 验收后将 WeChat Storage 规范合并到 `openspec/specs/wechat-storage/spec.md` 并归档 change。
