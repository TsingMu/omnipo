import Foundation

/// 大文件只读结果记录。
///
/// 不携带文件内容、扩展属性或安全敏感字段;`displayPath` 仅用于 UI 展示,
/// 不得进入日志或遥测(由 `PrivacyRedaction` 在 OSLog 边界兜底脱敏)。
public struct LargeFileRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let displayPath: String
    public let sizeBytes: Int64
    public let lastModifiedAt: Date?
    public let sourceVolumeIdentifier: String

    public init(
        id: UUID = UUID(),
        name: String,
        displayPath: String,
        sizeBytes: Int64,
        lastModifiedAt: Date? = nil,
        sourceVolumeIdentifier: String
    ) {
        self.id = id
        self.name = name
        self.displayPath = displayPath
        self.sizeBytes = max(0, sizeBytes)
        self.lastModifiedAt = lastModifiedAt
        self.sourceVolumeIdentifier = sourceVolumeIdentifier
    }
}

public enum LargeFileUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case scanNotStarted
    case resourceUnavailable
    case permissionLimited
    case unknown

    public var stableCode: String {
        switch self {
        case .scanNotStarted:
            return "LARGE_FILE_SCAN_NOT_STARTED"
        case .resourceUnavailable:
            return "LARGE_FILE_RESOURCE_UNAVAILABLE"
        case .permissionLimited:
            return "LARGE_FILE_PERMISSION_LIMITED"
        case .unknown:
            return "LARGE_FILE_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .scanNotStarted:
            return "大文件列表尚未开始扫描。"
        case .resourceUnavailable:
            return "当前无法读取大文件列表。"
        case .permissionLimited:
            return "缺少访问用户目录所需的权限,无法列举大文件。"
        case .unknown:
            return "大文件列表暂不可用。"
        }
    }
}

public enum LargeFileAvailability: Sendable, Equatable {
    case idle
    case loading
    case available([LargeFileRecord])
    case unavailable(reason: LargeFileUnavailableReason)

    public var records: [LargeFileRecord] {
        guard case .available(let records) = self else { return [] }
        return records
    }

    public var unavailableReason: LargeFileUnavailableReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// 按大小降序返回新状态;非 `.available` 状态原样返回。
    public func sortedBySizeDescending() -> LargeFileAvailability {
        guard case .available(let records) = self else { return self }
        let sorted = records.sorted { lhs, rhs in
            if lhs.sizeBytes != rhs.sizeBytes {
                return lhs.sizeBytes > rhs.sizeBytes
            }
            return lhs.name < rhs.name
        }
        return .available(sorted)
    }

    /// 限制结果条数;非 `.available` 状态原样返回。
    public func limited(to limit: Int) -> LargeFileAvailability {
        guard case .available(let records) = self else { return self }
        guard limit > 0 else { return .available([]) }
        if records.count <= limit {
            return self
        }
        return .available(Array(records.prefix(limit)))
    }
}
