import XCTest
import os
@testable import Omnipo

private let sampleApps: [AppRecord] = [
    AppRecord(bundleIdentifier: "com.apple.Safari", displayName: "Safari"),
    AppRecord(bundleIdentifier: "com.apple.mail", displayName: "Mail"),
    AppRecord(bundleIdentifier: "com.omnipo.app", displayName: "Omnipo"),
    AppRecord(
        bundleIdentifier: "com.tencent.xinWeChat",
        displayName: "微信",
        aliases: ["WeChat"]
    )
]

final class ApplicationSearchProviderTests: XCTestCase {

    func test_emptyQuery_returnsEmpty() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.isEmpty)
        } else {
            XCTFail("expected success")
        }
    }

    func test_exactName_matchesWithFullScore() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "Safari", generation: 1)

        if case .success(let results) = result {
            XCTAssertEqual(results.first?.title, "Safari")
            XCTAssertEqual(results.first?.matchScore, 1.0)
        } else {
            XCTFail("expected success")
        }
    }

    func test_bundleIdMatch_worksForPartialBundleId() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "com.apple", generation: 1)

        if case .success(let results) = result {
            XCTAssertGreaterThanOrEqual(results.count, 2, "should match multiple com.apple.* apps")
        } else {
            XCTFail("expected success")
        }
    }

    func test_noMatch_returnsEmpty() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "zzzz", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.isEmpty)
        } else {
            XCTFail("expected success")
        }
    }

    func test_deduplicatesByBundleIdentifier() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "com", generation: 1)

        guard case .success(let results) = result else {
            XCTFail("expected success")
            return
        }
        let bundleIds = results.compactMap { result -> String? in
            if case .applicationBundleIdentifier(let id) = result.executionPayload {
                return id
            }
            return nil
        }
        XCTAssertEqual(bundleIds.count, Set(bundleIds).count, "no duplicate bundle IDs")
    }

    func test_refresh_callsDiscover() async {
        let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
        let provider = ApplicationSearchProvider(discover: {
            counter.withLock { $0 += 1 }
            return sampleApps
        })
        await provider.refresh()
        let count = counter.withLock { $0 }
        XCTAssertEqual(count, 1)
    }

    func test_iconDescriptor_carriesBundleIdNotImage() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "Safari", generation: 1)

        guard case .success(let results) = result, let first = results.first else {
            XCTFail("expected success with results")
            return
        }
        if case .appBundleIdentifier(let id) = first.iconDescriptor {
            XCTAssertEqual(id, "com.apple.Safari")
        } else {
            XCTFail("icon descriptor should be appBundleIdentifier")
        }
    }

    func test_localizedApplication_matchesEnglishBundleName() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "wechat", generation: 1)

        guard case .success(let results) = result else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(results.first?.title, "微信")
    }

    func test_localizedApplication_matchesCompactCompositionText() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })
        let result = await provider.search(query: "we chat", generation: 1)

        guard case .success(let results) = result else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(results.first?.title, "微信")
    }

    func test_chineseApplication_matchesPinyinForms() async {
        let provider = ApplicationSearchProvider(discover: { sampleApps })

        for query in ["wechat", "we cha", "weixin", "wei xin", "wx", "微信"] {
            let result = await provider.search(query: query, generation: 1)
            guard case .success(let results) = result else {
                XCTFail("expected success for \(query)")
                continue
            }
            XCTAssertEqual(results.first?.title, "微信", "query: \(query)")
        }
    }

    func test_appRecord_precomputesPinyinAliases() {
        let record = AppRecord(bundleIdentifier: "com.tencent.xinWeChat", displayName: "微信")

        XCTAssertTrue(record.aliases.contains("wei xin"))
        XCTAssertTrue(record.aliases.contains("weixin"))
        XCTAssertTrue(record.aliases.contains("wx"))
    }
}
