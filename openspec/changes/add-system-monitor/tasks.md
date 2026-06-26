# Tasks：add-system-monitor

## 1. OpenSpec 文档

- [x] 1.1 编写 `proposal.md`，明确五维度只读概览与受影响能力。
- [x] 1.2 编写 `design.md`，定义快照模型、采样器边界、降级策略与隐私约束。
- [x] 1.3 编写 `tasks.md`，拆分模型、采样、服务、UI、测试与验收任务。
- [x] 1.4 编写 `specs/system-monitor/spec.md` 增量规范。

## 2. 模型与采样协议

- [x] 2.1 定义 `CPULoadSnapshot`、`MemorySnapshot`、`EnergySnapshot`、`NetworkSnapshot` 与聚合 `SystemMetricSnapshot`，全部 `Sendable` + `Equatable`。
  - `App/Models/SystemMetricSnapshot.swift`:`CPUMetrics`/`MemoryMetrics`/`EnergyMetrics`/`InterfaceStats`/`NetworkMetrics`(值类型,带钳制) + `CPULoadAvailability`/`MemoryAvailability`/`EnergyAvailability`/`NetworkAvailability`(enum,available/unavailable) + `SystemMetricSnapshot` 聚合(disk 复用既有 `DiskCapacityAvailability`)。
- [x] 2.2 定义每个维度的 `UnavailableReason` 枚举（含稳定 code + userDescription）。
  - `CPULoadUnavailableReason`(warmup/hostInfoFailed/unknown)、`MemoryUnavailableReason`(hostStatsFailed/sysctlFailed/unknown)、`EnergyUnavailableReason`(noBattery/iopsFailed/unknown)、`NetworkUnavailableReason`(getifaddrsFailed/unknown);各自 `stableCode` 唯一、`userDescription` 非空。
- [x] 2.3 定义 `SystemMonitorService` 协议：`start(intervalSeconds:)`、`stop()`、`updates()` 返回 `AsyncStream<SystemMetricSnapshot>`、`refreshOnce()`。
  - `App/Services/SystemMonitorService.swift`:协议 4 个方法,无默认实现,留给 §4 actor 实现。
- [x] 2.4 定义采样频率范围常量（默认 5s，区间 [1, 30]）与拒绝 0/负值的校验。
  - `SystemMonitorInterval`:`defaultSeconds=5`、`minSeconds=1`、`maxSeconds=30`、`isValid(_:)` 严格校验(拒绝 0/负/Nan/Inf/超上限)、`clampOrFallback(_:)` 非法值回退默认。
- [x] 2.5 为模型合法性、降级原因稳定性与频率边界编写单元测试。
  - `SystemMonitorModelsTests`(24 用例)+ `SystemMonitorIntervalTests`(5 用例):CPU 百分比归一化/钳制、内存字节钳制/usedFraction、电池百分比钳制、网络速率聚合/排序/钳制、所有 reason stableCode 唯一 + userDescription 非空、snapshot 部分字段独立性、interval 边界与回退。
- [x] 2.6 执行构建与测试并更新任务状态。
  - `xcodebuild test`:`** TEST SUCCEEDED **`,232 用例通过 / 0 失败。

## 3. 采样基础设施

- [x] 3.1 实现 `CPUSampler`：Mach `host_processor_info` / `HOST_CPU_LOAD_INFO`，两次采样差值计算 user/system/idle 百分比。
  - `App/Infrastructure/Diagnostics/CPUSampler.swift`:用 `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ...)` 拿整机 `host_cpu_load_info`(user/system/idle/nice ticks);首次返回 `.warmup`,delta=0 也返回 `.warmup`;user 百分比包含 nice(POSIX 习惯)。
  - `Ticks` 公共值类型保存上次 ticks;`availability(from:current:)` 是纯函数,便于测试;`sample(previous:)` 通过 `hostStatistics` closure(可注入)调用真实 Mach。
  - 测试:`CPUSamplerTests`(13 用例)覆盖纯函数边界(无 previous、zero delta、全 idle、全 user、混合、nice 归 user、UInt64 wraparound)+ 注入式 hostStatistics(首次 warmup + 提供 ticks、第二次 available、失败 hostInfoFailed + 保留 previous)+ 真实 Mach 冒烟(单次/两次)。
- [x] 3.2 实现 `MemorySampler`：Mach `host_statistics64` (`HOST_VM_INFO64`) + `sysctl("hw.memsize")`，计算 used/available/compressed(Apple Silicon 用 64 位变体更准)。
  - `App/Infrastructure/Diagnostics/MemorySampler.swift`:`VMStatistics` Sendable 包装 `vm_statistics64`(free/active/inactive/wire/compressor/speculative)。
  - `availability(totalBytes:vmStats:)` 纯函数:用 POSIX `getpagesize()` 替代 Mach 全局 var `vm_kernel_page_size`(Swift 6 严格并发安全);`available = (free + inactive) × pageSize`,`used = total - available`,`compressed = compressorPageCount × pageSize`。
  - `sample()` 通过注入式 `totalBytesProvider` + `vmStatsProvider`,失败分别映射 `.sysctlFailed` / `.hostStatsFailed`;两个稳定日志事件。
  - 测试:`MemorySamplerTests`(8 用例):纯函数 used/available/compressed 计算 + 钳制到 total + zero free;注入式 sysctl/vmStats 失败映射;真实 Mach/sysctl 冒烟(hw.memsize 大于 1GB)。
- [x] 3.3 实现 `EnergyStatus`：`IOPSCopyPowerSourcesInfo` 读取电池；整机能耗固定 `wholeMachinePowerUnavailable = true`，不调用 SMC/PowerMetrics。
  - `App/Infrastructure/Diagnostics/EnergyStatus.swift`:`import IOKit.ps` 调 `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` / `IOPSGetPowerSourceDescription`,从 `kIOPSMaxCapacityKey` / `kIOPSCurrentCapacityKey` 算 `current/max` 百分比,`kIOPSIsChargingKey` 取充放电状态。
  - `BatteryInfo` Sendable 包装(percent 0...1 + isCharging,钳到合法范围)。
  - `availability(from:)` 纯函数:`.available(EnergyMetrics)` 时 `wholeMachinePowerUnsupported = true` 固定;无电池或 IOKit 失败 → `.unavailable(reason: .noBattery)`;不调用 SMC / powermetrics / iostat。
  - 测试:`EnergyStatusTests`(6 用例):纯函数(电池+充电、低电量)+ 注入式 provider(可用 / nil → noBattery)+ BatteryInfo 钳制 + 真实 IOKit 冒烟(本机有电池走 available,桌面机走 noBattery)。
- [x] 3.4 实现 `NetworkSampler`：`getifaddrs` 按接口累计字节差值，过滤 `lo0` 回环；按间隔换算速率。
- [x] 3.5 复用 `DiskUsageService` 提供 `DiskSnapshot`（含 `DiskCapacityAvailability`，不重新实现容量读取）。
- [x] 3.6 每个采样器提供可注入式接口（便于测试替身），不在采样器内部跨 Actor 暴露 Mach/sysctl 不可发送对象。
- [x] 3.7 为各采样器编写单元测试：首次 warmup、第二次百分比/速率、采样失败映射。
- [x] 3.8 执行构建与测试并更新任务状态。

## 4. 默认服务实现

- [x] 4.1 实现 `DefaultSystemMonitorService`（actor）：装配五个采样器，顺序合并为 `SystemMetricSnapshot`，按间隔推送 `AsyncStream`。
- [x] 4.2 实现采样代次：每次 `start` 分配新 generation，过期结果丢弃；`refreshOnce` 用当前 generation。
- [x] 4.3 实现 `stop`：取消采样任务并 `continuation.finish()`；`onTermination` 兜底。
- [x] 4.4 实现单维度失败隔离：单采样失败不清空其他维度，仅在 snapshot 对应字段置 nil。
- [x] 4.5 实现采样间隔范围校验，拒绝 0/负值/超过上限。
- [x] 4.6 测试服务生命周期、generation 过期拒绝、单维度失败隔离、频率校验、AsyncStream 终止。
- [x] 4.7 执行构建与测试并更新任务状态。

## 5. 应用状态与依赖装配

- [ ] 5.1 新增 `SystemMonitorStore`（`@MainActor @Observable`）：持有最新快照、当前 generation、是否激活、采样间隔；提供 `activate/deactivate/refresh/setInterval`。
- [ ] 5.2 store 在 activate 时订阅 service 的 AsyncStream，按 generation 过滤并写回 `snapshot`；deactivate 时取消订阅并清空激活状态。
- [ ] 5.3 在 `DependencyContainer` 装配真实 `SystemMonitorService`，注入到 store 与“系统监控”页面。
- [ ] 5.4 持久化采样间隔到 `SettingsService`（新增 `systemMonitorIntervalSeconds` 键，默认 5，范围 [1, 30]），损坏值回退默认。
- [ ] 5.5 为 store 编写状态测试：activate/deactivate、generation 过滤、间隔切换。
- [ ] 5.6 执行构建与测试并更新任务状态。

## 6. UI 概览页

- [ ] 6.1 将 `SystemMonitorView` 从 `PlaceholderFeatureView` 升级为多卡片只读概览页。
- [ ] 6.2 实现 CPU 卡（user+system 百分比 + 圆环/进度条 + user/system/idle 拆分）。
- [ ] 6.3 实现内存卡（堆叠条 + 数字 + 三态）。
- [ ] 6.4 实现能耗卡（电池百分比 + 充放电状态 + 整机能耗降级文案）。
- [ ] 6.5 实现磁盘卡（复用 `DashboardDiskCard` 同源 `appState.startupVolumeCapacity`，提供进入磁盘分析页入口）。
- [ ] 6.6 实现网络卡（活跃接口列表 + 上下行速率 + 总速率栏）。
- [ ] 6.7 五张卡片统一三态：loading、available、unavailable；降级文案与 `UnavailableReason.userDescription` 一一对应。
- [ ] 6.8 顶部提供“立即刷新”按钮与采样间隔选择器（Stepper 或 Picker，范围 [1, 30]）。
- [ ] 6.9 `.onAppear` 调 `store.activate()`；`.onDisappear` 调 `store.deactivate()`。
- [ ] 6.10 VoiceOver 标签、键盘可达与浅色/深色外观适配。
- [ ] 6.11 执行构建与测试并更新任务状态。

## 7. 隐私、性能与验收

- [ ] 7.1 审计日志：确认不写入具体数值、接口名、电池百分比；只记录稳定事件码与维度缩写。
- [ ] 7.2 确认不存在上报、磁盘写入、私有 API 调用或额外权限申请。
- [ ] 7.3 确认采样仅在页面活跃时进行；视图关闭、应用退出后采样停止（用活动监视器交叉验证 Omnipo 自身 CPU 占用回落）。
- [ ] 7.4 运行全部单元测试与集成测试。
- [ ] 7.5 运行 Debug 构建，确认无编译错误与新增警告。
- [ ] 7.6 人工验证五张卡片显示真实值；切换频率生效；刷新按钮工作；能耗与磁盘 IOPS 降级文案清晰。
- [ ] 7.7 人工验证 CPU 卡百分比与活动监视器接近；内存卡与活动监视器“内存”标签一致；网络卡接口与 `ifconfig` 一致。
- [ ] 7.8 人工验证采样停止后 Omnipo 自身 CPU 占用接近 0（不构成后台监控负担）。
- [ ] 7.9 审阅任务清单，确保完成状态与验收证据准确。
- [ ] 7.10 验收后将 `system-monitor` 规范合并到 `openspec/specs/system-monitor/spec.md` 并归档 change。
