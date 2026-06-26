import Foundation
import Darwin
import os

/// CPU 采样器。
///
/// 使用 Mach `host_statistics(HOST_CPU_LOAD_INFO)` 读取整机 cpu_ticks
/// (user/system/idle/nice),通过两次采样差值计算百分比。首次采样无法计算,
/// 返回 `.unavailable(reason: .warmup)`;后续采样对比上次 ticks。
///
/// 调用方负责保存返回的 `Ticks` 并在下一次 `sample(previous:)` 传入。
public struct CPUSampler: Sendable {
    /// 单次 Mach 读取的整机 CPU ticks 快照。
    public struct Ticks: Sendable, Equatable {
        public let user: UInt64
        public let system: UInt64
        public let idle: UInt64
        public let nice: UInt64

        public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    private let logger: any LoggingService
    private let hostStatistics: @Sendable () -> Ticks?

    public init(logger: any LoggingService) {
        self.logger = logger
        self.hostStatistics = Self.readHostCPULoad
    }

    /// 测试用注入式 init,允许替换 Mach 读取。
    init(
        logger: any LoggingService,
        hostStatistics: @escaping @Sendable () -> Ticks?
    ) {
        self.logger = logger
        self.hostStatistics = hostStatistics
    }

    /// 采样一次。返回当前 availability 与最新 ticks(供下次传入);
    /// Mach 调用失败时保留 previous ticks,availability 返回 unavailable。
    public func sample(previous: Ticks?) -> (CPULoadAvailability, Ticks?) {
        guard let current = hostStatistics() else {
            logger.log(Self.logHostInfoFailed())
            return (.unavailable(reason: .hostInfoFailed), previous)
        }
        let availability = Self.availability(from: previous, current: current)
        return (availability, current)
    }

    /// 从两次 ticks 差值计算百分比(纯函数,便于测试)。
    ///
    /// - previous 为 nil 时返回 `.warmup`(无法计算差值)。
    /// - 总差值为 0 时返回 `.warmup`(可能两次采样过近,或系统刚启动)。
    /// - user 百分比包含 nice 值(POSIX 习惯,nice 归属 user)。
    public static func availability(from previous: Ticks?, current: Ticks) -> CPULoadAvailability {
        guard let previous else {
            return .unavailable(reason: .warmup)
        }
        let userDelta = current.user &- previous.user
        let systemDelta = current.system &- previous.system
        let idleDelta = current.idle &- previous.idle
        let niceDelta = current.nice &- previous.nice

        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else {
            return .unavailable(reason: .warmup)
        }

        return .available(CPUMetrics(
            userPercent: Double(userDelta + niceDelta) / Double(total),
            systemPercent: Double(systemDelta) / Double(total),
            idlePercent: Double(idleDelta) / Double(total)
        ))
    }

    // MARK: - Mach

    private static func readHostCPULoad() -> Ticks? {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &cpuLoad) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        // cpu_ticks 是 (UInt, UInt, UInt, UInt) 元组,顺序对应 CPU_STATE_USER/SYSTEM/IDLE/NICE
        let ticks = cpuLoad.cpu_ticks
        return Ticks(
            user: UInt64(ticks.0),
            system: UInt64(ticks.1),
            idle: UInt64(ticks.2),
            nice: UInt64(ticks.3)
        )
    }

    private static func logHostInfoFailed() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "monitor.cpu.hostInfoFailed",
            stableCode: "W_CPU_HOST_INFO_FAILED",
            sanitizedContext: ["code": "W_CPU_HOST_INFO_FAILED", "reason": "host-statistics-failed"]
        )
    }
}
