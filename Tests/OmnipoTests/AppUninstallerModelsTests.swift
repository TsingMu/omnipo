import XCTest
@testable import Omnipo

final class AppUninstallerModelsTests: XCTestCase {

    func test_associatedFileCategories_haveStableOrderAndDeletionConsequences() {
        XCTAssertEqual(AssociatedFileCategory.applicationBundle.sortOrder, 0)
        XCTAssertLessThan(AssociatedFileCategory.cache.sortOrder, AssociatedFileCategory.applicationSupport.sortOrder)

        for category in AssociatedFileCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.deletionConsequence.isEmpty)
        }

        XCTAssertTrue(AssociatedFileCategory.groupContainer.deletionConsequence.contains("默认不选中"))
        XCTAssertTrue(AssociatedFileCategory.applicationBundle.deletionConsequence.contains("重新安装"))
    }

    func test_unavailableReasons_haveUniqueStableCodesAndDescriptions() {
        let codes = Set(AssociatedFileUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, AssociatedFileUnavailableReason.allCases.count)

        for reason in AssociatedFileUnavailableReason.allCases {
            XCTAssertFalse(reason.userDescription.isEmpty)
        }
    }

    func test_installedApplication_normalizesFieldsAndClampsSize() {
        let url = URL(fileURLWithPath: "/Applications/Sample.app")
        let app = InstalledApplication(
            bundleIdentifier: "  ",
            displayName: " ",
            localizedDisplayName: " 样例 ",
            bundleURL: url,
            bundleSizeBytes: -10,
            source: .applications
        )

        XCTAssertNil(app.bundleIdentifier)
        XCTAssertEqual(app.displayName, "样例")
        XCTAssertEqual(app.localizedDisplayName, "样例")
        XCTAssertEqual(app.bundleSizeBytes, 0)
        XCTAssertEqual(app.id, url.path)
    }

    func test_defaultSelection_isConservative() {
        XCTAssertTrue(AppAssociatedFile.defaultSelection(
            category: .applicationBundle,
            ownershipConfidence: .low,
            riskLevel: .high,
            isUserSelectable: true
        ))
        XCTAssertTrue(AppAssociatedFile.defaultSelection(
            category: .cache,
            ownershipConfidence: .high,
            riskLevel: .low,
            isUserSelectable: true
        ))
        XCTAssertFalse(AppAssociatedFile.defaultSelection(
            category: .applicationSupport,
            ownershipConfidence: .medium,
            riskLevel: .low,
            isUserSelectable: true
        ))
        XCTAssertFalse(AppAssociatedFile.defaultSelection(
            category: .groupContainer,
            ownershipConfidence: .high,
            riskLevel: .low,
            isUserSelectable: true
        ))
        XCTAssertFalse(AppAssociatedFile.defaultSelection(
            category: .cache,
            ownershipConfidence: .high,
            riskLevel: .low,
            isUserSelectable: false
        ))
    }

    func test_appAssociatedFile_appliesDefaultSelectionAndUnavailableState() {
        let file = AppAssociatedFile(
            category: .cache,
            displayName: "",
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.app"),
            sizeBytes: -1,
            ownershipConfidence: .high,
            riskLevel: .low
        )

        XCTAssertEqual(file.displayName, "com.example.app")
        XCTAssertEqual(file.sizeBytes, 0)
        XCTAssertTrue(file.isDefaultSelected)
        XCTAssertTrue(file.isUserSelectable)

        let unavailable = AppAssociatedFile(
            category: .preferences,
            displayName: "prefs",
            url: URL(fileURLWithPath: "/Users/me/Library/Preferences/com.example.app.plist"),
            ownershipConfidence: .high,
            riskLevel: .low,
            unavailableReason: .permissionLimited
        )

        XCTAssertFalse(unavailable.isUserSelectable)
        XCTAssertFalse(unavailable.isDefaultSelected)
    }

    func test_uninstallPlan_sortsItemsAndComputesSelectedSummary() {
        let app = sampleApplication()
        let bundle = AppAssociatedFile(
            id: "bundle",
            category: .applicationBundle,
            displayName: "Sample",
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            sizeBytes: 100,
            ownershipConfidence: .high,
            riskLevel: .low
        )
        let support = AppAssociatedFile(
            id: "support",
            category: .applicationSupport,
            displayName: "Sample Support",
            url: URL(fileURLWithPath: "/Users/me/Library/Application Support/Sample"),
            sizeBytes: 40,
            ownershipConfidence: .medium,
            riskLevel: .medium
        )
        let cache = AppAssociatedFile(
            id: "cache",
            category: .cache,
            displayName: "Sample Cache",
            url: URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.sample"),
            sizeBytes: 10,
            ownershipConfidence: .high,
            riskLevel: .low
        )

        let plan = AppUninstallPlan(
            application: app,
            mode: .removeApplicationAndAssociatedFiles,
            items: [support, cache, bundle]
        )

        XCTAssertEqual(plan.items.map(\.id), ["bundle", "cache", "support"])
        XCTAssertEqual(plan.selectedItemIDs, ["bundle", "cache"])
        XCTAssertEqual(plan.selectedTotalSizeBytes, 110)
        XCTAssertEqual(plan.riskSummary.lowRiskCount, 2)
        XCTAssertEqual(plan.riskSummary.mediumRiskCount, 0)
        XCTAssertEqual(plan.groupedItems[.cache], [cache])

        let changed = plan.selecting(itemIDs: ["support"])
        XCTAssertEqual(changed.selectedItemIDs, ["support"])
        XCTAssertEqual(changed.selectedTotalSizeBytes, 40)
        XCTAssertEqual(changed.riskSummary.mediumRiskCount, 1)
    }

    func test_executionResult_countsPartialFailure() {
        let item = AppAssociatedFile(
            id: "bundle",
            category: .applicationBundle,
            displayName: "Sample",
            url: URL(fileURLWithPath: "/Applications/Sample.app"),
            ownershipConfidence: .high,
            riskLevel: .low
        )
        let result = UninstallExecutionResult(
            planID: UUID(),
            itemResults: [
                UninstallExecutionItemResult(item: item, status: .succeeded),
                UninstallExecutionItemResult(item: item, status: .insufficientPermission, reasonCode: "E_PERMISSION"),
                UninstallExecutionItemResult(item: item, status: .skipped)
            ],
            completedAt: Date(timeIntervalSince1970: 1_783_353_600)
        )

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(result.isPartialFailure)
    }

    func test_uninstallerTypes_roundTripCodable() throws {
        let plan = AppUninstallPlan(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            application: sampleApplication(),
            mode: .removeApplicationOnly,
            items: [
                AppAssociatedFile(
                    id: "bundle",
                    category: .applicationBundle,
                    displayName: "Sample",
                    url: URL(fileURLWithPath: "/Applications/Sample.app"),
                    sizeBytes: 1,
                    ownershipConfidence: .high,
                    riskLevel: .low
                )
            ]
        )

        let data = try JSONEncoder().encode(plan)
        let restored = try JSONDecoder().decode(AppUninstallPlan.self, from: data)

        XCTAssertEqual(restored, plan)
    }

    func test_uninstallerQuery_defaultsToVisibleApps() {
        let query = UninstallerQuery()

        XCTAssertEqual(query.searchText, "")
        XCTAssertTrue(query.includeSystemApplications)
    }

    private func sampleApplication() -> InstalledApplication {
        InstalledApplication(
            bundleIdentifier: "com.example.sample",
            displayName: "Sample",
            bundleURL: URL(fileURLWithPath: "/Applications/Sample.app"),
            bundleSizeBytes: 100,
            source: .applications
        )
    }
}
