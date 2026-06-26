import Foundation

// MARK: - CPU

public struct CPUMetrics: Sendable, Equatable {
    /// 0.0 ... 1.0,占用百分比(user + system + nice)
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double

    public init(userPercent: Double, systemPercent: Double, idlePercent: Double) {
        let user = max(0, min(1, userPercent))
        let system = max(0, min(1, systemPercent))
        let idle = max(0, min(1, idlePercent))
        let sum = user + system + idle
        if sum > 0 {
            self.userPercent = user / sum
            self.systemPercent = system / sum
            self.idlePercent = idle / sum
        } else {
            self.userPercent = 0
            self.systemPercent = 0
            self.idlePercent = 1
        }
    }

    public var busyPercent: Double { userPercent + systemPercent }
}

public enum CPULoadUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case warmup
    case hostInfoFailed
    case unknown

    public var stableCode: String {
        switch self {
        case .warmup: return "CPU_WARMUP"
        case .hostInfoFailed: return "CPU_HOST_INFO_FAILED"
        case .unknown: return "CPU_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .warmup: return "CPU 数据正在预热,需要至少两次采样才能计算占用。"
        case .hostInfoFailed: return "无法读取 CPU 信息。"
        case .unknown: return "CPU 数据暂不可用。"
        }
    }
}

public enum CPULoadAvailability: Sendable, Equatable {
    case available(CPUMetrics)
    case unavailable(reason: CPULoadUnavailableReason)

    public var metrics: CPUMetrics? {
        if case .available(let metrics) = self { return metrics }
        return nil
    }

    public var unavailableReason: CPULoadUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Memory

public struct MemoryMetrics: Sendable, Equatable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let compressedBytes: Int64?

    public init(totalBytes: Int64, usedBytes: Int64, availableBytes: Int64, compressedBytes: Int64? = nil) {
        let total = max(0, totalBytes)
        let available = max(0, min(availableBytes, total))
        let used = max(0, min(usedBytes, total - available))
        let compressed = compressedBytes.map { max(0, min($0, total)) }
        self.totalBytes = total
        self.usedBytes = used
        self.availableBytes = available
        self.compressedBytes = compressed
    }

    public var usedFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return Double(usedBytes) / Double(totalBytes)
    }
}

public enum MemoryUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case hostStatsFailed
    case sysctlFailed
    case unknown

    public var stableCode: String {
        switch self {
        case .hostStatsFailed: return "MEM_HOST_STATS_FAILED"
        case .sysctlFailed: return "MEM_SYSCTL_FAILED"
        case .unknown: return "MEM_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .hostStatsFailed: return "无法读取内存统计信息。"
        case .sysctlFailed: return "无法读取物理内存总量。"
        case .unknown: return "内存数据暂不可用。"
        }
    }
}

public enum MemoryAvailability: Sendable, Equatable {
    case available(MemoryMetrics)
    case unavailable(reason: MemoryUnavailableReason)

    public var metrics: MemoryMetrics? {
        if case .available(let metrics) = self { return metrics }
        return nil
    }

    public var unavailableReason: MemoryUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Energy

public struct EnergyMetrics: Sendable, Equatable {
    /// 0.0 ... 1.0;无电池设备为 nil。
    public let batteryPercent: Double?
    public let isCharging: Bool?
    /// `true` 表示当前由电源适配器供电,即使电池未处于充电状态。
    public let isOnExternalPower: Bool?
    /// 整机能耗瓦数在 macOS 无公开 API,本应用不调用 SMC/PowerMetrics;
    /// 此字段固定为 true,UI 据此显示降级文案。
    public let wholeMachinePowerUnsupported: Bool

    public init(
        batteryPercent: Double?,
        isCharging: Bool?,
        isOnExternalPower: Bool? = nil,
        wholeMachinePowerUnsupported: Bool = true
    ) {
        let clampedBattery = batteryPercent.map { max(0, min(1, $0)) }
        self.batteryPercent = clampedBattery
        self.isCharging = isCharging
        self.isOnExternalPower = isOnExternalPower
        self.wholeMachinePowerUnsupported = wholeMachinePowerUnsupported
    }

    public var hasBattery: Bool { batteryPercent != nil }
}

public enum EnergyUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case noBattery
    case iopsFailed
    case unknown

    public var stableCode: String {
        switch self {
        case .noBattery: return "ENERGY_NO_BATTERY"
        case .iopsFailed: return "ENERGY_IOPS_FAILED"
        case .unknown: return "ENERGY_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .noBattery: return "当前设备无电池,且 macOS 未提供公开整机能耗 API。"
        case .iopsFailed: return "无法读取电池信息。"
        case .unknown: return "能耗数据暂不可用。"
        }
    }
}

public enum EnergyAvailability: Sendable, Equatable {
    /// 有电池(可能同时整机能耗瓦数不可用)。
    case available(EnergyMetrics)
    case unavailable(reason: EnergyUnavailableReason)

    public var metrics: EnergyMetrics? {
        if case .available(let metrics) = self { return metrics }
        return nil
    }

    public var unavailableReason: EnergyUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

// MARK: - Network

public struct InterfaceStats: Sendable, Equatable, Identifiable {
    public let name: String
    public let bytesInPerSec: Double
    public let bytesOutPerSec: Double

    public var id: String { name }

    public init(name: String, bytesInPerSec: Double, bytesOutPerSec: Double) {
        self.name = name
        self.bytesInPerSec = max(0, bytesInPerSec)
        self.bytesOutPerSec = max(0, bytesOutPerSec)
    }
}

public struct NetworkMetrics: Sendable, Equatable {
    public let interfaces: [InterfaceStats]
    public let totalBytesInPerSec: Double
    public let totalBytesOutPerSec: Double

    public init(interfaces: [InterfaceStats]) {
        self.interfaces = interfaces.sorted { $0.name < $1.name }
        self.totalBytesInPerSec = interfaces.reduce(0) { $0 + $1.bytesInPerSec }
        self.totalBytesOutPerSec = interfaces.reduce(0) { $0 + $1.bytesOutPerSec }
    }
}

public enum NetworkUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case getifaddrsFailed
    case unknown

    public var stableCode: String {
        switch self {
        case .getifaddrsFailed: return "NET_GETIFADDRS_FAILED"
        case .unknown: return "NET_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .getifaddrsFailed: return "无法读取网络接口流量。"
        case .unknown: return "网络数据暂不可用。"
        }
    }
}

public enum NetworkAvailability: Sendable, Equatable {
    case available(NetworkMetrics)
    case unavailable(reason: NetworkUnavailableReason)

    public var metrics: NetworkMetrics? {
        if case .available(let metrics) = self { return metrics }
        return nil
    }

    public var unavailableReason: NetworkUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

// MARK: - 聚合

/// 五维度系统资源快照,聚合 CPU/内存/能耗/磁盘/网络。
///
/// `disk` 直接复用既有 `DiskCapacityAvailability`,避免重复定义;
/// 其余字段在采样未完成或失败时为 nil,UI 渲染降级。
public struct SystemMetricSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let cpu: CPULoadAvailability?
    public let memory: MemoryAvailability?
    public let energy: EnergyAvailability?
    public let disk: DiskCapacityAvailability?
    public let network: NetworkAvailability?

    public init(
        capturedAt: Date = Date(),
        cpu: CPULoadAvailability? = nil,
        memory: MemoryAvailability? = nil,
        energy: EnergyAvailability? = nil,
        disk: DiskCapacityAvailability? = nil,
        network: NetworkAvailability? = nil
    ) {
        self.capturedAt = capturedAt
        self.cpu = cpu
        self.memory = memory
        self.energy = energy
        self.disk = disk
        self.network = network
    }

    /// 五维度全部 nil 的空快照,用于 service 启动前的占位或整体降级。
    public static let empty = SystemMetricSnapshot()

    public var isEmpty: Bool {
        cpu == nil && memory == nil && energy == nil && disk == nil && network == nil
    }
}
