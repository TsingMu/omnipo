import XCTest
@testable import Omnipo

final class MenuBarNetworkRateMonitorTests: XCTestCase {

    private var consumers: [Task<Void, Never>] = []

    override func tearDown() async throws {
        consumers.forEach { $0.cancel() }
        consumers = []
    }

    // MARK: - 首次预热与第二次速率

    func test_start_publishesWarmingUpThenDirectionalRates() async {
        let (monitor, _) = makeMonitor(interval: 0.05, script: [
            counters(in: 0, out: 0),
            counters(in: 150_000, out: 0),
            counters(in: 150_000, out: 300_000),
        ])
        let collector = RateCollector()
        let stream = await monitor.start(requestGeneration: 1)
        record(stream, into: collector)

        let first = await awaitElement(collector, 0)
        XCTAssertEqual(first, .warmingUp, "会话开始应立即发布预热占位")

        let second = await awaitElement(collector, 1)
        guard case .available(let downloadRates) = second else {
            XCTFail("第二次采样应发布 available,实际: \(String(describing: second))")
            return
        }
        XCTAssertGreaterThan(downloadRates.downloadBytesPerSecond, 0, "入站增量应映射为下载速率")
        XCTAssertEqual(downloadRates.uploadBytesPerSecond, 0, "无出站增量时上传应为 0")

        let third = await awaitElement(collector, 2)
        guard case .available(let uploadRates) = third else {
            XCTFail("第三次采样应发布 available,实际: \(String(describing: third))")
            return
        }
        XCTAssertGreaterThan(uploadRates.uploadBytesPerSecond, 0, "出站增量应映射为上传速率")
        XCTAssertEqual(uploadRates.downloadBytesPerSecond, 0, "无入站增量时下载应为 0")

        await monitor.stop(requestGeneration: 2)
    }

    // MARK: - 失败降级

    func test_firstReadFailure_degradesToUnavailableThenRecovers() async {
        let (monitor, _) = makeMonitor(interval: 0.05, script: [
            nil,
            counters(in: 0, out: 0),
            counters(in: 5_000, out: 7_000),
        ])
        let collector = RateCollector()
        let stream = await monitor.start(requestGeneration: 1)
        record(stream, into: collector)

        let unavailable = await awaitElement(collector, 1)
        XCTAssertEqual(unavailable, .unavailable, "首次读取失败应直接降级,不得伪造零速率")

        let recovered = await awaitElement(collector, 2)
        guard case .available(let rates) = recovered else {
            XCTFail("读取恢复后应发布 available,实际: \(String(describing: recovered))")
            return
        }
        XCTAssertGreaterThan(rates.downloadBytesPerSecond, 0)
        XCTAssertGreaterThan(rates.uploadBytesPerSecond, 0)

        await monitor.stop(requestGeneration: 2)
    }

    func test_transientFailureAfterBaseline_publishesUnavailableAndKeepsBaseline() async {
        let (monitor, _) = makeMonitor(interval: 0.05, script: [
            counters(in: 0, out: 0),
            nil,
            counters(in: 5_000, out: 7_000),
        ])
        let collector = RateCollector()
        let stream = await monitor.start(requestGeneration: 1)
        record(stream, into: collector)

        let unavailable = await awaitElement(collector, 1)
        XCTAssertEqual(unavailable, .unavailable, "基线建立后的读取失败应发布 unavailable")

        let recovered = await awaitElement(collector, 2)
        guard case .available(let rates) = recovered else {
            XCTFail("瞬时失败后应沿用基线直接恢复速率,实际: \(String(describing: recovered))")
            return
        }
        XCTAssertGreaterThan(rates.downloadBytesPerSecond, 0)
        XCTAssertGreaterThan(rates.uploadBytesPerSecond, 0)

        await monitor.stop(requestGeneration: 2)
    }

    // MARK: - 重复 start:会话继续,不重新预热

    func test_repeatedStart_continuesSessionWithoutRewarming() async {
        let (monitor, _) = makeMonitor(interval: 0.05, script: [
            counters(in: 0, out: 0),
            counters(in: 10_000, out: 10_000),
            counters(in: 20_000, out: 20_000),
        ])
        let firstCollector = RateCollector()
        let firstStream = await monitor.start(requestGeneration: 1)
        record(firstStream, into: firstCollector)

        let firstRate = await awaitElement(firstCollector, 1)
        guard case .available = firstRate else {
            XCTFail("应先观察到首个速率,实际: \(String(describing: firstRate))")
            return
        }

        let secondStream = await monitor.start(requestGeneration: 2)
        let secondCollector = RateCollector()
        record(secondStream, into: secondCollector)

        let reattached = await awaitElement(secondCollector, 0)
        guard case .available = reattached else {
            XCTFail("重复 start 不应重置会话,新流的首个采样结果应为 available,实际: \(String(describing: reattached))")
            return
        }

        let oldStreamFinished = await awaitFinished(firstCollector)
        XCTAssertTrue(oldStreamFinished, "重复 start 后旧流应被结束")

        await monitor.stop(requestGeneration: 3)
    }

    // MARK: - stop 与 restart:清空基线、隔离晚到结果

    func test_stop_endsStreamAndRestartRewarmsWithFreshBaseline() async {
        // 使用较长间隔保证 stop 前恰好完成 2 次读取,消除时序竞态
        let (monitor, _) = makeMonitor(interval: 0.5, script: [
            counters(in: 0, out: 0),
            counters(in: 10_000, out: 10_000),
            counters(in: 10_000, out: 10_000),
            counters(in: 15_000, out: 15_000),
        ])
        let firstCollector = RateCollector()
        let firstStream = await monitor.start(requestGeneration: 1)
        record(firstStream, into: firstCollector)

        let firstRate = await awaitElement(firstCollector, 1)
        guard case .available = firstRate else {
            XCTFail("首个速率应发布 available,实际: \(String(describing: firstRate))")
            return
        }

        await monitor.stop(requestGeneration: 2)
        await monitor.stop(requestGeneration: 3)  // 幂等

        let oldStreamFinished = await awaitFinished(firstCollector)
        XCTAssertTrue(oldStreamFinished, "stop 后更新流应终止")

        let secondCollector = RateCollector()
        let secondStream = await monitor.start(requestGeneration: 4)
        record(secondStream, into: secondCollector)

        let rewarm = await awaitElement(secondCollector, 0)
        XCTAssertEqual(rewarm, .warmingUp, "再次 start 应重新预热")

        // 基线已清空:第一个采样仅建立基线,首个速率来自第二个采样(增量 > 0)。
        // 若 stop 未清空基线,第一个采样就会发布零增量速率。
        let secondRate = await awaitElement(secondCollector, 1, timeout: 5)
        guard case .available(let rates) = secondRate else {
            XCTFail("重新预热后应发布 available,实际: \(String(describing: secondRate))")
            return
        }
        XCTAssertGreaterThan(rates.downloadBytesPerSecond, 0, "stop 应清空差值基线")
        XCTAssertGreaterThan(rates.uploadBytesPerSecond, 0)

        await monitor.stop(requestGeneration: 5)
    }

    // MARK: - 过期代次请求:隔离迟到的异步结果

    func test_staleStartRequest_isRejectedWithoutCreatingSession() async {
        // 会话 1 建立并停止后,迟到的同代次 start 不得复活采样
        let (monitor, _) = makeMonitor(interval: 0.05, script: [
            counters(in: 0, out: 0),
            counters(in: 10_000, out: 10_000),
            counters(in: 20_000, out: 20_000),
            counters(in: 30_000, out: 30_000),
        ])
        let firstCollector = RateCollector()
        let firstStream = await monitor.start(requestGeneration: 1)
        record(firstStream, into: firstCollector)

        let firstRate = await awaitElement(firstCollector, 1)
        guard case .available = firstRate else {
            XCTFail("首个速率应发布 available,实际: \(String(describing: firstRate))")
            return
        }
        await monitor.stop(requestGeneration: 2)

        // 过期 start:返回已结束的空流,不创建采样会话
        let staleCollector = RateCollector()
        let staleStream = await monitor.start(requestGeneration: 1)
        record(staleStream, into: staleCollector)
        let staleFinished = await awaitFinished(staleCollector)
        XCTAssertTrue(staleFinished, "过期 start 应立即结束返回的流")
        let staleCount = await staleCollector.count()
        XCTAssertEqual(staleCount, 0, "过期 start 不得发布任何更新")

        // 随后的合法 start 应是全新会话(首个元素为 warmingUp),
        // 证明过期 start 没有创建会话
        let secondCollector = RateCollector()
        let secondStream = await monitor.start(requestGeneration: 3)
        record(secondStream, into: secondCollector)
        let rewarm = await awaitElement(secondCollector, 0)
        XCTAssertEqual(rewarm, .warmingUp, "合法 start 应创建全新会话并重新预热")

        await monitor.stop(requestGeneration: 4)
    }

    func test_staleStopRequest_doesNotStopNewerSession() async {
        let (monitor, _) = makeMonitor(interval: 0.05, script: [
            counters(in: 0, out: 0),
            counters(in: 10_000, out: 10_000),
            counters(in: 20_000, out: 20_000),
            counters(in: 30_000, out: 30_000),
            counters(in: 40_000, out: 40_000),
            counters(in: 50_000, out: 50_000),
        ])
        let firstCollector = RateCollector()
        let firstStream = await monitor.start(requestGeneration: 1)
        record(firstStream, into: firstCollector)
        _ = await awaitElement(firstCollector, 1)
        await monitor.stop(requestGeneration: 2)

        let secondCollector = RateCollector()
        let secondStream = await monitor.start(requestGeneration: 3)
        record(secondStream, into: secondCollector)
        let rewarm = await awaitElement(secondCollector, 0)
        XCTAssertEqual(rewarm, .warmingUp)
        let secondRate = await awaitElement(secondCollector, 1)
        guard case .available = secondRate else {
            XCTFail("会话 3 应发布速率,实际: \(String(describing: secondRate))")
            return
        }

        // 迟到的过期 stop:不得终止会话 3
        await monitor.stop(requestGeneration: 2)

        let nextRate = await awaitElement(secondCollector, 2)
        guard case .available = nextRate else {
            XCTFail("过期 stop 后新会话应继续发布速率,实际: \(String(describing: nextRate))")
            return
        }

        await monitor.stop(requestGeneration: 4)
    }

    // MARK: - Helpers

    private func counters(in: UInt64, out: UInt64) -> NetworkSampler.Counters {
        NetworkSampler.Counters(
            bytesInByInterface: ["en0": `in`],
            bytesOutByInterface: ["en0": out]
        )
    }

    private func makeMonitor(
        interval: TimeInterval,
        script: [NetworkSampler.Counters?]
    ) -> (monitor: MenuBarNetworkRateMonitor, scripted: ScriptedCounters) {
        let scripted = ScriptedCounters(script)
        let sampler = NetworkSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.menubar"),
            countersProvider: scripted.read
        )
        let monitor = MenuBarNetworkRateMonitor(sampler: sampler, interval: interval)
        return (monitor, scripted)
    }

    private func record(
        _ stream: AsyncStream<MenuBarNetworkRateAvailability>,
        into collector: RateCollector
    ) {
        consumers.append(Task {
            for await element in stream {
                await collector.append(element)
            }
            await collector.markFinished()
        })
    }

    @discardableResult
    private func awaitElement(
        _ collector: RateCollector,
        _ index: Int,
        timeout: TimeInterval = 3
    ) async -> MenuBarNetworkRateAvailability? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = await collector.element(at: index) { return element }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }

    private func awaitFinished(_ collector: RateCollector, timeout: TimeInterval = 2) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await collector.isFinished() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

/// 按脚本依次返回计数;脚本耗尽后永远返回最后一个响应。
private final class ScriptedCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [NetworkSampler.Counters?]
    private var held: NetworkSampler.Counters?

    init(_ responses: [NetworkSampler.Counters?]) {
        self.responses = responses
    }

    var read: @Sendable () -> NetworkSampler.Counters? {
        { self.pop() }
    }

    private func pop() -> NetworkSampler.Counters? {
        lock.lock()
        defer { lock.unlock() }
        if !responses.isEmpty {
            held = responses.removeFirst()
        }
        return held
    }
}

private actor RateCollector {
    private var elements: [MenuBarNetworkRateAvailability] = []
    private var finished = false

    func append(_ element: MenuBarNetworkRateAvailability) {
        elements.append(element)
    }

    func markFinished() {
        finished = true
    }

    func element(at index: Int) -> MenuBarNetworkRateAvailability? {
        index < elements.count ? elements[index] : nil
    }

    func count() -> Int {
        elements.count
    }

    func isFinished() -> Bool {
        finished
    }
}
