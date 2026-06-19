import XCTest
@testable import Omnipo

final class SearchResultTests: XCTestCase {

    func test_init_preservesAllFields() {
        let result = SearchResult(
            kind: .command,
            title: "打开剪切板",
            subtitle: "Open Clipboard",
            matchScore: 0.9,
            sourceIdentifier: "command.openClipboard",
            iconDescriptor: .systemSymbol(name: "doc.on.clipboard"),
            executionPayload: .launcherCommand(LauncherCommand.openClipboard.id)
        )

        XCTAssertEqual(result.kind, .command)
        XCTAssertEqual(result.title, "打开剪切板")
        XCTAssertEqual(result.subtitle, "Open Clipboard")
        XCTAssertEqual(result.matchScore, 0.9, accuracy: 0.0001)
        XCTAssertEqual(result.sourceIdentifier, "command.openClipboard")
    }

    func test_withScore_preservesIdentity() {
        let original = SearchResult(
            kind: .command,
            title: "title",
            matchScore: 0.1,
            sourceIdentifier: "src",
            iconDescriptor: .none,
            executionPayload: .launcherCommand(LauncherCommand.scanDisk.id)
        )
        let updated = original.withScore(0.95)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.matchScore, 0.95, accuracy: 0.0001)
        XCTAssertEqual(updated.title, original.title)
    }

    func test_iconDescriptor_equality() {
        XCTAssertEqual(SearchResult.IconDescriptor.systemSymbol(name: "x"), .systemSymbol(name: "x"))
        XCTAssertNotEqual(SearchResult.IconDescriptor.systemSymbol(name: "x"), .systemSymbol(name: "y"))
        XCTAssertEqual(SearchResult.IconDescriptor.appBundleIdentifier("com.test"), .appBundleIdentifier("com.test"))
        XCTAssertNotEqual(SearchResult.IconDescriptor.appBundleIdentifier("com.test"), .appBundleIdentifier("com.other"))
        XCTAssertEqual(SearchResult.IconDescriptor.fileType("pdf"), .fileType("pdf"))
        XCTAssertEqual(SearchResult.IconDescriptor.genericFile, .genericFile)
        XCTAssertEqual(SearchResult.IconDescriptor.none, .none)
        XCTAssertNotEqual(SearchResult.IconDescriptor.genericFile, .none)
    }

    func test_filePayload_doesNotEmbedURLString() {
        let bookmark = Data([0x01, 0x02, 0x03])
        let result = SearchResult(
            kind: .file,
            title: "report.pdf",
            matchScore: 0.5,
            sourceIdentifier: "file.bookmark.1",
            iconDescriptor: .fileType("pdf"),
            executionPayload: .fileBookmark(bookmark)
        )

        if case .fileBookmark(let data) = result.executionPayload {
            XCTAssertEqual(data, bookmark)
        } else {
            XCTFail("expected fileBookmark payload")
        }
    }
}
