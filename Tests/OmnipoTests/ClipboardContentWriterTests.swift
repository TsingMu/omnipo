import AppKit
import XCTest
@testable import Omnipo

final class ClipboardContentWriterTests: XCTestCase {

    func test_systemWriter_writesPlainTextToPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("omnipo-test-\(UUID().uuidString)"))
        let writer = SystemClipboardContentWriter(pasteboard: pasteboard)

        try writer.write([
            ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))
        ], as: .plainText)

        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
    }

    func test_systemWriter_writesHTMLWithPlainTextFallback() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("omnipo-test-\(UUID().uuidString)"))
        let writer = SystemClipboardContentWriter(pasteboard: pasteboard)
        let html = Data("<p>Hello</p>".utf8)

        try writer.write([
            ClipboardCapturedPayload(format: .html, data: html),
            ClipboardCapturedPayload(format: .plainText, data: Data("Hello".utf8))
        ], as: .html)

        XCTAssertEqual(pasteboard.data(forType: .html), html)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")
    }

    func test_systemWriter_writesRTFWithPlainTextFallback() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("omnipo-test-\(UUID().uuidString)"))
        let writer = SystemClipboardContentWriter(pasteboard: pasteboard)
        let rtf = Data("{\\rtf1 Hello}".utf8)

        try writer.write([
            ClipboardCapturedPayload(format: .rtf, data: rtf),
            ClipboardCapturedPayload(format: .plainText, data: Data("Hello".utf8))
        ], as: .richText)

        XCTAssertEqual(pasteboard.data(forType: .rtf), rtf)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")
    }

    func test_systemWriter_throwsWhenRequiredPayloadIsMissing() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("omnipo-test-\(UUID().uuidString)"))
        let writer = SystemClipboardContentWriter(pasteboard: pasteboard)

        XCTAssertThrowsError(try writer.write([], as: .plainText)) { error in
            XCTAssertEqual(error as? AppError, .dataCorrupted(detail: "clipboard-plain-text-missing"))
        }
    }
}
