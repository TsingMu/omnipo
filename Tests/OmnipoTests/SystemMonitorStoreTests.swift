import XCTest
@testable import Omnipo

@MainActor
final class SystemMonitorStoreTests: XCTestCase {

    func test_activateSubscribesAndAppliesIncomingSnapshot() async {
        let service = MockSystemMonitorService()
        let store = SystemMonitorStore(service: service)
        let snapshot = makeSnapshot(id: "activate")

        await store.activate()
        await service.push(snapshot)
        await waitUntil { store.snapshot == snapshot }

        XCTAssertTrue(store.isActive)
        XCTAssertEqual(store.generation, 1)
        XCTAssertEqual(store.snapshot, snapshot)

        let startedIntervals = await service.startedIntervals()
        XCTAssertEqual(startedIntervals, [SystemMonitorInterval.defaultSeconds])
    }

    func test_deactivateStopsUpdatesAndMarksInactive() async {
        let service = MockSystemMonitorService()
        let store = SystemMonitorStore(service: service)
        let first = makeSnapshot(id: "before-stop")
        let second = makeSnapshot(id: "after-stop")

        await store.activate()
        await service.push(first)
        await waitUntil { store.snapshot == first }
        await store.deactivate()
        await service.push(second)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(store.isActive)
        XCTAssertEqual(store.snapshot, first, "deactivate 后不应再接收后续 snapshot")

        let stopCount = await service.stopCallCount()
        XCTAssertEqual(stopCount, 1)
    }

    func test_setIntervalAdvancesGenerationAndInvalidatesOldStream() async {
        let service = MockSystemMonitorService()
        let store = SystemMonitorStore(service: service)
        let first = makeSnapshot(id: "before-interval-change")
        let stale = makeSnapshot(id: "stale")

        await store.activate()
        await service.push(first)
        await waitUntil { store.snapshot == first }

        await store.setInterval(3)
        await service.push(stale)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.intervalSeconds, 3)
        XCTAssertEqual(store.generation, 3)
        XCTAssertEqual(store.snapshot, first, "切换 interval 后旧 generation 的流不应继续写回")

        let startedIntervals = await service.startedIntervals()
        XCTAssertEqual(startedIntervals, [SystemMonitorInterval.defaultSeconds, 3])
    }

    func test_setIntervalClampsInvalidValueToDefault() async {
        let service = MockSystemMonitorService()
        let store = SystemMonitorStore(service: service, intervalSeconds: 4)

        await store.setInterval(-1)

        XCTAssertEqual(store.intervalSeconds, SystemMonitorInterval.defaultSeconds)
        XCTAssertEqual(store.generation, 1)
    }

    private func makeSnapshot(id: String) -> SystemMetricSnapshot {
        .init(
            cpu: .unavailable(reason: .warmup),
            memory: .unavailable(reason: .unknown),
            energy: .unavailable(reason: .noBattery),
            disk: .available(.init(
                volumeName: "Macintosh HD \(id)",
                volumeIdentifier: id,
                usedBytes: 40,
                availableBytes: 60,
                totalBytes: 100
            )),
            network: .unavailable(reason: .unknown)
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 500_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while !condition() {
            if ContinuousClock.now >= deadline {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private actor MockSystemMonitorService: SystemMonitorService {
    private var continuation: AsyncStream<SystemMetricSnapshot>.Continuation?
    private var stream: AsyncStream<SystemMetricSnapshot>
    private var started: [Double] = []
    private var stopCountValue = 0

    init() {
        let (stream, continuation) = Self.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func start(intervalSeconds: Double) async {
        if continuation == nil {
            let (stream, continuation) = Self.makeStream()
            self.stream = stream
            self.continuation = continuation
        }
        started.append(intervalSeconds)
    }

    private static func makeStream() -> (
        AsyncStream<SystemMetricSnapshot>,
        AsyncStream<SystemMetricSnapshot>.Continuation
    ) {
        let (stream, continuation) = AsyncStream<SystemMetricSnapshot>.makeStream()
        return (stream, continuation)
    }

    func stop() async {
        stopCountValue += 1
        continuation?.finish()
        continuation = nil
    }

    func updates() async -> AsyncStream<SystemMetricSnapshot> {
        stream
    }

    func refreshOnce() async -> SystemMetricSnapshot {
        .init(
            cpu: .unavailable(reason: .warmup),
            memory: .unavailable(reason: .unknown),
            energy: .unavailable(reason: .noBattery),
            disk: .available(.init(
                volumeName: "Refresh",
                volumeIdentifier: "refresh",
                usedBytes: 10,
                availableBytes: 90,
                totalBytes: 100
            )),
            network: .unavailable(reason: .unknown)
        )
    }

    func push(_ snapshot: SystemMetricSnapshot) {
        continuation?.yield(snapshot)
    }

    func startedIntervals() -> [Double] {
        started
    }

    func stopCallCount() -> Int {
        stopCountValue
    }
}
