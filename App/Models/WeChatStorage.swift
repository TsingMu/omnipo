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
    case externalLinkSkipped
    case resourceUnavailable
    case scanCancelled
    case unknown

    public var stableCode: String { rawValue }

    public var displayName: String {
        switch self {
        case .rootMissing: return "未发现该位置"
        case .permissionLimited: return "目录不可读"
        case .tccOrSandboxLimited: return "受系统隐私保护"
        case .externalLinkSkipped: return "已跳过外部链接"
        case .resourceUnavailable: return "资源不可用"
        case .scanCancelled: return "扫描已取消"
        case .unknown: return "未知原因"
        }
    }

    public var explanation: String {
        switch self {
        case .rootMissing:
            return "未在该候选位置发现微信存储。"
        case .permissionLimited:
            return "当前进程无法读取该目录，可选择一个已授权目录后重试。"
        case .tccOrSandboxLimited:
            return "macOS 隐私保护阻止了读取，可在系统设置中检查完全磁盘访问。"
        case .externalLinkSkipped:
            return "链接指向已授权扫描范围之外，为保护隐私未继续跟随。"
        case .resourceUnavailable:
            return "扫描时该资源已不存在或暂时无法访问。"
        case .scanCancelled:
            return "扫描已按用户请求停止，当前结果可能不完整。"
        case .unknown:
            return "无法确定该位置不可用的具体原因。"
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

/// 文件的可见类型。仅由扩展名和系统 UTType 推断，不读取文件内容。
public enum WeChatAssetKind: String, CaseIterable, Codable, Sendable, Hashable {
    case video
    case image
    case audio
    case document
    case archive
    case database
    case other

    public var displayName: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .audio: return "音频"
        case .document: return "文档"
        case .archive: return "压缩包"
        case .database: return "数据库"
        case .other: return "其他"
        }
    }
}

/// 单个文件类型的大小与数量汇总。
public struct WeChatAssetSummary: Identifiable, Sendable, Hashable, Codable {
    public var id: WeChatAssetKind { kind }
    public var kind: WeChatAssetKind
    public var sizeBytes: Int
    public var fileCount: Int

    public init(kind: WeChatAssetKind, sizeBytes: Int, fileCount: Int) {
        self.kind = kind
        self.sizeBytes = max(0, sizeBytes)
        self.fileCount = max(0, fileCount)
    }
}

public enum WeChatConversationKind: String, CaseIterable, Codable, Sendable, Hashable {
    case directMessage
    case group
    case unknown

    public var displayName: String {
        switch self {
        case .directMessage: return "单聊"
        case .group: return "群聊"
        case .unknown: return "会话"
        }
    }
}

public enum WeChatAttributionConfidence: String, Codable, Sendable, Hashable {
    case high
    case inferred

    public var displayName: String {
        switch self {
        case .high: return "高可信"
        case .inferred: return "目录推断"
        }
    }
}

public struct WeChatStorageScanOptions: Sendable, Hashable {
    public var includeSensitiveNames: Bool

    public init(includeSensitiveNames: Bool = false) {
        self.includeSensitiveNames = includeSensitiveNames
    }

    public static let anonymous = WeChatStorageScanOptions()
}

/// 大文件的隐私安全摘要。`displayName` 不包含原始文件名或路径。
public struct WeChatLargeFile: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var kind: WeChatAssetKind
    public var displayName: String
    public var fileName: String?
    /// 仅用于本次授权扫描后的本地操作，不参与编码或持久化。
    public var fileURL: URL?
    public var sizeBytes: Int
    public var modifiedAt: Date?
    public var conversationID: String?

    public init(
        id: UUID = UUID(),
        kind: WeChatAssetKind,
        displayName: String,
        fileName: String?,
        sizeBytes: Int,
        modifiedAt: Date? = nil,
        conversationID: String? = nil
    ) {
        self.init(
            id: id,
            kind: kind,
            displayName: displayName,
            fileName: fileName,
            fileURL: nil,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            conversationID: conversationID
        )
    }

    public init(
        id: UUID = UUID(),
        kind: WeChatAssetKind,
        displayName: String,
        fileName: String?,
        fileURL: URL?,
        sizeBytes: Int,
        modifiedAt: Date? = nil,
        conversationID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.fileName = fileName
        self.fileURL = fileURL
        self.sizeBytes = max(0, sizeBytes)
        self.modifiedAt = modifiedAt
        self.conversationID = conversationID
    }

    public init(
        id: UUID = UUID(),
        kind: WeChatAssetKind,
        displayName: String,
        sizeBytes: Int,
        modifiedAt: Date? = nil,
        conversationID: String? = nil
    ) {
        self.init(
            id: id,
            kind: kind,
            displayName: displayName,
            fileName: nil,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            conversationID: conversationID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case displayName
        case fileName
        case sizeBytes
        case modifiedAt
        case conversationID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(WeChatAssetKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        fileURL = nil
        sizeBytes = max(0, try container.decode(Int.self, forKey: .sizeBytes))
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        conversationID = try container.decodeIfPresent(String.self, forKey: .conversationID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encode(sizeBytes, forKey: .sizeBytes)
        try container.encodeIfPresent(modifiedAt, forKey: .modifiedAt)
        try container.encodeIfPresent(conversationID, forKey: .conversationID)
    }
}

/// 由可识别目录结构推断出的匿名会话占用。
public struct WeChatConversationUsage: Identifiable, Sendable, Hashable, Codable {
    public var id: String { conversationID }
    public var conversationID: String
    public var kind: WeChatConversationKind
    public var displayName: String
    public var sizeBytes: Int
    public var fileCount: Int
    public var assets: [WeChatAssetSummary]
    public var topFiles: [WeChatLargeFile]
    public var confidence: WeChatAttributionConfidence

    public init(
        conversationID: String,
        kind: WeChatConversationKind,
        displayName: String,
        sizeBytes: Int,
        fileCount: Int,
        assets: [WeChatAssetSummary],
        topFiles: [WeChatLargeFile],
        confidence: WeChatAttributionConfidence
    ) {
        self.conversationID = conversationID
        self.kind = kind
        self.displayName = displayName
        self.sizeBytes = max(0, sizeBytes)
        self.fileCount = max(0, fileCount)
        self.assets = assets
        self.topFiles = topFiles
        self.confidence = confidence
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
    public var assets: [WeChatAssetSummary]
    public var largeFiles: [WeChatLargeFile]
    public var conversations: [WeChatConversationUsage]
    public var unattributedBytes: Int
    public var sensitiveNamesIncluded: Bool
    public var topGroups: [WeChatStorageGroup]
    public var roots: [WeChatStorageRoot]
    public var issues: [WeChatStorageIssue]
    public var completedAt: Date

    public init(
        totalVisibleBytes: Int = 0,
        categories: [WeChatStorageCategorySummary] = [],
        assets: [WeChatAssetSummary] = [],
        largeFiles: [WeChatLargeFile] = [],
        conversations: [WeChatConversationUsage] = [],
        unattributedBytes: Int = 0,
        sensitiveNamesIncluded: Bool,
        topGroups: [WeChatStorageGroup] = [],
        roots: [WeChatStorageRoot] = [],
        issues: [WeChatStorageIssue] = [],
        completedAt: Date = Date()
    ) {
        self.totalVisibleBytes = max(0, totalVisibleBytes)
        self.categories = categories
        self.assets = assets
        self.largeFiles = largeFiles
        self.conversations = conversations
        self.unattributedBytes = max(0, unattributedBytes)
        self.sensitiveNamesIncluded = sensitiveNamesIncluded
        self.topGroups = topGroups
        self.roots = roots
        self.issues = issues
        self.completedAt = completedAt
    }

    public init(
        totalVisibleBytes: Int = 0,
        categories: [WeChatStorageCategorySummary] = [],
        assets: [WeChatAssetSummary] = [],
        largeFiles: [WeChatLargeFile] = [],
        conversations: [WeChatConversationUsage] = [],
        unattributedBytes: Int = 0,
        topGroups: [WeChatStorageGroup] = [],
        roots: [WeChatStorageRoot] = [],
        issues: [WeChatStorageIssue] = [],
        completedAt: Date = Date()
    ) {
        self.init(
            totalVisibleBytes: totalVisibleBytes,
            categories: categories,
            assets: assets,
            largeFiles: largeFiles,
            conversations: conversations,
            unattributedBytes: unattributedBytes,
            sensitiveNamesIncluded: false,
            topGroups: topGroups,
            roots: roots,
            issues: issues,
            completedAt: completedAt
        )
    }

    /// 各分类大小之和。供 UI 校验 `totalVisibleBytes` 一致性。
    public var summedCategoryBytes: Int {
        categories.reduce(0) { $0 + $1.sizeBytes }
    }
}
