import XCTest
@testable import Omnipo

final class AssociatedFileScannerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() async throws {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
    }

    func test_defaultRoots_coverExpectedLibraryCategories() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let roots = AssociatedFileScanner.defaultRoots(forHomeDirectory: home)

        XCTAssertEqual(roots.map(\.category), [
            .cache,
            .applicationSupport,
            .preferences,
            .logs,
            .savedApplicationState,
            .container,
            .groupContainer
        ])
        XCTAssertEqual(roots.first?.url.path, "/Users/example/Library/Caches")
    }

    func test_scan_matchesBundleIdentifierWithHighConfidenceAndDefaultSelection() throws {
        let root = try makeRoot(name: "high")
        let cacheRoot = try makeCategoryRoot(root: root, name: "Caches")
        try writeFile(at: cacheRoot.appendingPathComponent("com.example.sample"), path: "blob", size: 200)
        let scanner = AssociatedFileScanner()

        let result = scanner.scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .cache, url: cacheRoot)]
        )

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.files.count, 1)
        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.category, .cache)
        XCTAssertEqual(file.ownershipConfidence, .high)
        XCTAssertEqual(file.riskLevel, .low)
        XCTAssertTrue(file.isDefaultSelected)
        XCTAssertEqual(file.sizeBytes, 200)
    }

    func test_scan_matchesPreferencesPlistAsHighConfidence() throws {
        let root = try makeRoot(name: "prefs")
        let prefsRoot = try makeCategoryRoot(root: root, name: "Preferences")
        try writeFile(at: prefsRoot, path: "com.example.sample.plist", size: 42)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .preferences, url: prefsRoot)]
        )

        XCTAssertEqual(result.files.first?.ownershipConfidence, .high)
        XCTAssertEqual(result.files.first?.category, .preferences)
        XCTAssertEqual(result.files.first?.isDefaultSelected, true)
    }

    func test_scan_matchesApplicationNameAsMediumConfidenceWithoutDefaultSelection() throws {
        let root = try makeRoot(name: "medium")
        let supportRoot = try makeCategoryRoot(root: root, name: "Application Support")
        try writeFile(at: supportRoot.appendingPathComponent("Sample"), path: "db", size: 80)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .applicationSupport, url: supportRoot)]
        )

        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.ownershipConfidence, .medium)
        XCTAssertEqual(file.riskLevel, .medium)
        XCTAssertFalse(file.isDefaultSelected)
        XCTAssertTrue(file.isUserSelectable)
    }

    func test_scan_marksFuzzyMatchesHighRiskWithoutDefaultSelection() throws {
        let root = try makeRoot(name: "fuzzy")
        let logsRoot = try makeCategoryRoot(root: root, name: "Logs")
        try writeFile(at: logsRoot.appendingPathComponent("Sample Helper Logs"), path: "log.txt", size: 10)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .logs, url: logsRoot)]
        )

        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.ownershipConfidence, .low)
        XCTAssertEqual(file.riskLevel, .high)
        XCTAssertFalse(file.isDefaultSelected)
    }

    func test_scan_groupContainerIsNotDefaultSelected() throws {
        let root = try makeRoot(name: "group")
        let groupRoot = try makeCategoryRoot(root: root, name: "Group Containers")
        try writeFile(at: groupRoot.appendingPathComponent("com.example.sample"), path: "shared", size: 12)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .groupContainer, url: groupRoot)]
        )

        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.ownershipConfidence, .high)
        XCTAssertEqual(file.riskLevel, .high)
        XCTAssertFalse(file.isDefaultSelected)
        XCTAssertTrue(file.isUserSelectable)
    }

    func test_scan_unclearGroupContainerIsUnavailable() throws {
        let root = try makeRoot(name: "unclear-group")
        let groupRoot = try makeCategoryRoot(root: root, name: "Group Containers")
        try writeFile(at: groupRoot.appendingPathComponent("Sample Shared"), path: "shared", size: 12)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .groupContainer, url: groupRoot)]
        )

        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.unavailableReason, .ownershipUnclear)
        XCTAssertFalse(file.isUserSelectable)
        XCTAssertFalse(file.isDefaultSelected)
    }

    func test_scan_highSensitivityCandidateIsUnavailable() throws {
        let root = try makeRoot(name: "sensitive")
        let supportRoot = try makeCategoryRoot(root: root, name: "Application Support")
        try writeFile(at: supportRoot.appendingPathComponent("Sample").appendingPathComponent("Messages"), path: "chat.db", size: 300)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .applicationSupport, url: supportRoot)]
        )

        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.unavailableReason, .highSensitivity)
        XCTAssertEqual(file.riskLevel, .high)
        XCTAssertFalse(file.isUserSelectable)
    }

    func test_scan_missingRootReturnsUnavailableIssueWithoutEmptySuccess() throws {
        let missingRoot = URL(fileURLWithPath: "/this/does/not/exist/\(UUID().uuidString)", isDirectory: true)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [AssociatedFileScanRoot(category: .cache, url: missingRoot)]
        )

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.issues.first?.reason, .resourceUnavailable)
        XCTAssertTrue(result.isUnavailable)
    }

    func test_scan_keepsPartialResultsWhenOneRootUnavailable() throws {
        let root = try makeRoot(name: "partial")
        let cacheRoot = try makeCategoryRoot(root: root, name: "Caches")
        try writeFile(at: cacheRoot.appendingPathComponent("com.example.sample"), path: "blob", size: 10)
        let missingRoot = URL(fileURLWithPath: "/this/does/not/exist/\(UUID().uuidString)", isDirectory: true)

        let result = AssociatedFileScanner().scan(
            for: sampleApplication(),
            roots: [
                AssociatedFileScanRoot(category: .cache, url: cacheRoot),
                AssociatedFileScanRoot(category: .logs, url: missingRoot)
            ]
        )

        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.hasPartialFailures)
    }

    private func makeRoot(name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AssociatedFileScanner-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func makeCategoryRoot(root: URL, name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(at root: URL, path: String, size: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
    }

    private func sampleApplication() -> InstalledApplication {
        InstalledApplication(
            bundleIdentifier: "com.example.sample",
            displayName: "Sample",
            bundleURL: URL(fileURLWithPath: "/Applications/Sample.app", isDirectory: true),
            executableURL: URL(fileURLWithPath: "/Applications/Sample.app/Contents/MacOS/Sample"),
            source: .applications
        )
    }
}
