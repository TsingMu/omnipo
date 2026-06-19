import Foundation
import os

/// 默认搜索聚合服务。
///
/// 命令与应用提供者先并发完成并发布首批结果；文件提供者仅在 debounce 后启动，
/// 完成后把文件结果合并进最终批次。新查询和显式取消都会终止旧生产任务。
public final class DefaultSearchService: SearchService {
    private final class ActiveSearch: @unchecked Sendable {
        let generation: UInt64
        private let taskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        init(generation: UInt64) {
            self.generation = generation
        }

        func attach(_ task: Task<Void, Never>) {
            let cancelledBeforeAttach = taskLock.withLock { stored -> Bool in
                if stored == nil {
                    stored = task
                    return false
                }
                return true
            }
            if cancelledBeforeAttach {
                task.cancel()
            }
        }

        func cancel() {
            let task = taskLock.withLock { stored -> Task<Void, Never>? in
                if let stored { return stored }
                // 非 nil 占位表示取消先于 attach 到达。
                stored = Task { }
                return nil
            }
            task?.cancel()
        }
    }

    private struct ProviderOutput: Sendable {
        var results: [SearchResult] = []
        var failures: [SearchProviderFailure] = []
    }

    private let providers: [any SearchProvider]
    private let logger: any LoggingService
    private let fileDebounce: Duration
    private let generationLock = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private let activeSearchLock = OSAllocatedUnfairLock<ActiveSearch?>(initialState: nil)

    public init(
        providers: [any SearchProvider],
        logger: any LoggingService,
        fileDebounce: Duration = .milliseconds(150)
    ) {
        self.providers = providers
        self.logger = logger
        self.fileDebounce = fileDebounce
    }

    public func search(query: String) -> AsyncStream<SearchBatch> {
        let generation = nextGeneration()
        let activeSearch = ActiveSearch(generation: generation)
        let localProviders = providers.filter { $0.kind != SearchProviderKind.file }
        let fileProviders = query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            ? providers.filter { $0.kind == SearchProviderKind.file }
            : []

        let previous = activeSearchLock.withLock { active -> ActiveSearch? in
            let previous = active
            active = activeSearch
            return previous
        }
        previous?.cancel()

        return AsyncStream { continuation in
            let producer = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                defer {
                    continuation.finish()
                    self.clearActiveSearch(generation: generation)
                }

                let local = await Self.collect(
                    providers: localProviders,
                    query: query,
                    generation: generation
                )
                guard !Task.isCancelled else { return }

                let hasFilePhase = !fileProviders.isEmpty
                continuation.yield(SearchBatch(
                    generation: generation,
                    results: SearchRanker.rank(local.results),
                    failures: local.failures,
                    isFinal: !hasFilePhase
                ))

                guard hasFilePhase else {
                    self.logFailures(local.failures)
                    return
                }

                do {
                    try await Task.sleep(for: self.fileDebounce)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let files = await Self.collect(
                    providers: fileProviders,
                    query: query,
                    generation: generation
                )
                guard !Task.isCancelled else { return }

                let failures = local.failures + files.failures
                continuation.yield(SearchBatch(
                    generation: generation,
                    results: SearchRanker.rank(local.results + files.results),
                    failures: failures,
                    isFinal: true
                ))
                self.logFailures(failures)
            }

            activeSearch.attach(producer)
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }

    public func cancel() {
        let activeSearch = activeSearchLock.withLock { active -> ActiveSearch? in
            defer { active = nil }
            return active
        }
        activeSearch?.cancel()
    }

    private static func collect(
        providers: [any SearchProvider],
        query: String,
        generation: UInt64
    ) async -> ProviderOutput {
        await withTaskGroup(of: (kind: String, result: SearchProviderResult).self) { group in
            for provider in providers {
                group.addTask {
                    let result = await provider.search(query: query, generation: generation)
                    return (provider.kind, result)
                }
            }

            var output = ProviderOutput()
            for await (kind, result) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                switch result {
                case .success(let results):
                    output.results.append(contentsOf: results)
                case .failure(let failure):
                    output.failures.append(failure)
                case .unavailable(let reason):
                    output.failures.append(SearchProviderFailure(
                        providerKind: kind,
                        stableCode: "W_\(kind.uppercased())_UNAVAILABLE",
                        userDescription: reason
                    ))
                }
            }
            return output
        }
    }

    private func nextGeneration() -> UInt64 {
        generationLock.withLock { generation in
            generation &+= 1
            return generation
        }
    }

    private func clearActiveSearch(generation: UInt64) {
        activeSearchLock.withLock { active in
            guard active?.generation == generation else { return }
            active = nil
        }
    }

    private func logFailures(_ failures: [SearchProviderFailure]) {
        guard !failures.isEmpty else { return }
        logger.log(Self.logPartialFailures(count: failures.count))
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
