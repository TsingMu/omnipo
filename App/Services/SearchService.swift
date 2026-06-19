import Foundation

/// Launcher 搜索聚合服务。
///
/// 接收查询文本,异步返回一批或多批结果。查询代次用于拒绝过期结果;
/// 提供者错误被隔离,单个失败不清除其他成功结果。
public protocol SearchService: AnyObject, Sendable {
    func search(query: String) -> AsyncStream<SearchBatch>
    func cancel()
}

public protocol SearchProvider: Sendable {
    var kind: String { get }
    func search(query: String, generation: UInt64) async -> SearchProviderResult
}

public enum SearchProviderResult: Sendable {
    case success([SearchResult])
    case failure(SearchProviderFailure)
    case unavailable(reason: String)
}

public struct SearchProviderFailure: Sendable, Equatable {
    public let providerKind: String
    public let stableCode: String
    public let userDescription: String?

    public init(providerKind: String, stableCode: String, userDescription: String?) {
        self.providerKind = providerKind
        self.stableCode = stableCode
        self.userDescription = userDescription
    }
}

public struct SearchBatch: Sendable, Equatable {
    public let generation: UInt64
    public let results: [SearchResult]
    public let failures: [SearchProviderFailure]
    public let isFinal: Bool

    public init(
        generation: UInt64,
        results: [SearchResult],
        failures: [SearchProviderFailure] = [],
        isFinal: Bool = true
    ) {
        self.generation = generation
        self.results = results
        self.failures = failures
        self.isFinal = isFinal
    }

    public static let empty = SearchBatch(generation: 0, results: [], isFinal: true)
}

public enum SearchProviderKind {
    public static let command = "command"
    public static let application = "application"
    public static let file = "file"
}
