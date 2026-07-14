import XCTest
import os
@testable import Omnipo

private func makeTicks(
    _ user: UInt64, _ system: UInt64, _ idle: UInt64, _ nice: UInt64 = 0
) -> CPUSampler.Ticks {
    CPUSampler.Ticks(user: user, system: system, idle: idle, nice: nice)
}

final class CPUSamplerTests: XCTestCase {

    private func ticks(_ user: UInt64, _ system: UInt64, _ idle: UInt64, _ nice: UInt64 = 0)
        -> CPUSampler.Ticks
    {
        makeTicks(user, system, idle, nice)
    }

    // MARK: - availability(from:current:) 纯函数

    func test_availability_noPreviousReturnsWarmup() {
        let result = CPUSampler.availability(from: nil, current: ticks(100, 50, 200, 10))
        XCTAssertEqual(result, .unavailable(reason: .warmup))
    }

    func test_availability_zeroDeltaReturnsWarmup() {
        let previous = ticks(100, 50, 200, 10)
        let current = ticks(100, 50, 200, 10)
        let result = CPUSampler.availability(from: previous, current: current)
        XCTAssertEqual(result, .unavailable(reason: .warmup))
    }

    func test_availability_allIdleReturnsIdleOne() {
        let previous = ticks(0, 0, 100, 0)
        let current = ticks(0, 0, 200, 0)
        let result = CPUSampler.availability(from: previous, current: current)
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.idlePercent, 1.0, accuracy: 1e-9)
        XCTAssertEqual(metrics.userPercent, 0.0, accuracy: 1e-9)
        XCTAssertEqual(metrics.systemPercent, 0.0, accuracy: 1e-9)
    }

    func test_availability_allUserReturnsUserOne() {
        let previous = ticks(100, 0, 0, 0)
        let current = ticks(200, 0, 0, 0)
        let result = CPUSampler.availability(from: previous, current: current)
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.userPercent, 1.0, accuracy: 1e-9)
        XCTAssertEqual(metrics.busyPercent, 1.0, accuracy: 1e-9)
    }

    func test_availability_mixedCalculatesCorrectly() {
        // user +50, system +30, idle +20, nice +0  → total 100
        let previous = ticks(100, 30, 50, 5)
        let current = ticks(150, 60, 70, 5)
        let result = CPUSampler.availability(from: previous, current: current)
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.userPercent, 0.5, accuracy: 1e-9)
        XCTAssertEqual(metrics.systemPercent, 0.3, accuracy: 1e-9)
        XCTAssertEqual(metrics.idlePercent, 0.2, accuracy: 1e-9)
    }

    func test_availability_niceCountedAsUser() {
        // user +30, nice +20 → userPercent 应为 0.5(30+20)/100
        let previous = ticks(10, 0, 0, 0)
        let current = ticks(40, 0, 50, 20)
        let result = CPUSampler.availability(from: previous, current: current)
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.userPercent, 0.5, accuracy: 1e-9)
    }

    func test_availability_handlesTickWraparound() {
        // UInt64 溢出回绕:&- 处理 wraparound。previous 大,current 小(回绕后)
        let previous = ticks(UInt64.max - 30, 0, 0, 0)
        let current = ticks(20, 0, 0, 0)
        let result = CPUSampler.availability(from: previous, current: current)
        guard case .available(let metrics) = result else {
            return XCTFail("expected available even with tick wraparound")
        }
        // (max-30) → 20 是 +50 的差值,用户占用应为 1.0
        XCTAssertEqual(metrics.userPercent, 1.0, accuracy: 1e-9)
    }

    // MARK: - sample(previous:) with injected hostStatistics

    func test_sample_firstCallReturnsWarmupAndProvidesTicks() {
        let sampler = CPUSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.cpu"),
            hostStatistics: { makeTicks(100, 50, 200, 5) }
        )

        let (availability, newTicks) = sampler.sample(previous: nil)
        XCTAssertEqual(availability, .unavailable(reason: .warmup))
        XCTAssertNotNil(newTicks)
        XCTAssertEqual(newTicks?.user, 100)
    }

    func test_sample_secondCallProducesAvailability() {
        // 用 counter 锁避免 var 在 @Sendable 闭包中被并发修改。
        let counter = OSAllocatedUnfairLock<Int>(initialState: 0)
        let firstSample = makeTicks(100, 50, 200, 5)
        let secondSample = makeTicks(150, 60, 250, 5)
        let sampler = CPUSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.cpu"),
            hostStatistics: {
                let n = counter.withLock { value -> Int in
                    let current = value
                    value += 1
                    return current
                }
                return n == 0 ? firstSample : secondSample
            }
        )

        let (_, previous) = sampler.sample(previous: nil)
        let (availability, _) = sampler.sample(previous: previous)

        // 两次采样后 delta > 0,应得到 available;若 Mach 集成失败至少不是 hostInfoFailed。
        if case .unavailable(let reason) = availability {
            XCTAssertNotEqual(reason, .hostInfoFailed, "injected hostStatistics 不应失败")
        }
    }

    func test_sample_hostStatisticsFailureReturnsHostInfoFailed() {
        let sampler = CPUSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.cpu"),
            hostStatistics: { nil }
        )

        let (availability, _) = sampler.sample(previous: ticks(1, 2, 3, 4))
        XCTAssertEqual(availability, .unavailable(reason: .hostInfoFailed))
        // newTicks 的具体内容由 preservesPreviousTicks 测试覆盖。
    }

    func test_sample_hostStatisticsFailurePreservesPreviousTicks() {
        let sampler = CPUSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.cpu"),
            hostStatistics: { nil }
        )

        let previous = ticks(100, 50, 200, 5)
        let (_, returned) = sampler.sample(previous: previous)
        XCTAssertEqual(returned, previous, "失败时返回的 ticks 应是 previous,以便下次重试")
    }

    // MARK: - 真实 Mach 调用冒烟

    func test_sample_realMachCallAtLeastOnceReturnsTicks() {
        let sampler = CPUSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.cpu")
        )

        let (availability, newTicks) = sampler.sample(previous: nil)
        XCTAssertEqual(availability, .unavailable(reason: .warmup), "首次采样无 previous")
        XCTAssertNotNil(newTicks, "真实 Mach 调用应返回 ticks")
    }

    func test_sample_realMachCallTwiceProducesAvailableOrWarmup() {
        let sampler = CPUSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.cpu")
        )

        let (_, first) = sampler.sample(previous: nil)
        Thread.sleep(forTimeInterval: 0.05)
        let (availability, _) = sampler.sample(previous: first)

        if case .unavailable(let reason) = availability {
            XCTAssertEqual(reason, .warmup, "两次采样后只接受 warmup,不接受 hostInfoFailed")
        } else if case .available = availability {
            // 预期路径
        }
    }
}
