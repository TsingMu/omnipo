import Foundation

public struct AppUsageRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String?
    public let iconIdentifier: String?
    /// Activity Monitor-style CPU load where 1.0 is 100% of one CPU core.
    public let cpuPercent: Double?
    public let memoryBytes: Int64?
    public let networkBytesInPerSec: Double?
    public let networkBytesOutPerSec: Double?
    /// Current-sample usage score used for default ranking. This is not historical usage time.
    public let usageAmount: Double

    public init(
        id: String? = nil,
        displayName: String,
        bundleIdentifier: String? = nil,
        iconIdentifier: String? = nil,
        cpuPercent: Double? = nil,
        memoryBytes: Int64? = nil,
        networkBytesInPerSec: Double? = nil,
        networkBytesOutPerSec: Double? = nil,
        usageAmount: Double
    ) {
        let fallbackID = bundleIdentifier?.nonEmptyValue ?? displayName.nonEmptyValue ?? "unknown-app"
        self.id = id?.nonEmptyValue ?? fallbackID
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier?.nonEmptyValue
        self.iconIdentifier = iconIdentifier?.nonEmptyValue
        self.cpuPercent = Self.normalizedCPUPercent(cpuPercent)
        self.memoryBytes = memoryBytes.map { max(0, $0) }
        self.networkBytesInPerSec = Self.normalizedRate(networkBytesInPerSec)
        self.networkBytesOutPerSec = Self.normalizedRate(networkBytesOutPerSec)
        self.usageAmount = Self.normalizedScore(usageAmount)
    }

    private static func normalizedCPUPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    private static func normalizedRate(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }

    private static func normalizedScore(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    public func defaultSortPrecedes(_ other: AppUsageRecord) -> Bool {
        if usageAmount != other.usageAmount {
            return usageAmount > other.usageAmount
        }

        let lhsMemory = memoryBytes ?? 0
        let rhsMemory = other.memoryBytes ?? 0
        if lhsMemory != rhsMemory {
            return lhsMemory > rhsMemory
        }

        return displayName.localizedStandardCompare(other.displayName) == .orderedAscending
    }
}

public struct AppUsageSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let records: [AppUsageRecord]
    public let unavailableReason: AppUsageUnavailableReason?

    public init(
        capturedAt: Date = .now,
        records: [AppUsageRecord],
        unavailableReason: AppUsageUnavailableReason? = nil
    ) {
        self.capturedAt = capturedAt
        self.records = records.sortedByDefaultUsage()
        self.unavailableReason = unavailableReason
    }

    public var isEmpty: Bool {
        records.isEmpty && unavailableReason == nil
    }
}

public extension Array where Element == AppUsageRecord {
    func sortedByDefaultUsage() -> [AppUsageRecord] {
        sorted { lhs, rhs in
            lhs.defaultSortPrecedes(rhs)
        }
    }
}

public enum AppUsageUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case processListUnavailable
    case resourceUsageUnavailable
    case appAttributionUnavailable
    case unknown

    public var stableCode: String {
        switch self {
        case .processListUnavailable:
            return "APP_USAGE_PROCESS_LIST_UNAVAILABLE"
        case .resourceUsageUnavailable:
            return "APP_USAGE_RESOURCE_USAGE_UNAVAILABLE"
        case .appAttributionUnavailable:
            return "APP_USAGE_ATTRIBUTION_UNAVAILABLE"
        case .unknown:
            return "APP_USAGE_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .processListUnavailable:
            return "无法读取运行中应用列表。"
        case .resourceUsageUnavailable:
            return "无法读取应用资源占用。"
        case .appAttributionUnavailable:
            return "无法将资源占用归属到可识别的应用。"
        case .unknown:
            return "APP 使用情况暂不可用。"
        }
    }
}

public enum AppUsageAvailability: Sendable, Equatable {
    case idle
    case loading
    case available(AppUsageSnapshot)
    case unavailable(reason: AppUsageUnavailableReason)

    public var snapshot: AppUsageSnapshot? {
        guard case .available(let snapshot) = self else { return nil }
        return snapshot
    }

    public var records: [AppUsageRecord] {
        snapshot?.records ?? []
    }

    public var unavailableReason: AppUsageUnavailableReason? {
        switch self {
        case .available(let snapshot):
            return snapshot.unavailableReason
        case .unavailable(let reason):
            return reason
        case .idle, .loading:
            return nil
        }
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public func sortedByDefaultUsage() -> AppUsageAvailability {
        guard case .available(let snapshot) = self else { return self }
        let sortedSnapshot = AppUsageSnapshot(
            capturedAt: snapshot.capturedAt,
            records: snapshot.records.sortedByDefaultUsage(),
            unavailableReason: snapshot.unavailableReason
        )
        return .available(sortedSnapshot)
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
