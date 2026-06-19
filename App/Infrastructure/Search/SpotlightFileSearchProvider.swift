import Foundation

/// 抽象的文件搜索后端,便于测试替身。
public protocol FileSearchBackend: Sendable {
    func search(query: String) async -> FileSearchBackendResult
}

public enum FileSearchBackendResult: Sendable {
    case success([FileEntry])
    case unavailable(reason: String)
}

public struct FileEntry: Sendable, Hashable {
    public let displayName: String
    public let bookmark: Data
    public let fileExtension: String?

    public init(displayName: String, bookmark: Data, fileExtension: String?) {
        self.displayName = displayName
        self.bookmark = bookmark
        self.fileExtension = fileExtension
    }
}

/// Spotlight 文件搜索提供者。
///
/// 仅查询系统已索引的元数据,不读取文件内容、不递归扫描磁盘。
/// 查询长度小于 2 时跳过 Spotlight,避免无界查询。
/// 结果数量受 `maxResults` 限制(默认 50)。
public final class SpotlightFileSearchProvider: SearchProvider {
    public let kind: String = SearchProviderKind.file

    private let backend: any FileSearchBackend
    private let logger: any LoggingService
    private let maxResults: Int

    public init(
        backend: any FileSearchBackend,
        logger: any LoggingService,
        maxResults: Int = 50
    ) {
        self.backend = backend
        self.logger = logger
        self.maxResults = maxResults
    }

    public func search(query: String, generation: UInt64) async -> SearchProviderResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            return .success([])
        }

        let backendResult = await backend.search(query: trimmed)
        switch backendResult {
        case .success(let entries):
            let limited = Array(entries.prefix(maxResults))
            let results = limited.map { entry -> SearchResult in
                let iconDescriptor: SearchResult.IconDescriptor
                if let ext = entry.fileExtension, !ext.isEmpty {
                    iconDescriptor = .fileType(ext)
                } else {
                    iconDescriptor = .genericFile
                }
                let bookmarkKey = entry.bookmark.base64EncodedString()
                return SearchResult(
                    kind: .file,
                    title: entry.displayName,
                    subtitle: nil,
                    matchScore: 0.3,
                    sourceIdentifier: "spotlight.\(bookmarkKey.prefix(32))",
                    iconDescriptor: iconDescriptor,
                    executionPayload: .fileBookmark(entry.bookmark)
                )
            }
            return .success(results)
        case .unavailable(let reason):
            logger.log(Self.logUnavailable())
            return .unavailable(reason: reason)
        }
    }

    private static func logUnavailable() -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "launcher.file.unavailable",
            stableCode: "I_FILE_UNAVAILABLE",
            sanitizedContext: ["code": "I_FILE_UNAVAILABLE", "reason": "spotlight-unavailable"]
        )
    }
}
