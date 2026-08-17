# Design：add-menu-bar-network-speed

## 设计目标

在 macOS 菜单栏有限的垂直空间内，以原生、低开销且可点击的方式展示两行实时网络速率。实现遵循以下原则：

1. **AppKit 边界最小化**：继续由 `NSStatusItem` / `NSStatusBarButton` 管理状态项与菜单，只在按钮内部增加不参与命中的展示视图。
2. **采样职责单一**：菜单栏只采样网络累计字节，不启动包含磁盘等其他维度的 `SystemMonitorService`。
3. **生命周期明确**：仅在状态项可见期间采样，隐藏和退出时取消任务并清空差值基线。
4. **本地与隐私优先**：不持久化、不上传、不记录具体速率或接口名。

## 最终布局

```text
┌───────────────────────┐
│  [Omnipo]  ↑ 1.2M/s  │
│            ↓ 8.4M/s  │
└───────────────────────┘
```

- 图标位于左侧，保持 18 × 18 pt 模板图像。
- 上传位于右侧上行，使用 `↑` 前缀。
- 下载位于右侧下行，使用 `↓` 前缀。
- 两行文本使用系统小号字体和等宽数字；建议 8–9 pt，最终以 macOS 14 实机可读性为准。
- 状态项使用固定或按最大格式计算的稳定宽度，避免每秒随数字长度变化挤压其他菜单栏项目。
- 文本使用系统语义色，随浅色、深色及菜单栏材质自动适配。

## AppKit 展示边界

### 采用方案

保留 `NSStatusItem.button` 作为菜单点击所有者，在按钮内容区域安装一个仅负责绘制的轻量视图，例如 `MenuBarNetworkSpeedView`：

```text
StatusBarManager (@MainActor)
    └── NSStatusItem
        └── NSStatusBarButton（保留点击与 menu 行为）
            └── MenuBarNetworkSpeedView（展示覆盖层，不拦截 hit testing）
                ├── NSImageView
                ├── uploadLabel
                └── downloadLabel
```

展示视图不得成为新的菜单或业务状态所有者。它通过覆盖 `hitTest(_:)` 返回 `nil`，或采用等价的非交互方式，使鼠标事件继续落到 `NSStatusBarButton`。因此点击图标、上传行或下载行都会打开现有 `NSMenu`。

### 不采用普通多行标题

不直接向 `NSStatusBarButton.title` 写入换行字符串。按钮单元格对多行标题的高度、裁切和图文间距控制不稳定，难以保证不同显示缩放、辅助功能字号和系统版本下的可读性。

### 状态项尺寸

- `NSStatusItem` 从 `squareLength` 调整为可容纳图标与双行文本的稳定长度。
- 初始建议宽度为 76–88 pt；实现通过字体测量确定最终常量或最大内容宽度。
- 高度完全服从系统状态栏按钮 bounds，不写死屏幕像素高度。
- 视图在按钮 bounds 变化时重新布局，避免刘海屏、显示缩放和系统状态栏尺寸差异导致裁切。

## 数据流

```text
getifaddrs()
    │ cumulative interface bytes
    ▼
NetworkSampler（独立 previous 基线）
    │ total bytes/sec
    ▼
MenuBarNetworkRateMonitor actor
    │ AsyncStream<MenuBarNetworkRateSnapshot>
    ▼
StatusBarManager (@MainActor)
    │ compact formatting
    ▼
MenuBarNetworkSpeedView
```

### MenuBarNetworkRateSnapshot

菜单栏只需要整机总速率，不暴露接口明细给展示层：

```swift
struct MenuBarNetworkRateSnapshot: Sendable, Equatable {
    let uploadBytesPerSecond: Double
    let downloadBytesPerSecond: Double
}
```

采样不可用与预热状态使用显式状态表达，避免以 `0` 冒充尚未计算的结果：

```swift
enum MenuBarNetworkRateAvailability: Sendable, Equatable {
    case warmingUp
    case available(MenuBarNetworkRateSnapshot)
    case unavailable
}
```

## 采样器与生命周期

### 独立菜单栏 Monitor

新增轻量 `MenuBarNetworkRateMonitor` actor，内部持有：

- `NetworkSampler`
- 本次可见会话的 `NetworkSampler.Previous?`
- 单个可取消的采样 `Task`
- 单个更新流 continuation

它复用 `NetworkSampler` 的计数与差值算法，但不复用 `DefaultSystemMonitorService`。后者每轮还会采样 CPU、内存、能耗和磁盘，并由系统监控页面负责启停；把菜单栏接到同一个 service 会造成状态争用和不必要开销。

### 状态转换

```text
应用启动 / 设置打开状态项
    → 创建状态项
    → 显示 warmingUp（↑ -- / ↓ --）
    → start(interval: 1s)
    → 首次读取仅保存 previous
    → 第二次读取开始发布 available

设置隐藏状态项
    → stop()
    → 取消 Task、结束更新流、previous = nil
    → statusItem.isVisible = false

再次显示
    → 使用新会话重新预热

应用退出 / manager 释放
    → 取消订阅和采样任务
```

`setup()` 必须保持幂等，重复调用不得创建第二个状态项、第二个展示视图或第二个采样任务。

### 采样频率

- 固定为 1 秒，满足“实时”感知并保持较低开销。
- 使用实际两次采样时间差换算速率，不假设定时器严格为 1.000 秒。
- `Task.sleep` 被取消后立即退出，不吞掉取消并继续循环。
- 设备睡眠、接口重置或计数回绕后沿用 `NetworkSampler` 的安全差值规则；负差值按 0 处理。

## 速率格式化

新增纯函数格式化器，便于单元测试。采用十进制单位（1 K = 1,000 B）：

| 输入范围 | 示例输出 |
| --- | --- |
| 预热或不可用 | `--` |
| `< 1,000 B/s` | `824B/s` |
| `< 1,000,000 B/s` | `1.2K/s`、`128K/s` |
| `< 1,000,000,000 B/s` | `1.2M/s`、`128M/s` |
| 其余 | `1.2G/s` |

规则：

- 所有输入钳制为非负数；`NaN` 和无穷值视为不可用。
- 小于 10 个单位保留 1 位小数；达到 10 后可省略小数以限制宽度。
- 标签采用等宽数字，并分配固定文本宽度。
- UI 使用紧凑单位；VoiceOver accessibility value 使用完整中文语义，例如“上传每秒 1.2 兆字节，下载每秒 8.4 兆字节”。

## 设置响应

沿用现有 `showMenuBarIcon` 设置和 `.menuBarVisibilitySettingDidChange` 通知：

- `true`：显示组合状态项并启动菜单栏网络采样。
- `false`：先停止采样，再隐藏状态项。
- “恢复 Clippy 风格默认设置”改变该值时执行相同状态转换。

本 change 不增加独立网速开关，避免出现“图标隐藏但网速采样仍运行”或多个互相冲突的可见性组合。后续如有明确产品需要，可单独增加 `showMenuBarNetworkSpeed`。

## 并发与所有权

- `StatusBarManager` 和 `MenuBarNetworkSpeedView` 仅在 `@MainActor` 访问 AppKit 对象。
- `MenuBarNetworkRateMonitor` actor 隔离 previous、Task 和 stream continuation。
- `StatusBarManager` 持有一个订阅任务；收到 stream 更新后切换至 MainActor 更新标签。
- 任何 stop、重新启动或可见性变化均使用会话 generation 或取消旧订阅，防止隐藏后的晚到结果更新 UI。
- `deinit` 不能依赖异步清理作为唯一保障；持有的任务必须可取消并使用弱引用避免环。

## 错误与降级

- `getifaddrs()` 失败：两行均显示 `--`，状态项和菜单保持可用。
- 图标资源加载失败：沿用现有 `sparkles` 系统符号，再失败则显示文本后备标识。
- 自定义展示视图布局失败或尺寸不足：优先保留图标与菜单点击区域，允许速率文本被隐藏，不让菜单入口失效。
- 不弹出通知、不展示阻塞式错误；底层失败只记录稳定错误码，沿用 `NetworkSampler` 已有脱敏日志策略。

## 隐私与权限

- 只读取网络接口累计入站/出站字节计数。
- 不读取 IP、端口、域名、连接目标、数据包或应用归属。
- 不申请辅助功能、输入监控、完全磁盘访问或网络扩展权限。
- 速率、接口名和采样时间戳不写入 UserDefaults、数据库或 OSLog。
- 不产生任何遥测或网络请求。

## 测试策略

### 单元测试

- 速率格式化的 B/K/M/G 边界、小数规则、负值、`NaN`、无穷值。
- monitor 首次预热、第二次 available、采样失败 unavailable。
- start 幂等、stop 取消、再次 start 清空 previous。
- 状态项隐藏后忽略旧 generation 的晚到更新。
- 展示模型确保上传映射到上行、下载映射到下行。

### 集成与人工验收

- 启动应用后观察两行顺序、字体和裁切。
- 使用网络上传与下载分别制造流量，确认对应行变化，且不会上下颠倒。
- 点击图标、上传行、下载行，确认均打开原有菜单。
- 切换浅色/深色和不同显示缩放，确认模板图标与文字可读。
- 隐藏状态项后用 Instruments 或诊断日志确认采样停止；再次显示先出现 `--`，随后恢复速率。
- 与活动监视器或其他只读工具做数量级对比；允许采样窗口造成的短时差异。

## 风险与取舍

### 菜单栏空间占用

双行文本会扩大状态项宽度，在刘海屏或菜单栏项目较多时可能被系统隐藏。通过紧凑单位、固定宽度和小号字体控制占用，但不牺牲到不可读。

### 每秒更新的视觉与无障碍干扰

等宽数字和固定宽度用于减少跳动。accessibility value 可以更新，但不得每秒主动发送 announcement，避免 VoiceOver 持续打断用户。

### 与系统监控页面重复读取计数

两个功能同时活跃时会分别调用轻量 `getifaddrs()`。首版接受这一有限重复，以保持生命周期和所有权简单；不为消除一次低成本系统调用而把页面服务改造成全局共享总线。

## 备选方案

### 复用完整 `SystemMonitorService`

不采用。它会执行无关维度采样，尤其包含磁盘容量读取，并与页面的 start/stop 行为冲突。

### 给按钮标题插入换行

不采用。多行标题在状态栏按钮中容易裁切，图文对齐和点击区域也难以稳定验证。

### 使用定时器直接在 MainActor 调用采样器

不作为首选。`getifaddrs()` 通常很快，但 actor + 可取消 Task 能提供更清晰的后台生命周期、测试注入和晚到结果隔离。
