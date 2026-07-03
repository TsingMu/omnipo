import XCTest
@testable import Omnipo

final class ClipboardContentReaderTests: XCTestCase {

    func test_classifier_returnsNilForEmptySnapshot() {
        XCTAssertNil(ClipboardContentClassifier.capturedContent(from: ClipboardPasteboardSnapshot()))
    }

    func test_classifier_classifiesPlainText() throws {
        let content = try XCTUnwrap(
            ClipboardContentClassifier.capturedContent(
                from: ClipboardPasteboardSnapshot(plainText: "  hello\nworld  ")
            )
        )

        XCTAssertEqual(content.contentType, .plainText)
        XCTAssertEqual(content.textPreview, "hello world")
        XCTAssertEqual(content.payloads, [
            ClipboardCapturedPayload(format: .plainText, data: Data("  hello\nworld  ".utf8))
        ])
        XCTAssertFalse(content.contentHash.isEmpty)
    }

    func test_classifier_classifiesRTFAndKeepsPlainTextFallback() throws {
        let rtf = Data("{\\rtf1 hello}".utf8)
        let content = try XCTUnwrap(
            ClipboardContentClassifier.capturedContent(
                from: ClipboardPasteboardSnapshot(plainText: "hello", rtf: rtf)
            )
        )

        XCTAssertEqual(content.contentType, .richText)
        XCTAssertEqual(content.textPreview, "hello")
        XCTAssertEqual(content.payloads.map(\.format), [.rtf, .plainText])
    }

    func test_classifier_classifiesHTMLAndKeepsPlainTextFallback() throws {
        let html = Data("<p>Hello</p>".utf8)
        let content = try XCTUnwrap(
            ClipboardContentClassifier.capturedContent(
                from: ClipboardPasteboardSnapshot(plainText: "Hello", html: html)
            )
        )

        XCTAssertEqual(content.contentType, .html)
        XCTAssertEqual(content.textPreview, "Hello")
        XCTAssertEqual(content.payloads.map(\.format), [.html, .plainText])
    }

    func test_classifier_classifiesImageBeforeTextFallback() throws {
        let image = Data([0x01, 0x02, 0x03])
        let content = try XCTUnwrap(
            ClipboardContentClassifier.capturedContent(
                from: ClipboardPasteboardSnapshot(plainText: "ignored", image: image)
            )
        )

        XCTAssertEqual(content.contentType, .image)
        XCTAssertNil(content.textPreview)
        XCTAssertEqual(content.payloads, [ClipboardCapturedPayload(format: .image, data: image)])
    }

    func test_classifier_classifiesFileURLsBeforeOtherFormats() throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/report.pdf"),
            URL(fileURLWithPath: "/tmp/image.png")
        ]
        let content = try XCTUnwrap(
            ClipboardContentClassifier.capturedContent(
                from: ClipboardPasteboardSnapshot(plainText: "ignored", html: Data("<p>x</p>".utf8), fileURLs: urls)
            )
        )

        XCTAssertEqual(content.contentType, .fileURL)
        XCTAssertEqual(content.textPreview, "report.pdf, image.png")
        XCTAssertEqual(content.payloads.map(\.format), [.fileURLs, .plainText])

        let paths = try JSONDecoder().decode([String].self, from: try XCTUnwrap(content.payloads.first?.data))
        XCTAssertEqual(paths, ["/tmp/report.pdf", "/tmp/image.png"])
    }

    func test_hasher_isStableAcrossPayloadOrdering() {
        let first = [
            ClipboardCapturedPayload(format: .html, data: Data("<p>Hello</p>".utf8)),
            ClipboardCapturedPayload(format: .plainText, data: Data("Hello".utf8))
        ]
        let second = Array(first.reversed())

        XCTAssertEqual(
            ClipboardContentHasher.hash(payloads: first),
            ClipboardContentHasher.hash(payloads: second)
        )
    }
}
