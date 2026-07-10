import XCTest
@testable import Omnipo

final class WeChatStorageModelsTests: XCTestCase {

    // MARK: - Category

    func test_category_everyCaseHasDisplayNameAndPrivacyNote() {
        for category in WeChatStorageCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "displayName missing for \(category)")
            XCTAssertFalse(category.privacyNote.isEmpty, "privacyNote missing for \(category)")
        }
    }

    func test_category_caseIterableOrderIsStable() {
        XCTAssertEqual(WeChatStorageCategory.allCases, [
            .cache, .mediaAndFiles, .logs, .databasesAndState, .backups, .configuration, .other
        ])
    }

    func test_category_privacyNoteEmphasizesNoContentRead() {
        for category in WeChatStorageCategory.allCases {
            let note = category.privacyNote
            XCTAssertTrue(
                note.contains("不") || note.contains("仅"),
                "privacy note should emphasize no-read for \(category)"
            )
        }
    }

    func test_category_rawValuesAreStable() {
        XCTAssertEqual(WeChatStorageCategory.cache.rawValue, "cache")
        XCTAssertEqual(WeChatStorageCategory.databasesAndState.rawValue, "databasesAndState")
        XCTAssertEqual(WeChatStorageCategory.mediaAndFiles.rawValue, "mediaAndFiles")
    }

    // MARK: - Availability

    func test_availabilityReason_everyCaseHasStableCodeAndDisplayName() {
        for reason in WeChatStorageAvailabilityReason.allCases {
            XCTAssertEqual(reason.stableCode, reason.rawValue)
            XCTAssertFalse(reason.displayName.isEmpty)
        }
    }

    func test_availability_unavailableCarriesReason() {
        let avail = WeChatStorageAvailability.unavailable(.permissionLimited)
        guard case .unavailable(let reason) = avail else {
            return XCTFail("expected unavailable")
        }
        XCTAssertEqual(reason, .permissionLimited)
    }

    // MARK: - Summaries & clamping

    func test_categorySummary_clampsNegativeValues() {
        let summary = WeChatStorageCategorySummary(category: .cache, sizeBytes: -10, fileCount: -2)
        XCTAssertEqual(summary.sizeBytes, 0)
        XCTAssertEqual(summary.fileCount, 0)
    }

    func test_group_clampsNegativeSizeAndCount() {
        let group = WeChatStorageGroup(category: .mediaAndFiles, displayName: "g", sizeBytes: -5, fileCount: -1)
        XCTAssertEqual(group.sizeBytes, 0)
        XCTAssertEqual(group.fileCount, 0)
    }

    func test_scanResult_defaultsAreEmpty() {
        let result = WeChatStorageScanResult()
        XCTAssertEqual(result.totalVisibleBytes, 0)
        XCTAssertEqual(result.summedCategoryBytes, 0)
        XCTAssertTrue(result.categories.isEmpty)
        XCTAssertTrue(result.topGroups.isEmpty)
        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func test_scanResult_summedCategoryBytesAggregates() {
        let result = WeChatStorageScanResult(categories: [
            .init(category: .cache, sizeBytes: 100, fileCount: 2),
            .init(category: .logs, sizeBytes: 50, fileCount: 1)
        ])
        XCTAssertEqual(result.summedCategoryBytes, 150)
    }

    func test_scanResult_clampsNegativeTotal() {
        let result = WeChatStorageScanResult(totalVisibleBytes: -99)
        XCTAssertEqual(result.totalVisibleBytes, 0)
    }

    // MARK: - Issue privacy

    func test_issue_carriesOnlySanitizedFields() {
        let issue = WeChatStorageIssue(
            rootKind: .groupContainer,
            reason: .tccOrSandboxLimited,
            sanitizedDisplayName: "共享容器组 1"
        )
        XCTAssertEqual(issue.reason, .tccOrSandboxLimited)
        XCTAssertEqual(issue.rootKind, .groupContainer)
        XCTAssertEqual(issue.sanitizedDisplayName, "共享容器组 1")
        XCTAssertNil(issue.rootID)
    }

    // MARK: - Codable round-trip

    func test_models_roundTripCodable() throws {
        let root = WeChatStorageRoot(
            url: URL(fileURLWithPath: "/tmp/x"),
            kind: .applicationContainer,
            displayName: "r",
            availability: .unavailable(.permissionLimited)
        )
        let result = WeChatStorageScanResult(
            totalVisibleBytes: 42,
            categories: [.init(category: .cache, sizeBytes: 42, fileCount: 1)],
            topGroups: [.init(category: .cache, displayName: "g", sizeBytes: 42, fileCount: 1)],
            roots: [root],
            issues: [.init(rootKind: .applicationContainer, reason: .rootMissing)],
            completedAt: Date(timeIntervalSince1970: 1000)
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(WeChatStorageScanResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }
}
