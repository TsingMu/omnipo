import XCTest
@testable import Omnipo

final class PermissionAuditModelsTests: XCTestCase {

    func test_permissionCategories_coverExpectedOrderAndPresentation() {
        XCTAssertEqual(
            PermissionCategory.allCases,
            [.camera, .microphone, .photos, .contacts, .calendar, .reminders, .accessibility, .fullDiskAccess]
        )

        for (expectedOrder, category) in PermissionCategory.allCases.enumerated() {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.symbolName.isEmpty)
            XCTAssertEqual(category.sortOrder, expectedOrder)
        }
    }

    func test_permissionUnavailableReasons_haveUniqueStableCodes() {
        let codes = Set(PermissionUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, PermissionUnavailableReason.allCases.count)
    }

    func test_permissionUnavailableReasons_haveNonEmptyDescriptions() {
        for reason in PermissionUnavailableReason.allCases {
            XCTAssertFalse(reason.userDescription.isEmpty)
        }
    }

    func test_permissionGrantStatus_unavailableAccessors() {
        let unavailable: PermissionGrantStatus = .unavailable(reason: .permissionLimited)
        XCTAssertTrue(unavailable.isUnavailable)
        XCTAssertEqual(unavailable.unavailableReason, .permissionLimited)
        XCTAssertEqual(unavailable.displayName, "不可读取")

        XCTAssertFalse(PermissionGrantStatus.authorized.isUnavailable)
        XCTAssertNil(PermissionGrantStatus.denied.unavailableReason)
    }

    func test_appPermissionGrant_normalizesIdentifiersAndDisplayName() {
        let grant = AppPermissionGrant(
            bundleIdentifier: "  ",
            displayName: " ",
            category: .camera,
            status: .authorized,
            source: " "
        )

        XCTAssertEqual(grant.bundleIdentifier, "unknown.bundle")
        XCTAssertEqual(grant.displayName, "unknown.bundle")
        XCTAssertEqual(grant.source, "unknown")
        XCTAssertEqual(grant.id, "camera::unknown.bundle")
    }

    func test_appPermissionGrant_usesExplicitIDWhenProvided() {
        let grant = AppPermissionGrant(
            id: "grant-1",
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            category: .microphone,
            status: .denied,
            source: "tcc"
        )

        XCTAssertEqual(grant.id, "grant-1")
    }

    func test_permissionAuditSummary_clampsCounts() {
        let summary = PermissionAuditSummary(
            totalGrantCount: -2,
            authorizedGrantCount: 8,
            unavailableGrantCount: 3
        )

        XCTAssertEqual(summary.totalGrantCount, 0)
        XCTAssertEqual(summary.authorizedGrantCount, 0)
        XCTAssertEqual(summary.unavailableGrantCount, 0)
    }

    func test_permissionAuditResult_sortsGrantsAndBuildsSummary() {
        let grants = [
            AppPermissionGrant(
                bundleIdentifier: "com.apple.Terminal",
                displayName: "Terminal",
                category: .microphone,
                status: .unavailable(reason: .permissionLimited),
                source: "tcc"
            ),
            AppPermissionGrant(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                category: .camera,
                status: .authorized,
                source: "tcc"
            ),
            AppPermissionGrant(
                bundleIdentifier: "com.apple.Notes",
                displayName: "Notes",
                category: .camera,
                status: .denied,
                source: "tcc"
            )
        ]

        let result = PermissionAuditResult(
            grants: grants,
            unavailableCategories: [.fullDiskAccess: .unsupportedOnCurrentSystem]
        )

        XCTAssertEqual(result.grants.map(\.displayName), ["Notes", "Safari", "Terminal"])
        XCTAssertEqual(result.summary.totalGrantCount, 3)
        XCTAssertEqual(result.summary.authorizedGrantCount, 1)
        XCTAssertEqual(result.summary.unavailableGrantCount, 1)
        XCTAssertFalse(result.isEmpty)
    }

    func test_permissionAuditResult_emptyStateIncludesUnavailableCategories() {
        let result = PermissionAuditResult(
            grants: [],
            unavailableCategories: [.accessibility: .databaseUnreadable]
        )

        XCTAssertFalse(result.isEmpty)
    }

    func test_permissionAuditTypes_roundTripCodable() throws {
        let result = PermissionAuditResult(
            grants: [
                AppPermissionGrant(
                    bundleIdentifier: "com.apple.Safari",
                    displayName: "Safari",
                    category: .camera,
                    status: .authorized,
                    source: "tcc",
                    lastUpdatedAt: Date(timeIntervalSince1970: 1_783_353_600)
                )
            ],
            unavailableCategories: [.microphone: .databaseUnreadable]
        )

        let data = try JSONEncoder().encode(result)
        let restored = try JSONDecoder().decode(PermissionAuditResult.self, from: data)

        XCTAssertEqual(restored, result)
    }

    func test_permissionAuditQuery_defaultsToUnfilteredState() {
        let query = PermissionAuditQuery()

        XCTAssertEqual(query.searchText, "")
        XCTAssertNil(query.category)
    }
}
