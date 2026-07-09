import XCTest
@testable import Omnipo

final class InstalledApplicationScannerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() async throws {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
    }

    func test_scan_discoversAppBundleMetadataAndSize() async throws {
        let root = try makeRoot(name: "metadata")
        let appURL = try makeAppBundle(
            at: root,
            name: "Sample",
            bundleIdentifier: "com.example.sample",
            bundleName: "Sample App",
            executableName: "SampleExec",
            executableSize: 128
        )
        let scanner = InstalledApplicationScanner(runningApplicationProvider: { [] })

        let result = await scanner.scan(roots: [root])

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.applications.count, 1)
        let app = try XCTUnwrap(result.applications.first)
        XCTAssertEqual(app.bundleIdentifier, "com.example.sample")
        XCTAssertEqual(app.displayName, "Sample App")
        XCTAssertEqual(app.localizedDisplayName, "Sample App")
        XCTAssertEqual(app.bundleURL.standardizedFileURL, appURL.standardizedFileURL)
        XCTAssertEqual(app.executableURL?.lastPathComponent, "SampleExec")
        XCTAssertEqual(app.iconIdentifier, "com.example.sample")
        XCTAssertGreaterThanOrEqual(app.bundleSizeBytes, 128)
        XCTAssertEqual(app.source, .other)
        XCTAssertFalse(app.isSystemProtected)
        XCTAssertFalse(app.isRunning)
    }

    func test_scan_prefersChineseLocalizedDisplayName() async throws {
        let root = try makeRoot(name: "localized")
        _ = try makeAppBundle(
            at: root,
            name: "WeChat",
            bundleIdentifier: "com.example.wechat",
            bundleName: "WeChat",
            executableName: "WeChat",
            localizedNames: ["zh-Hans": "微信"]
        )
        let scanner = InstalledApplicationScanner(runningApplicationProvider: { [] })

        let result = await scanner.scan(roots: [root])

        XCTAssertEqual(result.applications.first?.displayName, "微信")
        XCTAssertEqual(result.applications.first?.localizedDisplayName, "微信")
    }

    func test_scan_marksRunningApplications() async throws {
        let root = try makeRoot(name: "running")
        _ = try makeAppBundle(
            at: root,
            name: "Running",
            bundleIdentifier: "com.example.running",
            bundleName: "Running",
            executableName: "Running"
        )
        let scanner = InstalledApplicationScanner(
            runningApplicationProvider: { ["com.example.running"] }
        )

        let result = await scanner.scan(roots: [root])

        XCTAssertEqual(result.applications.first?.isRunning, true)
    }

    func test_scan_marksSystemProtectedApplications() async throws {
        let root = try makeRoot(name: "protected")
        let protectedURL = try makeAppBundle(
            at: root,
            name: "Protected",
            bundleIdentifier: "com.example.protected",
            bundleName: "Protected",
            executableName: "Protected"
        )
        let scanner = InstalledApplicationScanner(
            runningApplicationProvider: { [] },
            systemProtectionEvaluator: { $0.lastPathComponent == protectedURL.lastPathComponent }
        )

        let result = await scanner.scan(roots: [root])

        XCTAssertEqual(result.applications.first?.isSystemProtected, true)
    }

    func test_scan_skipsNonAppBundlesAndInvalidBundles() async throws {
        let root = try makeRoot(name: "skip")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Notes.txt"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Broken.app"),
            withIntermediateDirectories: true
        )
        _ = try makeAppBundle(
            at: root,
            name: "Valid",
            bundleIdentifier: "com.example.valid",
            bundleName: "Valid",
            executableName: "Valid"
        )
        let scanner = InstalledApplicationScanner(runningApplicationProvider: { [] })

        let result = await scanner.scan(roots: [root])

        XCTAssertEqual(result.applications.map(\.bundleIdentifier), ["com.example.valid"])
    }

    func test_scan_deduplicatesByBundleIdentifier() async throws {
        let root = try makeRoot(name: "dedupe")
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let first = try makeAppBundle(
            at: root,
            name: "Duplicate",
            bundleIdentifier: "com.example.duplicate",
            bundleName: "Duplicate",
            executableName: "Duplicate"
        )
        _ = try makeAppBundle(
            at: nested,
            name: "Duplicate Copy",
            bundleIdentifier: "com.example.duplicate",
            bundleName: "Duplicate Copy",
            executableName: "DuplicateCopy"
        )
        let scanner = InstalledApplicationScanner(runningApplicationProvider: { [] })

        let result = await scanner.scan(roots: [root])

        XCTAssertEqual(result.applications.count, 1)
        XCTAssertEqual(
            result.applications.first?.bundleURL.standardizedFileURL.path,
            first.standardizedFileURL.path
        )
    }

    func test_scan_keepsPartialResultsWhenRootUnavailable() async throws {
        let root = try makeRoot(name: "partial")
        _ = try makeAppBundle(
            at: root,
            name: "Valid",
            bundleIdentifier: "com.example.valid",
            bundleName: "Valid",
            executableName: "Valid"
        )
        let missingRoot = URL(fileURLWithPath: "/this/path/does/not/exist/\(UUID().uuidString)")
        let scanner = InstalledApplicationScanner(runningApplicationProvider: { [] })

        let result = await scanner.scan(roots: [missingRoot, root])

        XCTAssertEqual(result.applications.count, 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.hasPartialFailures)
        XCTAssertFalse(result.isUnavailable)
        XCTAssertEqual(result.issues.first?.reason, .resourceUnavailable)
    }

    func test_scan_allRootsUnavailableReportsUnavailable() async {
        let missingRoot = URL(fileURLWithPath: "/this/path/does/not/exist/\(UUID().uuidString)")
        let scanner = InstalledApplicationScanner(runningApplicationProvider: { [] })

        let result = await scanner.scan(roots: [missingRoot])

        XCTAssertTrue(result.applications.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertFalse(result.hasPartialFailures)
        XCTAssertTrue(result.isUnavailable)
    }

    func test_defaultSearchRoots_includeExpectedApplicationLocations() {
        let paths = InstalledApplicationScanner.defaultSearchRoots.map(\.path)

        XCTAssertEqual(paths.prefix(3), [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices"
        ])
        XCTAssertTrue(paths.last?.hasSuffix("/Applications") == true)
    }

    private func makeRoot(name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("InstalledApplicationScanner-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    @discardableResult
    private func makeAppBundle(
        at root: URL,
        name: String,
        bundleIdentifier: String,
        bundleName: String,
        executableName: String,
        executableSize: Int = 64,
        localizedNames: [String: String] = [:]
    ) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": bundleName,
            "CFBundleDisplayName": bundleName,
            "CFBundleExecutable": executableName,
            "CFBundlePackageType": "APPL"
        ]
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: infoURL)

        let executableURL = macOSURL.appendingPathComponent(executableName)
        try Data(count: executableSize).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        for (localization, localizedName) in localizedNames {
            let lprojURL = resourcesURL.appendingPathComponent("\(localization).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: lprojURL, withIntermediateDirectories: true)
            let stringsURL = lprojURL.appendingPathComponent("InfoPlist.strings")
            try "CFBundleDisplayName = \"\(localizedName)\";\n".write(
                to: stringsURL,
                atomically: true,
                encoding: .utf8
            )
        }

        return appURL
    }
}
