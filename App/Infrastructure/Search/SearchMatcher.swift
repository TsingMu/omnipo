import Foundation

/// 搜索匹配器:对查询和候选文本打分。
///
/// 评分阶梯:
/// - 完全匹配 1.0
/// - 前缀匹配 0.8
/// - 单词边界匹配 0.6
/// - 子串匹配 0.4
/// - 无匹配 0(不返回)
public enum SearchMatcher {

    public struct Best {
        public let score: Double
        public let matchedText: String
    }

    /// 对多个候选文本返回最高分。
    public static func bestMatch(query: String, candidates: [String]) -> Best? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        var best: Best?
        for c in candidates {
            let normalizedC = normalize(c)
            let score = score(query: q, against: normalizedC)
            if score > 0, best == nil || score > best!.score {
                best = Best(score: score, matchedText: c)
            }
        }
        return best
    }

    public static func score(query: String, against text: String) -> Double {
        if text.isEmpty || query.isEmpty { return 0 }
        if text == query { return 1.0 }
        if text.hasPrefix(query) { return 0.8 }
        if atWordBoundary(text: text, query: query) { return 0.6 }
        if text.contains(query) { return 0.4 }
        return 0
    }

    public static func normalize(_ s: String) -> String {
        s
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{3000}", with: " ")
    }

    /// 检查 query 是否在 text 的单词边界后出现(开头或非字母数字字符之后)。
    public static func atWordBoundary(text: String, query: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let pattern = "(?:^|[^a-z0-9])" + escaped
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
