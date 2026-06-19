import XCTest
@testable import Omnipo

final class LauncherCommandTests: XCTestCase {

    func test_allCases_coverSixCommands() {
        XCTAssertEqual(LauncherCommand.allCases.count, 6)
        let ids = Set(LauncherCommand.allCases.map(\.id))
        XCTAssertEqual(ids.count, 6)
    }

    func test_displayTitles_areUniqueAndNonEmpty() {
        let titles = LauncherCommand.allCases.map(\.displayTitle)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
    }

    func test_searchableTexts_includeDisplayAndEnglishTitle() {
        for command in LauncherCommand.allCases {
            let texts = command.searchableTexts
            XCTAssertTrue(texts.contains(command.displayTitle))
            XCTAssertTrue(texts.contains(command.englishTitle))
        }
    }

    func test_keywords_areNonEmpty() {
        for command in LauncherCommand.allCases {
            XCTAssertFalse(command.keywords.isEmpty, "\(command) should have keywords")
        }
    }

    func test_symbolNames_areNonEmpty() {
        for command in LauncherCommand.allCases {
            XCTAssertFalse(command.symbolName.isEmpty)
        }
    }

    func test_id_isStableAcrossRawValue() {
        for command in LauncherCommand.allCases {
            XCTAssertEqual(command.id, command.rawValue)
        }
    }
}
