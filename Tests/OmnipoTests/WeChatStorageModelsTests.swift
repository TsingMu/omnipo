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
            XCTAssertFalse(reason.explanation.isEmpty)
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
        XCTAssertTrue(result.assets.isEmpty)
        XCTAssertTrue(result.largeFiles.isEmpty)
        XCTAssertTrue(result.conversations.isEmpty)
        XCTAssertEqual(result.unattributedBytes, 0)
        XCTAssertFalse(result.sensitiveNamesIncluded)
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
        let result = WeChatStorageScanResult(totalVisibleBytes: -99, unattributedBytes: -10)
        XCTAssertEqual(result.totalVisibleBytes, 0)
        XCTAssertEqual(result.unattributedBytes, 0)
    }

    func test_assetAndConversationSummariesClampNegativeValues() {
        let asset = WeChatAssetSummary(kind: .video, sizeBytes: -1, fileCount: -2)
        let conversation = WeChatConversationUsage(
            conversationID: "opaque",
            kind: .group,
            displayName: "群聊 1",
            sizeBytes: -3,
            fileCount: -4,
            assets: [],
            topFiles: [],
            confidence: .inferred
        )

        XCTAssertEqual(asset.sizeBytes, 0)
        XCTAssertEqual(asset.fileCount, 0)
        XCTAssertEqual(conversation.sizeBytes, 0)
        XCTAssertEqual(conversation.fileCount, 0)
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
            assets: [.init(kind: .video, sizeBytes: 42, fileCount: 1)],
            largeFiles: [.init(kind: .video, displayName: "视频文件 1", fileName: "real.mp4", sizeBytes: 42)],
            conversations: [.init(
                conversationID: "opaque",
                kind: .group,
                displayName: "群聊 1",
                sizeBytes: 42,
                fileCount: 1,
                assets: [.init(kind: .video, sizeBytes: 42, fileCount: 1)],
                topFiles: [],
                confidence: .high
            )],
            sensitiveNamesIncluded: true,
            topGroups: [.init(category: .cache, displayName: "g", sizeBytes: 42, fileCount: 1)],
            roots: [root],
            issues: [.init(rootKind: .applicationContainer, reason: .rootMissing)],
            completedAt: Date(timeIntervalSince1970: 1000)
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(WeChatStorageScanResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }

    func test_largeFile_codableOmitsTransientFileURL() throws {
        let sensitiveURL = URL(fileURLWithPath: "/Users/private-account/secret-video.mp4")
        let file = WeChatLargeFile(
            kind: .video,
            displayName: "视频文件 1",
            fileName: "secret-video.mp4",
            fileURL: sensitiveURL,
            sizeBytes: 42
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(WeChatLargeFile.self, from: data)

        XCTAssertNil(decoded.fileURL)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(sensitiveURL.path))
        XCTAssertEqual(decoded.fileName, file.fileName)
        XCTAssertEqual(decoded.sizeBytes, file.sizeBytes)
    }
}
