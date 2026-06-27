# Tasks：revise-system-monitor-tabbed-app-usage

## 1. OpenSpec 文档

- [x] 1.1 编写 `proposal.md`，明确标签卡切换与纵览页 APP 使用情况目标。
- [x] 1.2 编写 `design.md`，定义信息架构、APP 使用边界、排序规则、隐私与降级策略。
- [x] 1.3 编写 `tasks.md`，拆分模型、采样、状态、UI、测试与验收任务。
- [x] 1.4 编写 `specs/system-monitor/spec.md` 增量规范。

## 2. 模型与协议

- [ ] 2.1 新增 `SystemMonitorTab`，覆盖 `overview/cpu/memory/energy/disk/network`，并提供展示标题与无障碍标签。
- [ ] 2.2 新增 `AppUsageRecord`、`AppUsageSnapshot`、`AppUsageAvailability` 与 `AppUsageUnavailableReason`，保持 `Sendable` + `Equatable`。
- [ ] 2.3 定义 APP 使用默认排序：`usageAmount` 降序、内存次级降序、应用名称升序。
- [ ] 2.4 定义 `AppUsageSampling` 协议或等价采样边界，支持单次采样与可注入测试替身。
- [ ] 2.5 为模型合法性、默认排序、不可用原因 stable code 编写单元测试。

## 3. APP 使用采样

- [ ] 3.1 实现运行中应用发现，使用公开 API 获取可归属 `.app` 的应用名称、bundle id 与图标来源。
- [ ] 3.2 实现应用级 CPU / 内存当前快照采样；不可读字段必须降级或省略，不用 0 伪装成功。
- [ ] 3.3 网络字段仅在有可靠公开进程归属数据时展示；否则省略或标记不可用，不分摊整机网络速率。
- [ ] 3.4 采样器支持取消、generation 过滤与单应用失败隔离。
- [ ] 3.5 图标加载采用缓存或按需策略，避免每个采样周期重复高成本读取。
- [ ] 3.6 为成功、空列表、单应用失败、整体失败、排序稳定性编写采样测试。

## 4. Store 与服务装配

- [ ] 4.1 在 `SystemMonitorStore` 中新增 `selectedTab`，默认 `.overview`。
- [ ] 4.2 在 store 中持有 APP 使用状态，并暴露已按默认规则排序的记录。
- [ ] 4.3 页面进入时启动整机指标与 APP 使用采样；页面离开时两者都停止或取消。
- [ ] 4.4 标签切换只更新 `selectedTab`，不得重启采样任务。
- [ ] 4.5 显式刷新同时刷新整机指标与 APP 使用情况，并丢弃过期 generation 结果。
- [ ] 4.6 在 `DependencyContainer` 中装配真实 APP 使用采样器。
- [ ] 4.7 为 activate/deactivate、刷新、标签切换不重启、generation 过滤编写 store 测试。

## 5. UI：标签卡与纵览页

- [ ] 5.1 将 `SystemMonitorView` 调整为顶部标签卡 + 当前标签内容的结构。
- [ ] 5.2 纵览页展示 CPU、内存、能耗、磁盘、网络紧凑摘要。
- [ ] 5.3 在纵览页摘要下方新增“APP 使用情况”列表。
- [ ] 5.4 APP 使用列表默认按使用量降序展示，行内包含应用图标或占位图标、应用名、当前使用量、CPU 与内存信息。
- [ ] 5.5 列表为空和不可用时展示清晰状态，不展示示例应用或虚构数值。
- [ ] 5.6 刷新按钮与采样间隔控件在新布局中继续可用。
- [ ] 5.7 完成浅色/深色、窄宽度、键盘可达与 VoiceOver 适配。

## 6. UI：资源专项页

- [ ] 6.1 CPU 页展示 CPU 总占用与 user/system/idle 拆分。
- [ ] 6.2 内存页展示已用、可用、压缩与总量。
- [ ] 6.3 能耗页展示电池状态与整机能耗降级说明。
- [ ] 6.4 磁盘页继续复用 `DiskUsageService` 容量摘要。
- [ ] 6.5 网络页展示整机接口上下行速率，明确不展示不可靠的应用级网络排行。
- [ ] 6.6 确保专项页复用同一快照，不因切换标签重复采样。

## 7. 隐私、性能与验收

- [ ] 7.1 审计日志，确认不记录应用名称、bundle id、pid、资源数值或网络速率。
- [ ] 7.2 确认不申请辅助功能、输入监控、完全磁盘访问或自动化权限。
- [ ] 7.3 确认 APP 使用情况不写入磁盘、不上传、不持久化历史。
- [ ] 7.4 运行完整测试：`xcodebuild -project Omnipo.xcodeproj -scheme Omnipo -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`。
- [ ] 7.5 人工验证顶部标签卡切换流畅，切换时采样任务没有重复启动。
- [ ] 7.6 人工验证纵览页 APP 使用情况默认按使用量降序。
- [ ] 7.7 人工验证离开系统监控页后整机指标与 APP 使用采样停止。
- [ ] 7.8 验收后将增量规范合并到 `openspec/specs/system-monitor/spec.md` 并归档 change。
