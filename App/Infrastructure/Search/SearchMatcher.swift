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

    public struct CandidateForms: Sendable, Hashable {
        public let text: String
        public let forms: [String]
    }

    /// 对多个候选文本返回最高分。
    public static func bestMatch(query: String, candidates: [String]) -> Best? {
        bestMatch(query: query, preparedCandidates: preparedCandidates(for: candidates))
    }

    /// 对预先规范化的候选文本返回最高分。
    public static func bestMatch(query: String, preparedCandidates: [CandidateForms]) -> Best? {
        let queryForms = forms(for: query)
        guard !queryForms.isEmpty else { return nil }
        var best: Best?
        for candidate in preparedCandidates {
            for queryForm in queryForms {
                for candidateForm in candidate.forms {
                    let matchScore = score(query: queryForm, against: candidateForm)
                    if matchScore > 0, best == nil || matchScore > best!.score {
                        best = Best(score: matchScore, matchedText: candidate.text)
                    }
                }
            }
        }
        return best
    }

    public static func preparedCandidates(for candidates: [String]) -> [CandidateForms] {
        candidates.map { CandidateForms(text: $0, forms: forms(for: $0)) }
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
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: query, range: searchRange) {
            if range.lowerBound == text.startIndex {
                return true
            }

            let previous = text.index(before: range.lowerBound)
            if !isASCIILetterOrDigit(text[previous]) {
                return true
            }

            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    private static func isASCIILetterOrDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
            return false
        }
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }
}
