import Foundation

/// 跨提供者结果合并、去重与稳定排序。
public enum SearchRanker {

    private struct DedupKey: Hashable {
        let kind: SearchResult.Kind
        let identifier: String
    }

    /// 合并多批结果,按 (kind, sourceIdentifier) 去重(保留最高分),
    /// 然后按 kind 优先级→分数→sourceIdentifier 字典序排序。
    public static func rank(_ results: [SearchResult]) -> [SearchResult] {
        var bestByKey: [DedupKey: SearchResult] = [:]
        var insertionOrder: [DedupKey] = []

        for result in results {
            let key = DedupKey(kind: result.kind, identifier: result.sourceIdentifier)
            if let existing = bestByKey[key] {
                if result.matchScore > existing.matchScore {
                    bestByKey[key] = result
                }
            } else {
                bestByKey[key] = result
                insertionOrder.append(key)
            }
        }

        let unique = insertionOrder.compactMap { bestByKey[$0] }

        return unique.sorted { a, b in
            let pa = kindPriority(a.kind)
            let pb = kindPriority(b.kind)
            if pa != pb {
                return pa < pb
            }
            if a.matchScore != b.matchScore {
                return a.matchScore > b.matchScore
            }
            return a.sourceIdentifier < b.sourceIdentifier
        }
    }

    public static func kindPriority(_ kind: SearchResult.Kind) -> Int {
        switch kind {
        case .application: return 0
        case .file: return 1
        case .command: return 2
        }
    }
}
