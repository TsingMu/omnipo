import XCTest
@testable import Omnipo

final class DefaultWeChatStorageServiceTests: XCTestCase {

    func test_scan_returnsAggregatedResultForFixtureHome() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try writeFile(home.appendingPathComponent("Library/Containers/\(bid)/Caches/a.dat"), bytes: 80)

        let result = try await makeService(home: home, bid: bid).scan().get()

        XCTAssertEqual(result.totalVisibleBytes, 80)
        XCTAssertTrue(result.roots.contains { $0.kind == .applicationContainer })
    }

    func test_refresh_returnsFreshResult() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try writeFile(home.appendingPathComponent("Library/Containers/\(bid)/Logs/run.log"), bytes: 30)

        let result = try await makeService(home: home, bid: bid).refresh().get()

        XCTAssertEqual(result.totalVisibleBytes, 30)
    }

    func test_cancel_beforeScan_producesCancelledIssue() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try writeFile(home.appendingPathComponent("Library/Containers/\(bid)/Caches/a.dat"), bytes: 80)

        let service = makeService(home: home, bid: bid)
        await service.cancel()

        let result = try await service.scan().get()
        XCTAssertTrue(result.issues.contains { $0.reason == .scanCancelled })
    }

    func test_refresh_resetsPriorCancel() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try writeFile(home.appendingPathComponent("Library/Containers/\(bid)/Caches/a.dat"), bytes: 80)

        let service = makeService(home: home, bid: bid)
        await service.cancel()
        let refreshed = try await service.refresh().get()

        XCTAssertEqual(refreshed.totalVisibleBytes, 80)
        XCTAssertFalse(refreshed.issues.contains { $0.reason == .scanCancelled })
    }

    func test_scan_doesNotModifyFileSystem() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        let file = home.appendingPathComponent("Library/Containers/\(bid)/Caches/a.dat")
        try writeFile(file, bytes: 80)
        let contentsBefore = try Data(contentsOf: file)

        _ = try await makeService(home: home, bid: bid).scan().get()

        let contentsAfter = try Data(contentsOf: file)
        XCTAssertEqual(contentsBefore, contentsAfter)
    }

    func test_refresh_includesUserSelectedRoots() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let userRoot = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        try writeFile(userRoot.appendingPathComponent("Caches/manual.dat"), bytes: 25)

        let service = makeService(
            home: home,
            bid: "com.tencent.xinWeChat",
            userSelectedRootsProvider: { [userRoot] }
        )
        let result = try await service.refresh().get()

        XCTAssertEqual(result.totalVisibleBytes, 25)
        XCTAssertTrue(result.roots.contains { $0.kind == .userSelected })
    }

    func test_refresh_passesSensitiveNameOptionToScanner() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try writeFile(home.appendingPathComponent("Library/Containers/\(bid)/Media/real-name.mp4"), bytes: 80)

        let result = try await makeService(
            home: home,
            bid: bid,
            scanOptionsProvider: { .init(includeSensitiveNames: true) }
        ).refresh().get()

        XCTAssertTrue(result.sensitiveNamesIncluded)
        XCTAssertEqual(result.largeFiles.first?.fileName, "real-name.mp4")
    }

    func test_refresh_releasesUserSelectedRootScopeAfterTerminalResult() async throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let userRoot = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: userRoot) }
        try writeFile(userRoot.appendingPathComponent("Caches/manual.dat"), bytes: 25)
        let releases = WeChatReleaseCounter()

        let service = makeService(
            home: home,
            bid: "com.tencent.xinWeChat",
            userSelectedRootsProvider: { [userRoot] },
            userSelectedRootsRelease: { await releases.increment() }
        )
        _ = try await service.refresh().get()
        let releaseCount = await releases.value

        XCTAssertEqual(releaseCount, 1)
    }

    // MARK: - Helpers

    private func makeService(
        home: URL,
        bid: String,
        userSelectedRootsProvider: @escaping @Sendable () async -> [URL] = { [] },
        userSelectedRootsRelease: @escaping @Sendable () async -> Void = {},
        scanOptionsProvider: @escaping @Sendable () async -> WeChatStorageScanOptions = { .anonymous }
    ) -> DefaultWeChatStorageService {
        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: bid), homeDirectory: home)
        return DefaultWeChatStorageService(
            resolver: resolver,
            scanner: WeChatStorageScanner(),
            userSelectedRootsProvider: userSelectedRootsProvider,
            userSelectedRootsRelease: userSelectedRootsRelease,
            scanOptionsProvider: scanOptionsProvider
        )
    }

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-wechat-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }
}

private actor WeChatReleaseCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct FixedBidProvider: WeChatBundleIdentifierProviding {
    let bid: String?
    func installedWeChatBundleIdentifier() -> String? { bid }
}
