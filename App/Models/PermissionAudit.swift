import Foundation

public enum PermissionCategory: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case camera
    case microphone
    case photos
    case contacts
    case calendar
    case reminders
    case accessibility
    case fullDiskAccess

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .camera: return "相机"
        case .microphone: return "麦克风"
        case .photos: return "照片"
        case .contacts: return "通讯录"
        case .calendar: return "日历"
        case .reminders: return "提醒事项"
        case .accessibility: return "辅助功能"
        case .fullDiskAccess: return "完全磁盘访问"
        }
    }

    public var symbolName: String {
        switch self {
        case .camera: return "camera"
        case .microphone: return "mic"
        case .photos: return "photo.on.rectangle"
        case .contacts: return "person.crop.circle"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .accessibility: return "figure.roll"
        case .fullDiskAccess: return "externaldrive.badge.shield"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .camera: return 0
        case .microphone: return 1
        case .photos: return 2
        case .contacts: return 3
        case .calendar: return 4
        case .reminders: return 5
        case .accessibility: return 6
        case .fullDiskAccess: return 7
        }
    }
}

public enum PermissionUnavailableReason: String, CaseIterable, Codable, Sendable, Hashable {
    case databaseUnreadable
    case permissionLimited
    case unsupportedOnCurrentSystem
    case resourceUnavailable
    case unknown

    public var stableCode: String {
        switch self {
        case .databaseUnreadable: return "PERMISSION_DB_UNREADABLE"
        case .permissionLimited: return "PERMISSION_LIMITED"
        case .unsupportedOnCurrentSystem: return "PERMISSION_UNSUPPORTED_SYSTEM"
        case .resourceUnavailable: return "PERMISSION_RESOURCE_UNAVAILABLE"
        case .unknown: return "PERMISSION_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .databaseUnreadable:
            return "当前无法只读读取权限数据库。"
        case .permissionLimited:
            return "当前环境缺少读取此权限状态所需的访问条件。"
        case .unsupportedOnCurrentSystem:
            return "当前 macOS 版本暂不支持稳定读取此权限状态。"
        case .resourceUnavailable:
            return "当前权限状态数据源不可用。"
        case .unknown:
            return "当前无法判断此权限状态。"
        }
    }
}

public enum PermissionGrantStatus: Codable, Sendable, Hashable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unavailable(reason: PermissionUnavailableReason)
    case unknown

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    public var unavailableReason: PermissionUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    public var displayName: String {
        switch self {
        case .authorized: return "已授权"
        case .denied: return "未授权"
        case .restricted: return "受限制"
        case .notDetermined: return "未决定"
        case .unavailable: return "不可读取"
        case .unknown: return "未知"
        }
    }
}

public struct AppPermissionGrant: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let bundleIdentifier: String
    public let displayName: String
    public let category: PermissionCategory
    public let status: PermissionGrantStatus
    public let source: String
    public let lastUpdatedAt: Date?

    public init(
        id: String? = nil,
        bundleIdentifier: String,
        displayName: String,
        category: PermissionCategory,
        status: PermissionGrantStatus,
        source: String,
        lastUpdatedAt: Date? = nil
    ) {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBundleIdentifier = normalizedBundleIdentifier.isEmpty ? "unknown.bundle" : normalizedBundleIdentifier
        let resolvedDisplayName = normalizedDisplayName.isEmpty ? resolvedBundleIdentifier : normalizedDisplayName
        self.id = id ?? "\(category.rawValue)::\(resolvedBundleIdentifier)"
        self.bundleIdentifier = resolvedBundleIdentifier
        self.displayName = resolvedDisplayName
        self.category = category
        self.status = status
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastUpdatedAt = lastUpdatedAt
    }
}

public struct PermissionAuditSummary: Codable, Sendable, Hashable {
    public let totalGrantCount: Int
    public let authorizedGrantCount: Int
    public let unavailableGrantCount: Int

    public init(totalGrantCount: Int, authorizedGrantCount: Int, unavailableGrantCount: Int) {
        self.totalGrantCount = max(0, totalGrantCount)
        self.authorizedGrantCount = max(0, min(authorizedGrantCount, self.totalGrantCount))
        self.unavailableGrantCount = max(0, min(unavailableGrantCount, self.totalGrantCount))
    }
}

public struct PermissionAuditResult: Codable, Sendable, Hashable {
    public let grants: [AppPermissionGrant]
    public let unavailableCategories: [PermissionCategory: PermissionUnavailableReason]
    public let summary: PermissionAuditSummary

    public init(
        grants: [AppPermissionGrant],
        unavailableCategories: [PermissionCategory: PermissionUnavailableReason] = [:],
        summary: PermissionAuditSummary? = nil
    ) {
        let sortedGrants = grants.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.bundleIdentifier.localizedStandardCompare(rhs.bundleIdentifier) == .orderedAscending
        }
        self.grants = sortedGrants
        self.unavailableCategories = unavailableCategories

        if let summary {
            self.summary = summary
        } else {
            let totalGrantCount = sortedGrants.count
            let authorizedGrantCount = sortedGrants.reduce(into: 0) { partialResult, grant in
                if grant.status == .authorized {
                    partialResult += 1
                }
            }
            let unavailableGrantCount = sortedGrants.reduce(into: 0) { partialResult, grant in
                if grant.status.isUnavailable {
                    partialResult += 1
                }
            }
            self.summary = PermissionAuditSummary(
                totalGrantCount: totalGrantCount,
                authorizedGrantCount: authorizedGrantCount,
                unavailableGrantCount: unavailableGrantCount
            )
        }
    }

    public var isEmpty: Bool {
        grants.isEmpty && unavailableCategories.isEmpty
    }
}

