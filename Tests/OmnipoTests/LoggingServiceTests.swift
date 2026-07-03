import XCTest
@testable import Omnipo

final class LoggingServiceTests: XCTestCase {

    func test_sanitize_redactsClipboardContent() {
        let result = PrivacyRedaction.sanitize(context: [
            "clipboardContent": "secret",
            "code": "I_TEST"
        ])

        XCTAssertEqual(result["clipboardContent"], "<redacted>")
        XCTAssertEqual(result["code"], "I_TEST")
    }

    func test_sanitize_redactsClipboardPreviewAndPathFields() {
        let result = PrivacyRedaction.sanitize(context: [
            "clipboardPreview": "copied text",
            "clipboardFilePath": "/Users/foo/Desktop/private.pdf"
        ])

        XCTAssertEqual(result["clipboardPreview"], "<redacted>")
        XCTAssertEqual(result["clipboardFilePath"], "<redacted>")
    }

    func test_sanitize_redactsUserPathsInAllowedKey() {
        let result = PrivacyRedaction.sanitize(context: [
            "resource": "/Users/foo/Library/thing"
        ])

        XCTAssertEqual(result["resource"], "<redacted-path>")
    }

    func test_sanitize_redactsVolumesPaths() {
        let result = PrivacyRedaction.sanitize(context: [
            "resource": "/Volumes/Backup/secret.pdf"
        ])
        XCTAssertEqual(result["resource"], "<redacted-path>")
    }

    func test_sanitize_redactsTmpPaths() {
        let result = PrivacyRedaction.sanitize(context: [
            "resource": "/tmp/private.txt"
        ])
        XCTAssertEqual(result["resource"], "<redacted-path>")
    }

    func test_sanitize_redactsHomeTildePaths() {
        let result = PrivacyRedaction.sanitize(context: [
            "resource": "~/Documents/secret"
        ])
        XCTAssertEqual(result["resource"], "<redacted-path>")
    }

    func test_sanitize_redactsFilenameLookingValues() {
        let result = PrivacyRedaction.sanitize(context: [
            "resource": "report.pdf"
        ])
        XCTAssertEqual(result["resource"], "<redacted-path>")
    }

    func test_sanitize_redactsUnknownKeyEvenWithSafeValue() {
        let result = PrivacyRedaction.sanitize(context: [
            "unrelated": "anything"
        ])
        XCTAssertEqual(result["unrelated"], "<redacted>")
    }

    func test_sanitize_preservesAllowedKeysWithSafeValues() {
        let result = PrivacyRedaction.sanitize(context: [
            "destination": "cleaner",
            "stage": "scanning",
            "code": "I_NAV"
        ])
        XCTAssertEqual(result["destination"], "cleaner")
        XCTAssertEqual(result["stage"], "scanning")
        XCTAssertEqual(result["code"], "I_NAV")
    }

    func test_sanitize_redactsPathLookingValueInAllowedKey() {
        let result = PrivacyRedaction.sanitize(context: [
            "destination": "/Users/foo/Library"
        ])
        XCTAssertEqual(result["destination"], "<redacted-path>")
    }

    func test_sanitize_redactsForbiddenSubstringsInMessage() {
        let result = PrivacyRedaction.sanitize(message: "scanning /Users/foo/Library")
        XCTAssertEqual(result, "<redacted>")
    }

    func test_sanitize_redactsTmpInMessage() {
        let result = PrivacyRedaction.sanitize(message: "wrote /tmp/foo")
        XCTAssertEqual(result, "<redacted>")
    }

    func test_sanitize_redactsFilenameInMessage() {
        let result = PrivacyRedaction.sanitize(message: "loaded report.pdf")
        XCTAssertEqual(result, "<redacted>")
    }

    func test_sanitize_preservesSafeMessage() {
        let result = PrivacyRedaction.sanitize(message: "navigation.selected")
        XCTAssertEqual(result, "navigation.selected")
    }

    func test_sanitize_redactsAllForbiddenKeysEvenIfAllowed() {
        for key in PrivacyRedaction.forbiddenKeys {
            let result = PrivacyRedaction.sanitize(context: [key: "value"])
            XCTAssertEqual(result[key], "<redacted>", "expected \(key) to be redacted")
        }
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
