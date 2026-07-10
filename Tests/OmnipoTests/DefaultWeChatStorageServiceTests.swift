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

    // MARK: - Helpers

    private func makeService(home: URL, bid: String) -> DefaultWeChatStorageService {
        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: bid), homeDirectory: home)
        return DefaultWeChatStorageService(resolver: resolver, scanner: WeChatStorageScanner())
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

private struct FixedBidProvider: WeChatBundleIdentifierProviding {
    let bid: String?
    func installedWeChatBundleIdentifier() -> String? { bid }
}
