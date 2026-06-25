import XCTest
@testable import Omnipo

final class LargeFileScannerTests: XCTestCase {

    private var tempRoots: [URL] = []

    override func tearDown() async throws {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
    }

    private func makeRoot(name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LargeFileScanner-\(UUID().uuidString)-\(name)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func writeFile(at root: URL, path: String, size: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(count: size)
        try data.write(to: url, options: .atomic)
    }

    func test_scan_sortsBySizeDescending() throws {
        let root = try makeRoot(name: "sort")
        try writeFile(at: root, path: "small.txt", size: 100)
        try writeFile(at: root, path: "big.bin", size: 5_000)
        try writeFile(at: root, path: "medium.mov", size: 1_000)

        let result = LargeFileScanner.scan(
            roots: [root],
            limit: 10,
            volumeIdentifier: "vol"
        )

        guard case .available(let records) = result else {
            XCTFail("expected available")
            return
        }
        XCTAssertEqual(records.map(\.name), ["big.bin", "medium.mov", "small.txt"])
    }

    func test_scan_appliesLimit() throws {
        let root = try makeRoot(name: "limit")
        for index in 0..<10 {
            try writeFile(at: root, path: "f\(index)", size: (index + 1) * 100)
        }

        let result = LargeFileScanner.scan(
            roots: [root],
            limit: 3,
            volumeIdentifier: "vol"
        )

        guard case .available(let records) = result else {
            XCTFail("expected available")
            return
        }
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.first?.sizeBytes, 1_000)
    }

    func test_scan_zeroOrNegativeLimit_returnsScanNotStarted() throws {
        let root = try makeRoot(name: "zero")
        try writeFile(at: root, path: "a", size: 100)

        XCTAssertEqual(
            LargeFileScanner.scan(roots: [root], limit: 0, volumeIdentifier: "v"),
            .unavailable(reason: .scanNotStarted)
        )
        XCTAssertEqual(
            LargeFileScanner.scan(roots: [root], limit: -1, volumeIdentifier: "v"),
            .unavailable(reason: .scanNotStarted)
        )
    }

    func test_scan_emptyRoots_returnsScanNotStarted() {
        let result = LargeFileScanner.scan(roots: [], limit: 10, volumeIdentifier: "v")
        XCTAssertEqual(result, .unavailable(reason: .scanNotStarted))
    }

    func test_scan_skipsDirectoriesAndOnlyReturnsRegularFiles() throws {
        let root = try makeRoot(name: "files-only")
        try writeFile(at: root, path: "file.txt", size: 200)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("subdir"),
            withIntermediateDirectories: true
        )

        let result = LargeFileScanner.scan(
            roots: [root],
            limit: 10,
            volumeIdentifier: "v"
        )

        guard case .available(let records) = result else {
            XCTFail("expected available")
            return
        }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "file.txt")
    }

    func test_scan_aggregatesAcrossRootsAndDeduplicates() throws {
        let rootA = try makeRoot(name: "a")
        let rootB = try makeRoot(name: "b")
        try writeFile(at: rootA, path: "shared", size: 500)
        try writeFile(at: rootB, path: "shared", size: 500)  // 不同根但同名,不同路径
        try writeFile(at: rootB, path: "unique", size: 1_000)

        let result = LargeFileScanner.scan(
            roots: [rootA, rootB],
            limit: 10,
            volumeIdentifier: "v"
        )

        guard case .available(let records) = result else {
            XCTFail("expected available")
            return
        }
        // rootA/shared 与 rootB/shared 路径不同,因此各算一条
        XCTAssertEqual(records.count, 3)
    }

    func test_scan_skipsUnreadableRootAndContinues() throws {
        let validRoot = try makeRoot(name: "valid")
        try writeFile(at: validRoot, path: "ok.txt", size: 200)
        let bogusRoot = URL(fileURLWithPath: "/this/definitely/does/not/exist/\(UUID().uuidString)")

        let result = LargeFileScanner.scan(
            roots: [bogusRoot, validRoot],
            limit: 10,
            volumeIdentifier: "v"
        )

        guard case .available(let records) = result else {
            XCTFail("expected available despite one bogus root")
            return
        }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "ok.txt")
    }

    func test_scan_allRootsUnreadable_returnsPermissionLimited() {
        let bogusRootA = URL(fileURLWithPath: "/this/does/not/exist/a/\(UUID().uuidString)")
        let bogusRootB = URL(fileURLWithPath: "/this/does/not/exist/b/\(UUID().uuidString)")

        let result = LargeFileScanner.scan(
            roots: [bogusRootA, bogusRootB],
            limit: 10,
            volumeIdentifier: "v"
        )
        XCTAssertEqual(result, .unavailable(reason: .permissionLimited))
    }

    func test_scan_attachesVolumeIdentifierAndLastModified() throws {
        let root = try makeRoot(name: "meta")
        try writeFile(at: root, path: "file.bin", size: 800)

        let result = LargeFileScanner.scan(
            roots: [root],
            limit: 5,
            volumeIdentifier: "vol-42"
        )

        guard case .available(let records) = result, let first = records.first else {
            XCTFail("expected available")
            return
        }
        XCTAssertEqual(first.sourceVolumeIdentifier, "vol-42")
        XCTAssertNotNil(first.lastModifiedAt)
    }

    func test_defaultRoots_includesHomeAndSixSubdirs() {
        let home = URL(fileURLWithPath: "/Users/example")
        let roots = LargeFileScanner.defaultRoots(forHomeDirectory: home)
        let paths = roots.map { $0.path }

        XCTAssertEqual(paths, [
            "/Users/example",
            "/Users/example/Downloads",
            "/Users/example/Documents",
            "/Users/example/Desktop",
            "/Users/example/Movies",
            "/Users/example/Pictures",
            "/Users/example/Music"
        ])
    }
}
