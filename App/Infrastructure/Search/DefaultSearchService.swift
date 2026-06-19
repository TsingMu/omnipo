import Foundation
import os

/// 默认搜索聚合服务。
///
/// 并发运行所有 provider,合并结果,隔离失败,按 SearchRanker 排序。
/// 单次 search 调用生成一个单调递增的 generation,LauncherStore 用它过滤过期批次。
public final class DefaultSearchService: SearchService {
    private let providers: [any SearchProvider]
    private let logger: any LoggingService
    private let generationLock = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    public init(providers: [any SearchProvider], logger: any LoggingService) {
        self.providers = providers
        self.logger = logger
    }

    public func search(query: String) async -> SearchBatch {
        let generation = nextGeneration()
        var all: [SearchResult] = []
        var failures: [SearchProviderFailure] = []

        await withTaskGroup(of: (kind: String, result: SearchProviderResult).self) { group in
            for provider in providers {
                let captured = provider
                group.addTask {
                    let result = await captured.search(query: query, generation: generation)
                    return (captured.kind, result)
                }
            }
            for await (kind, result) in group {
                switch result {
                case .success(let results):
                    all.append(contentsOf: results)
                case .failure(let failure):
                    failures.append(failure)
                case .unavailable(let reason):
                    let stableCode = "W_\(kind.uppercased())_UNAVAILABLE"
                    failures.append(SearchProviderFailure(
                        providerKind: kind,
                        stableCode: stableCode,
                        userDescription: reason
                    ))
                }
            }
        }

        if !failures.isEmpty {
            logger.log(Self.logPartialFailures(count: failures.count))
        }
        let ranked = SearchRanker.rank(all)
        return SearchBatch(
            generation: generation,
            results: ranked,
            failures: failures,
            isFinal: true
        )
    }

    public func cancel() async {
        // DefaultSearchService 自身无状态,取消由调用方在 search() 返回前取消 task 实现。
    }

    private func nextGeneration() -> UInt64 {
        generationLock.withLock { gen in
            gen += 1
            return gen
        }
    }

    private static func logPartialFailures(count: Int) -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.search.partialFailure",
            stableCode: "W_SEARCH_PARTIAL",
            sanitizedContext: [
                "code": "W_SEARCH_PARTIAL",
                "reason": "partial-failure",
                "systemCode": String(count)
            ]
        )
    }
}
