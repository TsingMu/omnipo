import Foundation

/// 微信存储根的位置类别。
public enum WeChatStorageRootKind: String, CaseIterable, Codable, Sendable, Hashable {
    case applicationContainer
    case applicationSupport
    case cache
    case groupContainer
    case userSelected
    case other

    public var displayName: String {
        switch self {
        case .applicationContainer: return "应用容器"
        case .applicationSupport: return "应用支持"
        case .cache: return "缓存"
        case .groupContainer: return "共享容器"
        case .userSelected: return "自选目录"
        case .other: return "其他"
        }
    }
}

/// 微信存储根或子项不可读的稳定原因。
public enum WeChatStorageAvailabilityReason: String, CaseIterable, Codable, Sendable, Hashable {
    case rootMissing
    case permissionLimited
    case tccOrSandboxLimited
    case resourceUnavailable
    case scanCancelled
    case unknown

    public var stableCode: String { rawValue }

    public var displayName: String {
        switch self {
        case .rootMissing: return "未发现该位置"
        case .permissionLimited: return "权限不足"
        case .tccOrSandboxLimited: return "受系统保护"
        case .resourceUnavailable: return "资源不可用"
        case .scanCancelled: return "扫描已取消"
        case .unknown: return "未知原因"
        }
    }
}

/// 根的可用性:可读,或带原因的不可读。
public enum WeChatStorageAvailability: Sendable, Hashable, Codable {
    case readable
    case unavailable(WeChatStorageAvailabilityReason)
}

/// 已发现或用户授权的微信存储根。
public struct WeChatStorageRoot: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var url: URL
    public var kind: WeChatStorageRootKind
    public var displayName: String
    public var availability: WeChatStorageAvailability

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: WeChatStorageRootKind,
        displayName: String,
        availability: WeChatStorageAvailability
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.displayName = displayName
        self.availability = availability
    }
}

/// 微信存储的粗分类。类别由路径推断,不读取文件内容。
public enum WeChatStorageCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case cache
    case mediaAndFiles
    case logs
    case databasesAndState
    case backups
    case configuration
    case other

    public var displayName: String {
        switch self {
        case .cache: return "缓存"
        case .mediaAndFiles: return "媒体与文件"
        case .logs: return "日志"
        case .databasesAndState: return "数据库与本地状态"
        case .backups: return "备份"
        case .configuration: return "配置"
        case .other: return "其他"
        }
    }

    /// 用户可见的隐私说明:强调只统计元数据,不读取内容,且类别不源自消息解析。
    public var privacyNote: String {
        switch self {
        case .cache:
            return "仅统计缓存文件占用,不读取内容;缓存可在不影响账号的前提下重建。"
        case .mediaAndFiles:
            return "仅统计媒体与文件占用,不解析图片、视频或文件内容。"
        case .logs:
            return "仅统计日志占用,不读取日志文本。"
        case .databasesAndState:
            return "按路径推断为数据库或本地状态,绝不打开或解析数据库内容。"
        case .backups:
            return "仅统计备份占用,不读取备份数据。"
        case .configuration:
            return "仅统计配置占用,不读取配置内容。"
        case .other:
            return "未能归入其他类别,不读取文件内容。"
        }
    }
}

/// 单个分类的汇总大小与文件数。
public struct WeChatStorageCategorySummary: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var category: WeChatStorageCategory
    public var sizeBytes: Int
    public var fileCount: Int

    public init(id: UUID = UUID(), category: WeChatStorageCategory, sizeBytes: Int, fileCount: Int) {
        self.id = id
        self.category = category
        self.sizeBytes = max(0, sizeBytes)
        self.fileCount = max(0, fileCount)
    }
}

/// 一个聚合存储组(通常是根下的子目录)。`displayName` 必须脱敏。
public struct WeChatStorageGroup: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var category: WeChatStorageCategory
    public var displayName: String
    public var sizeBytes: Int
    public var fileCount: Int
    public var lastModified: Date?
    public var riskNote: String?

    public init(
        id: UUID = UUID(),
        category: WeChatStorageCategory,
        displayName: String,
        sizeBytes: Int,
        fileCount: Int,
        lastModified: Date? = nil,
        riskNote: String? = nil
    ) {
        self.id = id
        self.category = category
        self.displayName = displayName
        self.sizeBytes = max(0, sizeBytes)
        self.fileCount = max(0, fileCount)
        self.lastModified = lastModified
        self.riskNote = riskNote
    }
}

/// 扫描中发现的问题。仅含稳定码、root id/kind 与脱敏显示名;
/// 不得携带原始路径、文件名或账号样路径组件(见 design symlink 隐私约束)。
public struct WeChatStorageIssue: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var rootID: UUID?
    public var rootKind: WeChatStorageRootKind?
    public var reason: WeChatStorageAvailabilityReason
    public var sanitizedDisplayName: String?

    public init(
        id: UUID = UUID(),
        rootID: UUID? = nil,
        rootKind: WeChatStorageRootKind? = nil,
        reason: WeChatStorageAvailabilityReason,
        sanitizedDisplayName: String? = nil
    ) {
        self.id = id
        self.rootID = rootID
        self.rootKind = rootKind
        self.reason = reason
        self.sanitizedDisplayName = sanitizedDisplayName
    }
}

/// 一次微信存储扫描的完整结果。
public struct WeChatStorageScanResult: Sendable, Hashable, Codable {
    public var totalVisibleBytes: Int
    public var categories: [WeChatStorageCategorySummary]
    public var topGroups: [WeChatStorageGroup]
    public var roots: [WeChatStorageRoot]
    public var issues: [WeChatStorageIssue]
    public var completedAt: Date

    public init(
        totalVisibleBytes: Int = 0,
        categories: [WeChatStorageCategorySummary] = [],
        topGroups: [WeChatStorageGroup] = [],
        roots: [WeChatStorageRoot] = [],
        issues: [WeChatStorageIssue] = [],
        completedAt: Date = Date()
    ) {
        self.totalVisibleBytes = max(0, totalVisibleBytes)
        self.categories = categories
        self.topGroups = topGroups
        self.roots = roots
        self.issues = issues
        self.completedAt = completedAt
    }

    /// 各分类大小之和。供 UI 校验 `totalVisibleBytes` 一致性。
    public var summedCategoryBytes: Int {
        categories.reduce(0) { $0 + $1.sizeBytes }
    }
}
