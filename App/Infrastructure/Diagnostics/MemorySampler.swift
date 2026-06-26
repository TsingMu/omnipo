import Foundation
import Darwin
import os

/// 内存采样器。
///
/// 使用 Mach `host_statistics64(HOST_VM_INFO64)` 读取整机 `vm_statistics64`,
/// 配合 `sysctl("hw.memsize")` 拿物理内存总量,计算 used/available/compressed。
/// 与 CPUSampler 不同,内存采样是绝对值,不需要 previous 差值。
public struct MemorySampler: Sendable {

    /// `vm_statistics64` 的 Sendable 值类型包装。
    public struct VMStatistics: Sendable, Equatable {
        public let freeCount: UInt32
        public let activeCount: UInt32
        public let inactiveCount: UInt32
        public let wireCount: UInt32
        public let compressorPageCount: UInt32
        public let speculativeCount: UInt32

        public init(
            freeCount: UInt32,
            activeCount: UInt32,
            inactiveCount: UInt32,
            wireCount: UInt32,
            compressorPageCount: UInt32,
            speculativeCount: UInt32
        ) {
            self.freeCount = freeCount
            self.activeCount = activeCount
            self.inactiveCount = inactiveCount
            self.wireCount = wireCount
            self.compressorPageCount = compressorPageCount
            self.speculativeCount = speculativeCount
        }
    }

    private let logger: any LoggingService
    private let totalBytesProvider: @Sendable () -> Int64?
    private let vmStatsProvider: @Sendable () -> VMStatistics?

    public init(logger: any LoggingService) {
        self.logger = logger
        self.totalBytesProvider = Self.readPhysicalMemoryBytes
        self.vmStatsProvider = Self.readVMStatistics
    }

    init(
        logger: any LoggingService,
        totalBytesProvider: @escaping @Sendable () -> Int64?,
        vmStatsProvider: @escaping @Sendable () -> VMStatistics?
    ) {
        self.logger = logger
        self.totalBytesProvider = totalBytesProvider
        self.vmStatsProvider = vmStatsProvider
    }

    public func sample() -> MemoryAvailability {
        guard let totalBytes = totalBytesProvider() else {
            logger.log(Self.logSysctlFailed())
            return .unavailable(reason: .sysctlFailed)
        }
        guard let stats = vmStatsProvider() else {
            logger.log(Self.logHostStatsFailed())
            return .unavailable(reason: .hostStatsFailed)
        }
        return Self.availability(totalBytes: totalBytes, vmStats: stats)
    }

    /// 从 totalBytes 与 vm_statistics64 派生 MemoryAvailability(纯函数)。
    ///
    /// - `available` = (free + inactive) × pageSize,粗略对应活动监视器"可立即使用"。
    /// - `used` = total - available,包含 active + wired + compressed + speculative。
    /// - `compressed` = compressorPageCount × pageSize,单独报告供 UI 展示。
    /// - pageSize 用 `vm_kernel_page_size`(Apple Silicon 默认 16384,Intel 默认 4096)。
    public static func availability(totalBytes: Int64, vmStats: VMStatistics) -> MemoryAvailability {
        // 用 POSIX `getpagesize()` 避免 Swift 6 严格并发对 Mach 全局 var `vm_kernel_page_size`
        // 的非 Sendable 报错;两者在 macOS 上返回相同值(Apple Silicon 16384,Intel 4096)。
        let pageSize = Int64(getpagesize())
        let free = Int64(vmStats.freeCount) * pageSize
        let inactive = Int64(vmStats.inactiveCount) * pageSize
        let compressed = Int64(vmStats.compressorPageCount) * pageSize
        let available = min(free + inactive, totalBytes)
        let used = max(0, totalBytes - available)
        return .available(MemoryMetrics(
            totalBytes: totalBytes,
            usedBytes: used,
            availableBytes: available,
            compressedBytes: compressed
        ))
    }

    // MARK: - 真实 Mach / sysctl 读取

    private static func readPhysicalMemoryBytes() -> Int64? {
        var size: Int64 = 0
        var sizeOfVar = MemoryLayout<Int64>.size
        let result = sysctlbyname("hw.memsize", &size, &sizeOfVar, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return size
    }

    private static func readVMStatistics() -> VMStatistics? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        return VMStatistics(
            freeCount: info.free_count,
            activeCount: info.active_count,
            inactiveCount: info.inactive_count,
            wireCount: info.wire_count,
            compressorPageCount: info.compressor_page_count,
            speculativeCount: info.speculative_count
        )
    }

    private static func logSysctlFailed() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "monitor.memory.sysctlFailed",
            stableCode: "W_MEM_SYSCTL_FAILED",
            sanitizedContext: ["code": "W_MEM_SYSCTL_FAILED", "reason": "sysctl-failed"]
        )
    }

    private static func logHostStatsFailed() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "monitor.memory.hostStatsFailed",
            stableCode: "W_MEM_HOST_STATS_FAILED",
            sanitizedContext: ["code": "W_MEM_HOST_STATS_FAILED", "reason": "host-statistics-failed"]
        )
    }
}
