# Design：add-system-monitor

## 设计目标

把“系统监控”页从占位升级为只读、低开销、可取消的多维度资源概览页。设计坚守三条原则：

1. **本地优先、零上报**：所有指标只在内存中保留短暂快照，不写入磁盘、不上传网络、不进入 OSLog 数值细节。
2. **Sandbox 内可用**：只用公开 API；无可靠公开 API 的维度（能耗瓦数、实时磁盘 IOPS）显式降级，不调用私有框架。
3. **生命周期受控**：采样仅在“系统监控”页面活跃时进行；用户切走或关闭主窗口立即停止，避免后台占用。

## 能力范围

首版覆盖五个维度的**整机级只读概览**（不做进程级）：

| 维度 | MVP 数据源 | 展示要点 | 降级原因 |
| --- | --- | --- | --- |
| CPU | Mach `host_processor_info` / `HOST_CPU_LOAD_INFO` | user / system / idle 百分比 | Mach API 不可用（极罕见） |
| 内存 | Mach `host_statistics64` (`HOST_VM_INFO64`) + `sysctl("hw.memsize")` | 已用 / 可用 / 总量 / 压缩（App Compressed） | sysctl 或 Mach 不可用 |
| 能耗 | **不可用降级** + 电池（`IOPSCopyPowerSourcesInfo`） | 电池电量、充放电状态；整机能耗瓦数无公开 API → 降级文案 | 整机能耗需 SMC/PowerMetrics（私有/特权） |
| 磁盘 | 复用 `DiskUsageService` 容量摘要 + 总磁盘读写速率（可选） | 已用 / 可用 / 总容量；实时 IOPS 私有 API → 降级 | IOPS 用 `iostat` 等命令式 API，Sandbox 不可用 |
| 网络 | `getifaddrs` 差值（按接口累计字节） | 上行 / 下行速率（字节/秒）+ 接口名 | `getifaddrs` 不可用 |

进程级监控（活动监视器的“进程”标签页）、历史趋势图、阈值告警、能耗瓦数、实时磁盘 IOPS、单接口速率详图等明确留到后续 change。

## 总体架构

```text
SystemMonitorView (SwiftUI, MainActor)
        │  reads
        ▼
SystemMonitorStore (@MainActor @Observable)
        │  subscribes batches
        ▼
SystemMonitorService (actor, single-flight + cancel)
   ┌──────────┬──────────────┬───────────────┬──────────────┬──────────────┐
   ▼          ▼              ▼               ▼              ▼              ▼
CPUSampler  MemorySampler  EnergyStatus  DiskUsageService  NetworkSampler  (future)
   │          │              │               │              │
   Mach       Mach+sysctl    IOPS Kit        已有            getifaddrs
   ▼          ▼              ▼               ▼              ▼
SystemMetricSnapshot (Sendable value)
```

### 依赖方向

- UI 仅依赖 `SystemMonitorStore` 与 `SystemMonitorService` 协议。
- Infrastructure 实现具体采样器（Mach / sysctl / IOPS / getifaddrs）。
- 模型 `SystemMetricSnapshot` 不持有任何不可发送的系统对象（`host_cpu_load_info` 数组、`vm_statistics` 等只在采样器内部使用，转换为值类型后跨 Actor 传递）。
- `DependencyContainer` 装配具体实现，UI 不直接接触 Mach / sysctl / IOPS。

## 数据模型

### SystemMetricSnapshot

不可变、`Sendable`、`Equatable` 值类型，聚合五个维度的当前状态：

```text
SystemMetricSnapshot {
    capturedAt: Date
    cpu: CPULoadSnapshot?
    memory: MemorySnapshot?
    energy: EnergySnapshot?
    disk: DiskSnapshot?
    network: NetworkSnapshot?
}
```

每个子模型同时携带 `value` 与 `unavailableReason`：

- `CPULoadSnapshot { userPercent, systemPercent, idlePercent }`
- `MemorySnapshot { totalBytes, usedBytes, availableBytes, compressedBytes? }`
- `EnergySnapshot { batteryPercent?, isCharging?, wholeMachinePowerUnavailable: Bool }`
- `DiskSnapshot { capacity: DiskCapacityAvailability }`（复用既有类型）
- `NetworkSnapshot { interfaces: [InterfaceStats], totalBytesInPerSec?, totalBytesOutPerSec? }`
  - `InterfaceStats { name, bytesInPerSec, bytesOutPerSec }`

任一维度采样失败时该字段为 `nil` 或子模型内 `unavailableReason != nil`，UI 渲染降级文案，不展示虚构数字。

### 采样代次（Generation）

- 每次启动新一轮采样（页面进入、刷新）分配单调递增 `generation`。
- 采样器返回结果必须携带 generation；`SystemMonitorStore` 仅接受当前 generation 的结果，过期批次丢弃。
- 这与 Launcher 的查询代次模型一致，避免快速刷新时旧数据覆盖新数据。

### 历史环（可选，默认关闭）

MVP 不维护历史趋势；为后续 change 留接口：`SystemMonitorStore` 内部可保留最近 N 个 snapshot（默认 0），由后续 change 决定是否启用。

## 服务边界

### SystemMonitorService 协议

```text
protocol SystemMonitorService: AnyObject, Sendable {
    func start(intervalSeconds: Double) async
    func stop() async
    func updates() -> AsyncStream<SystemMetricSnapshot>
    func refreshOnce() async -> SystemMetricSnapshot
}
```

- `start` 在 service 内启动定时采样任务，按 `intervalSeconds` 推送 `AsyncStream`。
- `stop` 取消任务并关闭流。
- `refreshOnce` 立即采样一次，用于首次进入页面与显式刷新按钮。
- 实现以 actor 隔离采样任务与最近一次快照。

### 单维度采样器

每个维度一个独立采样器，纯函数式 `(previousSample?) -> Snapshot?`：

- `CPUSampler`：用 `host_processor_info(HOST_CPU_LOAD_INFO)` 拿 `cpu_load_info` 结构，对比上次采样的 `tick` 计算百分比。需要至少两次采样才能算出百分比；首次返回 idle=100% 占位或返回 `.unavailable(reason: .warmup)`。
- `MemorySampler`：`host_statistics64(HOST_VM_INFO64)` + `sysctl("hw.memsize")`;返回 `vm_statistics64`,含 `compressor_page_count`,在 Apple Silicon 上比 32 位 `HOST_VM_INFO` 更准。计算 `used = total - (free + active + inactive + speculative + compressed)`、`available = free + inactive`、`compressed = compressor_page_count * vm_kernel_page_size`。
- `EnergyStatus`：`IOPSCopyPowerSourcesInfo` 拿电池；整机能耗固定返回 `wholeMachinePowerUnavailable = true`（私有 API 不调用）。
- `DiskUsageService`（已有）：复用容量摘要；实时 IOPS 不实现。
- `NetworkSampler`：`getifaddrs` 遍历接口，累计 `ifa_data.ifi_ibytes / ifi_obytes`，对比上次采样的差值除以时间间隔得到速率。过滤 `lo0` 等回环接口。

每个采样器是 `Sendable` struct/class，无状态（除自身缓存上次值用于差值计算）；差值缓存放 actor 内，不在采样器外部可见。

## 启动与停止策略

- 进入“系统监控”页面：`SystemMonitorStore.activate()` → `service.start(interval:)` + `refreshOnce()` 立即推送首帧。
- 离开页面：`SystemMonitorStore.deactivate()` → `service.stop()` 取消任务、关闭流。
- 主窗口最小化或隐藏：MVP 不监听窗口状态，依赖 view 的 `.onDisappear`；后续 change 可加 scenePhase 监听。
- 应用退出：actor `deinit` 兜底取消任务。

## 采样频率

- 默认 `5` 秒；范围 `[1, 30]`；不允许 0 或负值。
- 设置中可改；改动后下次 `start` 生效，正在进行的采样周期保持原间隔直到下一次启动。
- CPU 与 Network 对差值计算要求采样间隔稳定；高频抖动间隔会影响百分比/速率准确性，UI 在频率变化时短暂展示“正在重新校准”。

## UI 布局

页面采用竖向滚动列表，五张卡片各占一行：

- **CPU 卡**：圆环或进度条展示 `user + system` 占用百分比；副文案展示 user/system/idle 拆分。
- **内存卡**：堆叠条展示 used / available / compressed；数字标注总容量。
- **能耗卡**：电池图标 + 电量百分比 + 充放电状态；整机能耗直接展示降级文案（“macOS 未提供公开整机能耗 API”）。
- **磁盘卡**：复用 `DashboardDiskCard` 同源数据；点击进入“磁盘分析”页（既有目的地）。
- **网络卡**：列出活跃接口及上下行速率；总速率栏在头部。

每张卡都有三态：loading（首次采样）、available、unavailable。状态文案与 `SystemMetricSnapshot` 字段一一对应。

页面顶部提供“立即刷新”按钮 + 采样间隔选择器。

## 并发模型

- `SystemMonitorService` 是 actor，所有采样器调用通过 actor 串行化。
- 单次采样在 actor 内顺序调五个采样器，合并为 `SystemMetricSnapshot`，通过 `AsyncStream` 推送。
- 采样器内部不阻塞 actor：Mach / sysctl 调用都是微秒级；如某维度采样变慢，未来可在 actor 内分 Task，但 MVP 顺序调用以简化。
- UI 在 `MainActor` 上读 `SystemMonitorStore`，store 通过 `@Observable` 通知 UI 刷新。
- `AsyncStream` 的 `continuation.onTermination` 在 store 取消订阅时停止 actor 内的定时任务。

## 错误与降级

### 单维度采样失败

- 采样失败时返回 `nil`；service 在合并 snapshot 时把该维度字段设为 `nil`，UI 显示降级。
- 单维度失败不清空其他维度；五个维度彼此独立。

### 整机采样失败（罕见）

- 如 actor 启动失败或所有采样器同时失败，snapshot 全部 `nil`；UI 显示整体降级文案，不阻塞页面。

### Sandbox 限制

- 全部采样器在 Sandbox 内可用（Mach / sysctl / IOPS Kit / getifaddrs 均为公开且允许调用）。
- 若未来发现某采样器在 Sandbox 下被拒（如 entitlement 变化），降级到 unavailable，不申请额外权限。

### 频率抖动

- 用户频繁切换频率：service 内部用 generation 区分；旧 `start` 的任务被 cancel。

## 隐私与安全

- 所有指标仅留在 `SystemMonitorStore` 的当前快照与采样器的瞬时差值缓存中，不写入磁盘。
- 日志只记录稳定事件码（“monitor.started”、“monitor.stopped”、“monitor.sampleFailed”、维度缩写），不记录具体数值、接口名、电池百分比等。
- 网络接口名（en0/en5/bridge100 等）在 UI 上展示，但**不**进入 OSLog（接口名可能透露 VPN、虚拟机配置）。
- 不上报任何数据；不调用任何会触达网络或文件系统写入的 API。

## 性能约束

- 默认 5 秒采样间隔；单次采样在 actor 内 < 20ms（Mach + sysctl + getifaddrs 都是纳秒到微秒级）。
- 不在主线程采样；UI 仅通过 `@Observable` 接收已合并的快照。
- `AsyncStream` buffering 策略：`.bufferingNewest(1)`，丢弃旧快照避免积压。
- 视图关闭时立即 `stop()`，不在后台采样。

## 测试策略

### 单元测试

- 各采样器的“首次采样”、“第二次采样百分比/速率”、“采样失败映射”。
- `SystemMonitorService` 的 start/stop/refreshOnce 生命周期、generation 过期拒绝、单维度失败不影响其他。
- `SystemMonitorStore` 的 activate/deactivate 触发 start/stop、应用快照时只接受当前 generation。
- 采样频率范围校验（拒绝 0 / 负值 / 超过上限）。

### 集成测试

- 用 fake 采样器替换真实 Mach / sysctl / getifaddrs 调用，验证合并、推送、降级。
- 验证 view `.onAppear` 启动、`.onDisappear` 停止。

### 人工验收

- 五张卡片显示真实值；切换频率生效；关闭页面后 CPU 占用回落（用活动监视器交叉验证 Omnipo 自身 CPU）。
- 能耗卡显示降级文案；磁盘卡数字与 Disk Analysis 一致；网络卡接口与 `ifconfig` 输出一致。

## 备选方案

### 使用 `ps` / `top` / `iostat` 命令式 API

不采用。命令式 API 需 `Process` 启动子进程，在 Sandbox 下受限；解析输出脆弱且开销大。Mach / sysctl / getifaddrs 是公开原生 API，开销低且稳定。

### 使用 `Stats` / `MESuite` 等第三方库

不采用。首版所需能力可通过原生 API 满足；引入依赖增加供应链与隐私面。

### 监听 `NSWorkspace.didActivateApplicationNotification` 等推断 CPU

不采用。事件通知不能给出 CPU 占用百分比，且监听应用激活属于使用习惯跟踪，违背“不收集使用习惯”。

### 进程级监控

留到后续 change。需要 `proc_listallprocs` + `proc_pid_rusage` 等，开销与隐私敏感度更高，不适合 MVP。
