import Foundation

/// Launcher 搜索结果的可发送值模型。
///
/// 不持有 `NSImage` 或其他不可发送系统对象;图标通过描述符表达,
/// 执行通过稳定 payload 表达,文件 URL 不以明文出现。
public struct SearchResult: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case command
        case application
        case file
    }

    public enum IconDescriptor: Hashable, Sendable {
        case systemSymbol(name: String)
        case appBundleIdentifier(String)
        case fileType(String)
        case genericFile
        case none
    }

    public enum ExecutionPayload: Hashable, Sendable {
        case launcherCommand(LauncherCommand.ID)
        case applicationBundleIdentifier(String)
        case fileBookmark(Data)
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let matchScore: Double
    public let sourceIdentifier: String
    public let iconDescriptor: IconDescriptor
    public let executionPayload: ExecutionPayload

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        matchScore: Double,
        sourceIdentifier: String,
        iconDescriptor: IconDescriptor,
        executionPayload: ExecutionPayload
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.matchScore = matchScore
        self.sourceIdentifier = sourceIdentifier
        self.iconDescriptor = iconDescriptor
        self.executionPayload = executionPayload
    }

    public func withScore(_ score: Double) -> SearchResult {
        SearchResult(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            matchScore: score,
            sourceIdentifier: sourceIdentifier,
            iconDescriptor: iconDescriptor,
            executionPayload: executionPayload
        )
    }
}

extension SearchResult.IconDescriptor {
    public static func == (lhs: SearchResult.IconDescriptor, rhs: SearchResult.IconDescriptor) -> Bool {
        switch (lhs, rhs) {
        case (.systemSymbol(let a), .systemSymbol(let b)): return a == b
        case (.appBundleIdentifier(let a), .appBundleIdentifier(let b)): return a == b
        case (.fileType(let a), .fileType(let b)): return a == b
        case (.genericFile, .genericFile): return true
        case (.none, .none): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .systemSymbol(let name): hasher.combine("symbol"); hasher.combine(name)
        case .appBundleIdentifier(let id): hasher.combine("app"); hasher.combine(id)
        case .fileType(let type): hasher.combine("fileType"); hasher.combine(type)
        case .genericFile: hasher.combine("genericFile")
        case .none: hasher.combine("none")
        }
    }
}
