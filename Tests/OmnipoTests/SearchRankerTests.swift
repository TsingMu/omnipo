import XCTest
@testable import Omnipo

final class SearchMatcherTests: XCTestCase {

    func test_exactMatch_scoresHighest() {
        XCTAssertEqual(SearchMatcher.score(query: "open", against: "open"), 1.0)
    }

    func test_prefixMatch_scoresHigherThanWordBoundary() {
        let prefix = SearchMatcher.score(query: "open", against: "open clipboard")
        XCTAssertEqual(prefix, 0.8)
    }

    func test_wordBoundaryMatch_scoresHigherThanSubstring() {
        let word = SearchMatcher.score(query: "clipboard", against: "open clipboard history")
        XCTAssertEqual(word, 0.6)
    }

    func test_substringMatch_scoresLowest() {
        let sub = SearchMatcher.score(query: "lip", against: "clipboard")
        XCTAssertEqual(sub, 0.4)
    }

    func test_noMatch_scoresZero() {
        XCTAssertEqual(SearchMatcher.score(query: "xyz", against: "clipboard"), 0)
    }

    func test_bestMatch_picksHighestScoreAcrossCandidates() {
        let best = SearchMatcher.bestMatch(query: "open", candidates: [
            "Open Clipboard",
            "open",
            "clipboard"
        ])
        XCTAssertEqual(best?.score, 1.0)
        XCTAssertEqual(best?.matchedText, "open")
    }

    func test_bestMatch_returnsNilForEmptyQuery() {
        XCTAssertNil(SearchMatcher.bestMatch(query: "  ", candidates: ["a"]))
    }

    func test_normalize_lowercasesAndTrims() {
        XCTAssertEqual(SearchMatcher.normalize("  Hello WORLD  "), "hello world")
    }

    func test_normalize_foldsWidthAndDiacritics() {
        XCTAssertEqual(SearchMatcher.normalize("  ＷéＣhat  "), "wechat")
    }

    func test_forms_addsCompactPinyinVariant() {
        XCTAssertEqual(SearchMatcher.forms(for: "we chat"), ["we chat", "wechat"])
        XCTAssertEqual(SearchMatcher.forms(for: "wei'xin"), ["wei'xin", "weixin"])
    }

    func test_bestMatch_usesCompactForms() {
        let best = SearchMatcher.bestMatch(query: "we chat", candidates: ["WeChat"])
        XCTAssertEqual(best?.score, 1.0)
    }
}

final class SearchRankerTests: XCTestCase {

    private func make(_ kind: SearchResult.Kind, _ id: String, _ score: Double) -> SearchResult {
        SearchResult(
            kind: kind,
            title: id,
            matchScore: score,
            sourceIdentifier: id,
            iconDescriptor: .none,
            executionPayload: .launcherCommand(id)
        )
    }

    func test_rank_ordersByScoreDescending() {
        let ranked = SearchRanker.rank([
            make(.command, "low", 0.4),
            make(.command, "high", 1.0),
            make(.command, "mid", 0.8)
        ])
        XCTAssertEqual(ranked.map(\.sourceIdentifier), ["high", "mid", "low"])
    }

    func test_rank_kindPriorityBreaksScoreTie() {
        let ranked = SearchRanker.rank([
            make(.file, "f", 0.5),
            make(.application, "a", 0.5),
            make(.command, "c", 0.5)
        ])
        XCTAssertEqual(ranked.map(\.kind), [.command, .application, .file])
    }

    func test_rank_sourceIdentifierBreaksSameKindSameScore() {
        let ranked = SearchRanker.rank([
            make(.command, "zeta", 0.5),
            make(.command, "alpha", 0.5)
        ])
        XCTAssertEqual(ranked.map(\.sourceIdentifier), ["alpha", "zeta"])
    }

    func test_rank_deduplicatesKeepingHighestScore() {
        let ranked = SearchRanker.rank([
            make(.command, "open", 0.4),
            make(.command, "open", 1.0),
            make(.command, "open", 0.6)
        ])
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.matchScore, 1.0)
    }

    func test_rank_dedupRespectsKind() {
        let ranked = SearchRanker.rank([
            make(.command, "x", 0.5),
            make(.application, "x", 0.5),
            make(.file, "x", 0.5)
        ])
        XCTAssertEqual(ranked.count, 3)
    }
}

final class CommandSearchProviderTests: XCTestCase {

    func test_emptyQuery_returnsAllSixCommands() async {
        let provider = CommandSearchProvider()
        let result = await provider.search(query: "", generation: 1)

        if case .success(let results) = result {
            XCTAssertEqual(results.count, 6)
            XCTAssertEqual(Set(results.map { $0.sourceIdentifier }).count, 6)
        } else {
            XCTFail("expected success")
        }
    }

    func test_whitespaceOnlyQuery_returnsAllSixCommands() async {
        let provider = CommandSearchProvider()
        let result = await provider.search(query: "   ", generation: 1)

        if case .success(let results) = result {
            XCTAssertEqual(results.count, 6)
        } else {
            XCTFail("expected success")
        }
    }

    func test_exactChineseTitle_matches() async {
        let provider = CommandSearchProvider()
        let result = await provider.search(query: "权限审计", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.contains { $0.sourceIdentifier == LauncherCommand.auditPermissions.id })
            XCTAssertEqual(results.first?.matchScore, 1.0)
        } else {
            XCTFail("expected success")
        }
    }

    func test_keywordMatch_returnsRelevantCommand() async {
        let provider = CommandSearchProvider()
        let result = await provider.search(query: "wechat", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.contains { $0.sourceIdentifier == LauncherCommand.inspectWeChatStorage.id })
        } else {
            XCTFail("expected success")
        }
    }

    func test_noMatch_returnsEmpty() async {
        let provider = CommandSearchProvider()
        let result = await provider.search(query: "xyzqqq", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.isEmpty)
        } else {
            XCTFail("expected success")
        }
    }

    func test_results_carryLauncherCommandPayload() async {
        let provider = CommandSearchProvider()
        let result = await provider.search(query: "", generation: 1)

        if case .success(let results) = result {
            for r in results {
                if case .launcherCommand = r.executionPayload {
                    // ok
                } else {
                    XCTFail("command result must carry launcherCommand payload")
                }
            }
        }
    }
}
