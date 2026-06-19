import XCTest
@testable import Omnipo

final class LoggingServiceTests: XCTestCase {

    func test_sanitize_redactsClipboardContent() {
        let result = PrivacyRedaction.sanitize(context: [
            "clipboardContent": "secret",
            "stableCode": "I_TEST"
        ])

        XCTAssertEqual(result["clipboardContent"], "<redacted>")
        XCTAssertEqual(result["stableCode"], "I_TEST")
    }

    func test_sanitize_redactsUserPaths() {
        let result = PrivacyRedaction.sanitize(context: [
            "userPath": "/Users/foo/Documents/secret.txt"
        ])

        XCTAssertEqual(result["userPath"], "<redacted>")
    }

    func test_sanitize_redactsPathLikeValuesEvenWithUnknownKey() {
        let result = PrivacyRedaction.sanitize(context: [
            "unrelated": "/Users/somebody/Library/thing"
        ])

        XCTAssertEqual(result["unrelated"], "<redacted-path>")
    }

    func test_sanitize_preservesSafeContext() {
        let result = PrivacyRedaction.sanitize(context: [
            "destination": "cleaner",
            "stage": "scanning"
        ])

        XCTAssertEqual(result["destination"], "cleaner")
        XCTAssertEqual(result["stage"], "scanning")
    }

    func test_sanitize_redactsForbiddenSubstringsInMessage() {
        let result = PrivacyRedaction.sanitize(message: "scanning /Users/foo/Library")

        XCTAssertEqual(result, "<redacted>")
    }

    func test_sanitize_preservesSafeMessage() {
        let result = PrivacyRedaction.sanitize(message: "navigation.selected")

        XCTAssertEqual(result, "navigation.selected")
    }

    func test_logEvent_doesNotExposeForbiddenKeys() {
        let event = LogEvent(
            level: .info,
            category: .navigation,
            message: "test.event",
            sanitizedContext: ["clipboardRaw": "should-not-leak"]
        )

        let cleaned = PrivacyRedaction.sanitize(context: event.sanitizedContext)
        XCTAssertNotEqual(cleaned["clipboardRaw"], "should-not-leak")
    }
}
