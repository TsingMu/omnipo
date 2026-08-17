import XCTest
@testable import Omnipo

@MainActor
final class MenuBarNetworkSamplingControllerTests: XCTestCase {

    // MARK: - 正常显示/隐藏/重新显示

    func test_normalCycle_startsStopsAndRewarms() async {
        let (controller, recorder) = makeFixture()

        controller.show()

        let first = await awaitElement(recorder, 0)
        XCTAssertEqual(first, .warmingUp, "显示后应立即给出预热占位")
        let firstRate = await awaitElement(recorder, 2)
        guard case .available = firstRate else {
            XCTFail("预热后应发布真实速率,实际: \(String(describing: firstRate))")
            return
        }

        controller.hide()
        let hiddenApplied = await awaitHidden(recorder)
        XCTAssertTrue(hiddenApplied, "隐藏应在停止采样后回写")
        let countAtHidden = recorder.count

        // 隐藏后不应再有任何采样更新(宽限内无新增即视为已停止)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(recorder.count, countAtHidden, "隐藏后不应继续发布采样更新")

        controller.show()
        let rewarm = await awaitElement(recorder, countAtHidden)
        XCTAssertEqual(rewarm, .warmingUp, "重新显示应重新预热")
        let rewarmedRate = await awaitElement(recorder, countAtHidden + 2)
        guard case .available = rewarmedRate else {
            XCTFail("重新预热后应恢复速率,实际: \(String(describing: rewarmedRate))")
            return
        }
        XCTAssertEqual(recorder.hiddenCount, 1, "正常循环只应回写一次隐藏")
    }

    // MARK: - 快速 关闭→开启:隐藏任务不得回写隐藏,采样继续

    func test_rapidHideThenShow_neverAppliesHiddenAndKeepsSampling() async {
        let (controller, recorder) = makeFixture()

        controller.show()
        let firstRate = await awaitElement(recorder, 2)
        guard case .available = firstRate else {
            XCTFail("首个速率应发布 available,实际: \(String(describing: firstRate))")
            return
        }

        // 两个调用之间不挂起:隐藏任务执行时代次必然过期
        controller.hide()
        controller.show()

        // 旧会话无缝继续:重开后的首个采样结果仍是 available,而不是重新预热
        let resumed = await awaitElement(recorder, 3)
        guard case .available = resumed else {
            XCTFail("快速重开后采样应无缝继续,实际: \(String(describing: resumed))")
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(recorder.hiddenCount, 0, "过期隐藏任务不得在重开后回写隐藏")
    }

    // MARK: - 开启→关闭(已完成)→开启:重新预热且隐藏恰好一次

    func test_showHideShow_appliesHiddenExactlyOnceAndRewarms() async {
        let (controller, recorder) = makeFixture()

        controller.show()
        let firstRate = await awaitElement(recorder, 2)
        guard case .available = firstRate else {
            XCTFail("首个速率应发布 available,实际: \(String(describing: firstRate))")
            return
        }

        controller.hide()
        let hiddenApplied = await awaitHidden(recorder)
        XCTAssertTrue(hiddenApplied, "关闭应回写隐藏")
        let countAtHidden = recorder.count

        controller.show()
        let rewarm = await awaitElement(recorder, countAtHidden)
        XCTAssertEqual(rewarm, .warmingUp, "隐藏后的重新显示应重新预热")
        let rewarmedRate = await awaitElement(recorder, countAtHidden + 2)
        guard case .available = rewarmedRate else {
            XCTFail("重新预热后应恢复速率,实际: \(String(describing: rewarmedRate))")
            return
        }
        XCTAssertEqual(recorder.hiddenCount, 1, "不得出现重复回写隐藏")
    }

    // MARK: - 隐藏任务挂起期间被新显示取代:过期结果丢弃

    func test_hideInFlightThenShow_samplingResumesWithAtMostOneHiddenWrite() async {
        let (controller, recorder) = makeFixture()

        controller.show()
        let firstRate = await awaitElement(recorder, 2)
        guard case .available = firstRate else {
            XCTFail("首个速率应发布 available,实际: \(String(describing: firstRate))")
            return
        }
        let countBeforeToggle = recorder.count

        controller.hide()
        // 让隐藏任务至少启动;它可能停在 stop 挂起点,也可能在睡眠内完整完成,
        // 两种交错都是合法时序,由下面的不变量统一覆盖
        try? await Task.sleep(nanoseconds: 5_000_000)
        controller.show()

        // 无论隐藏任务在哪个阶段执行,最新设置(显示)最终必须获胜:
        // 采样恢复出真实速率
        let deadline = Date().addingTimeInterval(3)
        var resumedRate: MenuBarNetworkRateAvailability?
        while Date() < deadline {
            if let element = recorder.element(at: countBeforeToggle + 2),
               case .available = element {
                resumedRate = element
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard case .available = resumedRate else {
            XCTFail("重开后采样应恢复出真实速率")
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertLessThanOrEqual(
            recorder.hiddenCount,
            1,
            "隐藏至多回写一次;若隐藏任务在重开前已完整执行则恰好一次,被取代则零次"
        )
    }

    // MARK: - 旧订阅已取得元素后发生 hide/show:晚到值不得更新展示

    func test_staleSubscriptionElement_afterHideShow_doesNotUpdateDisplay() async {
        let (controller, recorder) = makeFixture()

        controller.show()
        let firstRate = await awaitElement(recorder, 2)
        guard case .available = firstRate else {
            XCTFail("首个速率应发布 available,实际: \(String(describing: firstRate))")
            return
        }

        // 在不挂起的前提下自旋等待超过两个采样间隔:
        // 旧订阅从流中取得的新元素恢复被排入 MainActor 队列,但尚未执行写入
        let spinDeadline = Date().addingTimeInterval(0.12)
        while Date() < spinDeadline {}

        let countAtToggle = recorder.count

        // 旧订阅仍持有已取得(未写入)的元素;先完整关闭,再重新开启
        controller.hide()
        let hiddenApplied = await awaitHidden(recorder)
        XCTAssertTrue(hiddenApplied, "关闭应完整执行(取消旧订阅并停止会话)")
        controller.show()

        // 让新会话完成预热并恢复速率
        let resumedRate = await awaitElement(recorder, countAtToggle + 2)
        guard case .available = resumedRate else {
            XCTFail("重开后采样应恢复出真实速率,实际: \(String(describing: resumedRate))")
            return
        }

        // 晚到的旧 generation 速率不得写入:
        // 切换后的第一个元素必须是重开时的预热占位,而不是旧会话的 available
        let firstAfterToggle = recorder.element(at: countAtToggle)
        XCTAssertEqual(
            firstAfterToggle,
            .warmingUp,
            "切换后首个写入应是新会话预热占位,实际: \(String(describing: firstAfterToggle))"
        )

        XCTAssertEqual(recorder.hiddenCount, 1, "隐藏恰好回写一次")
    }

    // MARK: - Helpers

    private func counters(in: UInt64, out: UInt64) -> NetworkSampler.Counters {
        NetworkSampler.Counters(
            bytesInByInterface: ["en0": `in`],
            bytesOutByInterface: ["en0": out]
        )
    }

    private func makeFixture() -> (controller: MenuBarNetworkSamplingController, recorder: TransitionRecorder) {
        let script: [NetworkSampler.Counters?] = (0...8).map {
            counters(in: UInt64($0) * 10_000, out: UInt64($0) * 10_000)
        }
        let scripted = ScriptedCounters(script)
        let sampler = NetworkSampler(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.menubar"),
            countersProvider: scripted.read
        )
        let monitor = MenuBarNetworkRateMonitor(sampler: sampler, interval: 0.05)
        let recorder = TransitionRecorder()
        let controller = MenuBarNetworkSamplingController(
            makeMonitor: { monitor },
            onAvailability: { recorder.record($0) },
            onApplyHidden: { recorder.recordHidden() }
        )
        return (controller, recorder)
    }

    @discardableResult
    private func awaitElement(
        _ recorder: TransitionRecorder,
        _ index: Int,
        timeout: TimeInterval = 3
    ) async -> MenuBarNetworkRateAvailability? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = recorder.element(at: index) { return element }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }

    private func awaitHidden(_ recorder: TransitionRecorder, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if recorder.hiddenCount > 0 { return true }
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

private final class TransitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [MenuBarNetworkRateAvailability] = []
    private var hiddenApplications = 0

    func record(_ element: MenuBarNetworkRateAvailability) {
        lock.lock()
        defer { lock.unlock() }
        elements.append(element)
    }

    func recordHidden() {
        lock.lock()
        defer { lock.unlock() }
        hiddenApplications += 1
    }

    func element(at index: Int) -> MenuBarNetworkRateAvailability? {
        lock.lock()
        defer { lock.unlock() }
        return index < elements.count ? elements[index] : nil
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return elements.count
    }

    var hiddenCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return hiddenApplications
    }
}
