import Foundation

/// 内置命令搜索提供者。
///
/// 非空查询根据 displayTitle、englishTitle 与关键词进行完全/前缀/单词边界/子串匹配。
public final class CommandSearchProvider: SearchProvider {
    public let kind: String = SearchProviderKind.command

    public init() {}

    public func search(query: String, generation: UInt64) async -> SearchProviderResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .success([])
        }
        let matched = LauncherCommand.allCases.compactMap { command -> SearchResult? in
            guard let best = SearchMatcher.bestMatch(query: trimmed, candidates: command.searchableTexts) else {
                return nil
            }
            return result(for: command, score: best.score)
        }
        return .success(matched)
    }

    private func result(for command: LauncherCommand, score: Double) -> SearchResult {
        SearchResult(
            kind: .command,
            title: command.displayTitle,
            subtitle: command.englishTitle,
            matchScore: score,
            sourceIdentifier: command.id,
            iconDescriptor: .systemSymbol(name: command.symbolName),
            executionPayload: .launcherCommand(command.id)
        )
    }
}
