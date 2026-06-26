import Foundation

/// 采样间隔的范围与默认值。
///
/// 默认 5 秒;合法范围 [1, 30];`clampOrFallback` 把 0/负值/超过上限的输入钳到默认。
public enum SystemMonitorInterval {
    public static let defaultSeconds: Double = 5
    public static let minSeconds: Double = 1
    public static let maxSeconds: Double = 30

    /// 把任意输入钳到合法范围;非法值(0、负、超上限、NaN)回退默认。
    public static func clampOrFallback(_ value: Double) -> Double {
        if value.isNaN || value < minSeconds || value > maxSeconds {
            return defaultSeconds
        }
        return value
    }

    /// 严格校验:仅当 value 在 [min, max] 内才返回 true。
    public static func isValid(_ value: Double) -> Bool {
        !value.isNaN && value >= minSeconds && value <= maxSeconds
    }
}

/// 系统资源采样服务协议。
///
/// 实现必须:
/// - `start` 启动后台采样任务,按 `intervalSeconds` 推送 `AsyncStream`。
/// - `stop` 取消任务并关闭流。
/// - `refreshOnce` 立即采样一次,用于首次进入页面与显式刷新按钮。
/// - 采样代次(generation)在 service 内部维护,过期结果不推送。
/// - 不写入磁盘、不上报、不申请额外权限。
public protocol SystemMonitorService: AnyObject, Sendable {
    /// 启动周期采样;非法 interval 由 `SystemMonitorInterval.clampOrFallback` 钳到默认。
    func start(intervalSeconds: Double) async

    /// 取消采样任务并关闭流。
    func stop() async

    /// 返回当前采样流。重复调用可能返回同一个流或新流;实现需保证 stop 后流终止。
    func updates() async -> AsyncStream<SystemMetricSnapshot>

    /// 立即采样一次并返回,不影响周期采样的代次。
    func refreshOnce() async -> SystemMetricSnapshot
}
