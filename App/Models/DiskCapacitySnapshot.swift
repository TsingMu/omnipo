import Foundation

public struct DiskCapacitySnapshot: Sendable, Equatable {
    public let volumeName: String
    public let volumeIdentifier: String
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let totalBytes: Int64
    public let capturedAt: Date

    public init(
        volumeName: String,
        volumeIdentifier: String,
        usedBytes: Int64,
        availableBytes: Int64,
        totalBytes: Int64,
        capturedAt: Date = .now
    ) {
        let normalizedTotal = max(0, totalBytes)
        let normalizedUsed = min(max(0, usedBytes), normalizedTotal)
        let normalizedAvailable = min(max(0, availableBytes), normalizedTotal)

        self.volumeName = volumeName
        self.volumeIdentifier = volumeIdentifier
        self.usedBytes = normalizedUsed
        self.availableBytes = normalizedAvailable
        self.totalBytes = normalizedTotal
        self.capturedAt = capturedAt
    }

    public var utilizationFraction: Double? {
        guard totalBytes > 0 else { return nil }
        return Double(usedBytes) / Double(totalBytes)
    }
}

public enum DiskCapacityUnavailableReason: String, Sendable, Equatable, CaseIterable {
    case metadataNotReady
    case resourceUnavailable
    case unsupportedVolume
    case unknown

    public var stableCode: String {
        switch self {
        case .metadataNotReady:
            return "DISK_METADATA_NOT_READY"
        case .resourceUnavailable:
            return "DISK_RESOURCE_UNAVAILABLE"
        case .unsupportedVolume:
            return "DISK_UNSUPPORTED_VOLUME"
        case .unknown:
            return "DISK_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .metadataNotReady:
            return "磁盘容量信息仍在准备中。"
        case .resourceUnavailable:
            return "当前无法读取磁盘容量信息。"
        case .unsupportedVolume:
            return "当前卷暂不支持容量概览。"
        case .unknown:
            return "磁盘容量信息暂不可用。"
        }
    }
}

public enum DiskCapacityAvailability: Sendable, Equatable {
    case idle
    case loading
    case available(DiskCapacitySnapshot)
    case unavailable(reason: DiskCapacityUnavailableReason)

    public var snapshot: DiskCapacitySnapshot? {
        guard case .available(let snapshot) = self else { return nil }
        return snapshot
    }

    public var unavailableReason: DiskCapacityUnavailableReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
