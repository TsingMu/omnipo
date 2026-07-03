import Foundation

/// 应用搜索提供者。
///
/// 不直接持有 `NSImage` 等不可发送对象;图标通过 `appBundleIdentifier` 描述符表达,
/// 由 UI 层在 MainActor 上根据 bundle ID 现取图标。
public final class ApplicationSearchProvider: SearchProvider {
    public let kind: String = SearchProviderKind.application

    private let index: ApplicationIndex

    public init(discover: @escaping @Sendable () async -> [AppRecord]) {
        self.index = ApplicationIndex(discover: discover)
    }

    public init(index: ApplicationIndex) {
        self.index = index
    }

    public func search(query: String, generation: UInt64) async -> SearchProviderResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = await index.currentRecords()
        if trimmed.isEmpty {
            return .success(apps.map { app in
                SearchResult(
                    kind: .application,
                    title: app.displayName,
                    subtitle: app.bundleIdentifier,
                    matchScore: 0.5,
                    sourceIdentifier: app.bundleIdentifier,
                    iconDescriptor: .appBundleIdentifier(app.bundleIdentifier),
                    executionPayload: .applicationBundleIdentifier(app.bundleIdentifier)
                )
            })
        }
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
        await index.refresh()
    }
}
