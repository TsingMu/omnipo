import XCTest
@testable import Omnipo

final class WeChatStorageScannerTests: XCTestCase {

    func test_scan_aggregatesByCategoryAndComputesTotal() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeFile(root.appendingPathComponent("Caches/scratch.dat"), bytes: 100)
        try writeFile(root.appendingPathComponent("Logs/run.log"), bytes: 40)
        try writeFile(root.appendingPathComponent("DB/store.sqlite"), bytes: 200)

        let result = WeChatStorageScanner().scan(roots: [readableRoot(url: root)])

        XCTAssertEqual(result.totalVisibleBytes, 340)
        XCTAssertEqual(categoryBytes(result, .cache), 100)
        XCTAssertEqual(categoryBytes(result, .logs), 40)
        XCTAssertEqual(categoryBytes(result, .databasesAndState), 200)
    }

    func test_scan_topGroupsSortedBySizeAndCapped() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Caches/big.dat"), bytes: 500)
        try writeFile(root.appendingPathComponent("Logs/small.log"), bytes: 10)

        let result = WeChatStorageScanner(topGroupCap: 10).scan(roots: [readableRoot(url: root)])

        XCTAssertEqual(result.topGroups.first?.sizeBytes, 500)
        XCTAssertLessThanOrEqual(result.topGroups.count, 10)
    }

    func test_scan_capsTopGroupsToLimit() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<5 {
            try writeFile(root.appendingPathComponent("Cache\(index)/data.dat"), bytes: (index + 1) * 10)
        }

        let result = WeChatStorageScanner(topGroupCap: 2).scan(roots: [readableRoot(url: root)])

        XCTAssertEqual(result.topGroups.count, 2)
    }

    func test_scan_unavailableRootProducesIssueWithoutCountingBytes() {
        let unavailable = WeChatStorageRoot(
            url: URL(fileURLWithPath: "/nonexistent/wechat"),
            kind: .applicationContainer,
            displayName: "应用容器",
            availability: .unavailable(.tccOrSandboxLimited)
        )

        let result = WeChatStorageScanner().scan(roots: [unavailable])

        XCTAssertTrue(result.issues.contains { $0.reason == .tccOrSandboxLimited })
        XCTAssertEqual(result.totalVisibleBytes, 0)
    }

    func test_scan_deduplicatesSymlinkWithinRoots() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let realDir = root.appendingPathComponent("Caches/Real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try writeFile(realDir.appendingPathComponent("a.dat"), bytes: 80)
        let link = root.appendingPathComponent("Caches/LinkToReal")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: realDir.path)

        let result = WeChatStorageScanner().scan(roots: [readableRoot(url: root)])

        // Real 与 LinkToReal 解析后同一真实路径,去重一次,cache 仅计 80。
        XCTAssertEqual(categoryBytes(result, .cache), 80)
    }

    func test_scan_rejectsOutOfScopeSymlinkAsIssue() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: outside) }
        try writeFile(outside.appendingPathComponent("foreign.dat"), bytes: 999)
        let link = root.appendingPathComponent("LinkOutside")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: outside.path)

        let result = WeChatStorageScanner().scan(roots: [readableRoot(url: root)])

        XCTAssertEqual(result.totalVisibleBytes, 0)
        XCTAssertTrue(result.issues.contains { $0.reason == .permissionLimited })
    }

    func test_scan_supportsCancellation() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Caches/a.dat"), bytes: 10)

        let result = WeChatStorageScanner().scan(roots: [readableRoot(url: root)], isCancelled: { true })

        XCTAssertTrue(result.issues.contains { $0.reason == .scanCancelled })
    }

    func test_scan_doesNotDoubleCountNestedOverlappingRoot() throws {
        let parent = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let nested = parent.appendingPathComponent("Caches/Sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(nested.appendingPathComponent("x.dat"), bytes: 50)

        let roots = [
            WeChatStorageRoot(url: parent, kind: .applicationContainer, displayName: "应用容器", availability: .readable),
            WeChatStorageRoot(url: nested, kind: .userSelected, displayName: "自选目录", availability: .readable)
        ]

        let result = WeChatStorageScanner().scan(roots: roots)

        // nested 被 parent 包含 → 跳过;totalVisibleBytes 只计一次 50,不重复。
        XCTAssertEqual(result.totalVisibleBytes, 50)
    }

    func test_scan_nestedOutOfScopeSymlinkProducesIssue() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: outside) }
        try writeFile(outside.appendingPathComponent("foreign.dat"), bytes: 999)

        let nestedDir = root.appendingPathComponent("Caches/A")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let link = nestedDir.appendingPathComponent("LinkOutside")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: outside.path)

        let result = WeChatStorageScanner().scan(roots: [readableRoot(url: root)])

        // 嵌套 symlink 越界:不仅静默跳过,还要按 spec 报 permissionLimited issue。
        XCTAssertTrue(result.issues.contains { $0.reason == .permissionLimited })
        XCTAssertEqual(result.totalVisibleBytes, 0)
    }

    func test_scan_cancelMidScanProducesCancelledIssue() throws {
        let root = try makeTemporaryDir()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<3 {
            try writeFile(root.appendingPathComponent("Cache\(index)/d.dat"), bytes: 10)
        }
        var calls = 0
        let result = WeChatStorageScanner().scan(roots: [readableRoot(url: root)]) {
            calls += 1
            return calls > 2
        }
        XCTAssertTrue(result.issues.contains { $0.reason == .scanCancelled })
    }

    func test_inferCategory_coversKeyPathComponents() {
        XCTAssertEqual(WeChatStorageScanner.inferCategory(path: "/x/Caches/a"), .cache)
        XCTAssertEqual(WeChatStorageScanner.inferCategory(path: "/x/run.log"), .logs)
        XCTAssertEqual(WeChatStorageScanner.inferCategory(path: "/x/store.sqlite"), .databasesAndState)
        XCTAssertEqual(WeChatStorageScanner.inferCategory(path: "/x/Media/photo"), .mediaAndFiles)
        XCTAssertEqual(WeChatStorageScanner.inferCategory(path: "/x/random"), .other)
    }

    // MARK: - Helpers

    private func readableRoot(url: URL) -> WeChatStorageRoot {
        WeChatStorageRoot(url: url, kind: .applicationContainer, displayName: "应用容器", availability: .readable)
    }

    private func categoryBytes(_ result: WeChatStorageScanResult, _ category: WeChatStorageCategory) -> Int {
        result.categories.first { $0.category == category }?.sizeBytes ?? 0
    }

    @discardableResult
    private func makeTemporaryDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-wechat-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }
}
