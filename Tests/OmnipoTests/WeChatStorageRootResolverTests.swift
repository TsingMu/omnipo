import XCTest
@testable import Omnipo

final class WeChatStorageRootResolverTests: XCTestCase {

    func test_resolve_includesExistingContainersAndSkipsMissing() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try makeDir(home, "Library/Containers/\(bid)")
        try makeDir(home, "Library/Application Support/\(bid)")
        // Caches/<bid> 未创建 → missing → absent

        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: bid), homeDirectory: home)
        let roots = resolver.resolve()

        let kinds = Set(roots.map(\.kind))
        XCTAssertTrue(kinds.contains(.applicationContainer))
        XCTAssertTrue(kinds.contains(.applicationSupport))
        XCTAssertFalse(kinds.contains(.cache))
    }

    func test_resolve_displayNamesAreSanitized() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try makeDir(home, "Library/Containers/\(bid)")
        try makeDir(home, "Library/Group Containers/group.\(bid).shared")

        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: bid), homeDirectory: home)
        let roots = resolver.resolve()

        for root in roots {
            XCTAssertFalse(root.displayName.contains("/"))
            XCTAssertFalse(root.displayName.contains(bid))
        }
    }

    func test_resolve_includesGroupContainersMatchingBidWithSanitizedName() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        try makeDir(home, "Library/Group Containers/group.\(bid).shared")
        try makeDir(home, "Library/Group Containers/unrelated.group")  // 不匹配 bid

        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: bid), homeDirectory: home)
        let roots = resolver.resolve()

        let groupRoots = roots.filter { $0.kind == .groupContainer }
        XCTAssertEqual(groupRoots.count, 1)
        XCTAssertEqual(groupRoots.first?.displayName, "共享容器 1")
    }

    func test_resolve_usesFallbackWhenProviderReturnsNil() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeDir(home, "Library/Containers/com.tencent.xinWeChat")

        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: nil), homeDirectory: home)
        let roots = resolver.resolve()

        XCTAssertTrue(roots.contains { $0.kind == .applicationContainer })
    }

    func test_resolve_deduplicatesSymlinkedRoot() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let bid = "com.tencent.xinWeChat"
        let real = try makeDir(home, "Library/Containers/\(bid)")
        let link = home.appendingPathComponent("LinkToContainer")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)

        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: bid), homeDirectory: home)
        let roots = resolver.resolve(userSelectedRoots: [link])

        let realStandard = real.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertEqual(roots.filter { $0.url.path == realStandard }.count, 1)
    }

    func test_resolve_userSelectedRootsAreIncluded() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let userRoot = try makeDir(home, "CustomWeChatRoot")

        let resolver = WeChatStorageRootResolver(bundleIDProvider: FixedBidProvider(bid: "com.tencent.xinWeChat"), homeDirectory: home)
        let roots = resolver.resolve(userSelectedRoots: [userRoot])

        XCTAssertTrue(roots.contains { $0.kind == .userSelected })
    }

    // MARK: - Helpers

    private func makeTemporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-wechat-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeDir(_ parent: URL, _ relativePath: String) throws -> URL {
        let url = parent.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct FixedBidProvider: WeChatBundleIdentifierProviding {
    let bid: String?
    func installedWeChatBundleIdentifier() -> String? { bid }
}
