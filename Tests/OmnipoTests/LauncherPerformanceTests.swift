import XCTest
@testable import Omnipo

private struct BenchmarkFileProvider: SearchProvider {
    let kind = SearchProviderKind.file

    func search(query: String, generation: UInt64) async -> SearchProviderResult {
        try? await Task.sleep(for: .milliseconds(20))
        return .success([])
    }
}

final class LauncherPerformanceTests: XCTestCase {
    private let sampleCount = 40

    func test_prewarmedApplicationMatching_p95IsWithin50Milliseconds() async {
        let apps = makeApplications(count: 1_000)
        let index = ApplicationIndex(discover: { apps })
        let provider = ApplicationSearchProvider(index: index)
        await index.prewarm()
        _ = await provider.search(query: "target app 999", generation: 0)

        var samples: [Duration] = []
        for generation in 1...sampleCount {
            let start = ContinuousClock.now
            _ = await provider.search(
                query: "target app 999",
                generation: UInt64(generation)
            )
            samples.append(start.duration(to: .now))
        }

        let p95 = percentile95(samples)
        print("PERF prewarmed-application-match p95=\(p95)")
        XCTAssertLessThanOrEqual(
            p95,
            .milliseconds(50),
            "预热应用匹配 P95 超过 50ms：\(p95)"
        )
    }

    @MainActor
    func test_launcherStoreFirstLocalBatch_p95IsWithin100Milliseconds() async {
        let apps = makeApplications(count: 1_000)
        let index = ApplicationIndex(discover: { apps })
        await index.prewarm()
        let service = DefaultSearchService(
            providers: [
                CommandSearchProvider(),
                ApplicationSearchProvider(index: index),
                BenchmarkFileProvider()
            ],
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.performance"),
            fileDebounce: .milliseconds(150)
        )
        let store = LauncherStore(service: service)

        store.updateQuery("target app 999")
        let warmupReceived = await waitForFirstResult(in: store, timeout: .milliseconds(500))
        XCTAssertTrue(warmupReceived)
        store.cancelAll()

        var samples: [Duration] = []
        for _ in 0..<sampleCount {
            let start = ContinuousClock.now
            store.updateQuery("target app 999")
            let received = await waitForFirstResult(in: store, timeout: .milliseconds(500))
            samples.append(start.duration(to: .now))
            XCTAssertTrue(received, "Launcher Store 未在 500ms 安全超时内收到首批结果")
            store.cancelAll()
        }

        let p95 = percentile95(samples)
        print("PERF launcher-store-first-local-batch p95=\(p95)")
        XCTAssertLessThanOrEqual(
            p95,
            .milliseconds(100),
            "Launcher Store 首批本地结果 P95 超过 100ms：\(p95)"
        )
    }

    private func makeApplications(count: Int) -> [AppRecord] {
        (0..<count).map { index in
            AppRecord(
                bundleIdentifier: "com.example.target-app-\(index)",
                displayName: "Target App \(index)"
            )
        }
    }

    private func percentile95(_ samples: [Duration]) -> Duration {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }

    @MainActor
    private func waitForFirstResult(
        in store: LauncherStore,
        timeout: Duration
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while store.results.isEmpty {
            guard ContinuousClock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }
}
