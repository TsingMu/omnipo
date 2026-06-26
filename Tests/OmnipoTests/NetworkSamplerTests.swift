import XCTest
import os
@testable import Omnipo

private func makeCounters(
    _ inBy: [String: UInt64] = [:],
    _ outBy: [String: UInt64] = [:]
) -> NetworkSampler.Counters {
    NetworkSampler.Counters(bytesInByInterface: inBy, bytesOutByInterface: outBy)
}

final class NetworkSamplerTests: XCTestCase {

    private func counters(
        _ inBy: [String: UInt64] = [:],
        _ outBy: [String: UInt64] = [:]
    ) -> NetworkSampler.Counters {
        makeCounters(inBy, outBy)
    }

    // MARK: - metrics(from:to:interval:) 纯函数

    func test_metrics_computesPerInterfaceRates() {
        let prev = counters(["en0": 1000], ["en0": 500])
        let curr = counters(["en0": 3000], ["en0": 1500])

        let metrics = NetworkSampler.metrics(from: prev, to: curr, interval: 2.0)

        XCTAssertEqual(metrics.interfaces.count, 1)
        let en0 = metrics.interfaces.first { $0.name == "en0" }
        XCTAssertEqual(en0?.bytesInPerSec ?? -1, 1000, accuracy: 1e-9)  // (3000-1000)/2
        XCTAssertEqual(en0?.bytesOutPerSec ?? -1, 500, accuracy: 1e-9)   // (1500-500)/2
    }

    func test_metrics_zeroIntervalReturnsZeroRates() {
        let prev = counters(["en0": 100], ["en0": 50])
        let curr = counters(["en0": 200], ["en0": 100])

        let metrics = NetworkSampler.metrics(from: prev, to: curr, interval: 0)

        let en0 = metrics.interfaces.first { $0.name == "en0" }
        XCTAssertEqual(en0?.bytesInPerSec, 0)
        XCTAssertEqual(en0?.bytesOutPerSec, 0)
    }

    func test_metrics_negativeDeltaTreatedAsZero() {
        // 接口重置或 wraparound:curr < prev
        let prev = counters(["en0": 1000], ["en0": 500])
        let curr = counters(["en0": 100], ["en0": 50])

        let metrics = NetworkSampler.metrics(from: prev, to: curr, interval: 1.0)

        let en0 = metrics.interfaces.first { $0.name == "en0" }
        XCTAssertEqual(en0?.bytesInPerSec, 0)
        XCTAssertEqual(en0?.bytesOutPerSec, 0)
    }

    func test_metrics_mergesNewAndDisappearingInterfaces() {
        let prev = counters(["en0": 100, "en5": 200], ["en0": 50])
        let curr = counters(["en0": 200, "en1": 300], ["en0": 100, "en1": 50])

        let metrics = NetworkSampler.metrics(from: prev, to: curr, interval: 1.0)

        let names = Set(metrics.interfaces.map(\.name))
        XCTAssertTrue(names.contains("en0"))
        XCTAssertTrue(names.contains("en1"))
        XCTAssertTrue(names.contains("en5"))

        // en5 在 curr 缺失,delta 视为 0(currIn=0, prevIn=200 → curr < prev → 0)
        let en5 = metrics.interfaces.first { $0.name == "en5" }
        XCTAssertEqual(en5?.bytesInPerSec, 0)
    }

    func test_metrics_aggregatesTotals() {
        let prev = counters(["en0": 100, "en1": 200], ["en0": 50, "en1": 100])
        let curr = counters(["en0": 300, "en1": 500], ["en0": 150, "en1": 300])

        let metrics = NetworkSampler.metrics(from: prev, to: curr, interval: 1.0)

        XCTAssertEqual(metrics.totalBytesInPerSec, 500, accuracy: 1e-9)
        XCTAssertEqual(metrics.totalBytesOutPerSec, 300, accuracy: 1e-9)
    }

    // MARK: - placeholderMetrics

    func test_placeholderMetrics_zeroRates() {
        let current = counters(["en0": 100, "en5": 200], ["en0": 50])
        let metrics = NetworkSampler.placeholderMetrics(from: current)

        XCTAssertEqual(metrics.interfaces.count, 2)
        for iface in metrics.interfaces {
            XCTAssertEqual(iface.bytesInPerSec, 0)
            XCTAssertEqual(iface.bytesOutPerSec, 0)
        }
    }

    // MARK: - sample(previous:) with injected provider

    func test_sample_firstCallReturnsPlaceholderWithCurrentInterfaces() {
        let sampler = NetworkSampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.net"),
            countersProvider: { makeCounters(["en0": 100], ["en0": 50]) }
        )

        let (availability, previous) = sampler.sample(previous: nil)
        guard case .available(let metrics) = availability else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.interfaces.count, 1)
        XCTAssertEqual(metrics.interfaces.first?.bytesInPerSec, 0)
        XCTAssertNotNil(previous)
    }

    func test_sample_secondCallProducesRealRates() {
        let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
        let sampler = NetworkSampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.net"),
            countersProvider: {
                let n = counter.withLock { v -> Int in
                    let curr = v
                    v += 1
                    return curr
                }
                return n == 0
                    ? makeCounters(["en0": 1000], ["en0": 500])
                    : makeCounters(["en0": 2000], ["en0": 1000])
            }
        )

        let (_, firstPrevious) = sampler.sample(previous: nil)
        // 让时间流逝一点
        Thread.sleep(forTimeInterval: 0.05)
        let (availability, _) = sampler.sample(previous: firstPrevious)

        guard case .available(let metrics) = availability else {
            return XCTFail("expected available")
        }
        let en0 = metrics.interfaces.first { $0.name == "en0" }
        XCTAssertNotNil(en0)
        XCTAssertGreaterThan(en0?.bytesInPerSec ?? 0, 0)
    }

    func test_sample_providerFailureReturnsGetifaddrsFailed() {
        let sampler = NetworkSampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.net"),
            countersProvider: { nil }
        )

        let (availability, previous) = sampler.sample(previous: nil)
        XCTAssertEqual(availability, .unavailable(reason: .getifaddrsFailed))
        XCTAssertNil(previous)
    }

    // MARK: - 真实 getifaddrs 冒烟

    func test_sample_realGetifaddrsReturnsAvailableOrFailure() {
        let sampler = NetworkSampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.net")
        )

        let (availability, previous) = sampler.sample(previous: nil)
        if case .available(let metrics) = availability {
            // 没有回环 lo0;每个接口速率应为 0(首次)
            XCTAssertFalse(metrics.interfaces.contains { $0.name.hasPrefix("lo") })
        } else if case .unavailable(let reason) = availability {
            XCTAssertEqual(reason, .getifaddrsFailed)
        }
        XCTAssertNotNil(previous, "成功时必须有 Previous")
    }
}
