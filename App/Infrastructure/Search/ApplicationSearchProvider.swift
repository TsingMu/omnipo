import Foundation
import os

/// 应用搜索提供者。
///
/// 不直接持有 `NSImage` 等不可发送对象;图标通过 `appBundleIdentifier` 描述符表达,
/// 由 UI 层在 MainActor 上根据 bundle ID 现取图标。
public final class ApplicationSearchProvider: SearchProvider {
    public let kind: String = SearchProviderKind.application

    private let discover: @Sendable () async -> [AppRecord]
    private let cache = OSAllocatedUnfairLock<CacheState>(initialState: CacheState())

    private struct CacheState: Sendable {
        var records: [AppRecord] = []
        var lastRefresh: Date = .distantPast
    }

    /// 60 秒内复用缓存,避免每次输入触发新的扫描。
    private let cacheTTL: TimeInterval = 60

    public init(discover: @escaping @Sendable () async -> [AppRecord]) {
        self.discover = discover
    }

    public func search(query: String, generation: UInt64) async -> SearchProviderResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .success([])
        }
        let apps = await currentRecords()
        let matched = apps.compactMap { app -> SearchResult? in
            guard let best = SearchMatcher.bestMatch(query: trimmed, candidates: app.searchCandidates) else {
                return nil
            }
            return SearchResult(
                kind: .application,
                title: app.displayName,
                subtitle: app.bundleIdentifier,
                matchScore: best.score,
                sourceIdentifier: app.bundleIdentifier,
                iconDescriptor: .appBundleIdentifier(app.bundleIdentifier),
                executionPayload: .applicationBundleIdentifier(app.bundleIdentifier)
            )
        }
        return .success(matched)
    }

    public func refresh() async {
        let fresh = await discover()
        cache.withLock { state in
            state.records = fresh
            state.lastRefresh = Date()
        }
    }

    private func currentRecords() async -> [AppRecord] {
        let now = Date()
        let snapshot = cache.withLock { $0 }
        if !snapshot.records.isEmpty && now.timeIntervalSince(snapshot.lastRefresh) < cacheTTL {
            return snapshot.records
        }
        await refresh()
        return cache.withLock { $0.records }
    }
}
