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
        let queryForms = forms(for: query)
        guard !queryForms.isEmpty else { return nil }
        var best: Best?
        for c in candidates {
            let candidateForms = forms(for: c)
            for queryForm in queryForms {
                for candidateForm in candidateForms {
                    let matchScore = score(query: queryForm, against: candidateForm)
                    if matchScore > 0, best == nil || matchScore > best!.score {
                        best = Best(score: matchScore, matchedText: c)
                    }
                }
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
        s.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: \Character.isWhitespace)
        .joined(separator: " ")
    }

    /// 返回原始规范化形式以及适合拼音组合文本的紧凑形式。
    ///
    /// 输入法可能把 `wechat` 显示为 `we chat` 或 `we'chat`。紧凑形式仅移除
    /// 空白和常见拼音分隔撇号，不改写搜索框显示值。
    public static func forms(for text: String) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }

        let compact = normalized.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && scalar != "'"
                && scalar != "’"
                && scalar != "ʼ"
        }
        let compactString = String(String.UnicodeScalarView(compact))
        return compactString == normalized ? [normalized] : [normalized, compactString]
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
