import XCTest
@testable import Omnipo

@MainActor
final class SystemMonitorStoreTests: XCTestCase {

    func test_selectedTabDefaultsToOverviewAndCanChange() {
        let service = MockSystemMonitorService()
        let store = SystemMonitorStore(service: service)

        XCTAssertEqual(store.selectedTab, .overview)

        store.selectedTab = .memory

        XCTAssertEqual(store.selectedTab, .memory)
    }

    func test_appUsageDefaultsToIdleAndExposesSortedRecords() async {
        let service = MockSystemMonitorService()
        let sampler = MockAppUsageSampler()
        let store = SystemMonitorStore(service: service, appUsageSampler: sampler)
        let low = makeAppUsageRecord(name: "Low", usageAmount: 1)
        let high = makeAppUsageRecord(name: "High", usageAmount: 9)

        XCTAssertEqual(store.appUsage, .idle)
        XCTAssertEqual(store.sortedAppUsageRecords, [])

        await store.activate()
        await sampler.push(.available(.init(records: [low, high])))
        await waitUntil { store.sortedAppUsageRecords.map(\.displayName) == ["High", "Low"] }

        XCTAssertEqual(store.sortedAppUsageRecords, [high, low])
    }

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

    func test_activateStartsAppUsageSampling() async {
        let service = MockSystemMonitorService()
        let sampler = MockAppUsageSampler()
        let store = SystemMonitorStore(service: service, appUsageSampler: sampler)
        let record = makeAppUsageRecord(name: "Sampler", usageAmount: 3)

        await store.activate()
        await sampler.waitForSampleCount(1)
        await sampler.push(.available(.init(records: [record])))
        await waitUntil { store.sortedAppUsageRecords == [record] }
        let sampleCount = await sampler.sampleCount()

        XCTAssertEqual(store.sortedAppUsageRecords, [record])
        XCTAssertEqual(sampleCount, 1)
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

    func test_deactivateCancelsAppUsageSamplingAndIgnoresLateResult() async {
        let service = MockSystemMonitorService()
        let sampler = MockAppUsageSampler()
        let store = SystemMonitorStore(service: service, appUsageSampler: sampler)
        let late = makeAppUsageRecord(name: "Late", usageAmount: 7)

        await store.activate()
        await sampler.waitForSampleCount(1)
        await store.deactivate()
        await sampler.push(.available(.init(records: [late])))
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.sortedAppUsageRecords, [])
        XCTAssertTrue(store.appUsage.isLoading)
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
        await service.pushRetired(stale)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.intervalSeconds, 3)
        XCTAssertEqual(store.generation, 3)
        XCTAssertEqual(store.snapshot, first, "切换 interval 后旧 generation 的流不应继续写回")

        let startedIntervals = await service.startedIntervals()
        XCTAssertEqual(startedIntervals, [SystemMonitorInterval.defaultSeconds, 3])
    }

    func test_setIntervalInvalidatesOldAppUsageResult() async {
        let service = MockSystemMonitorService()
        let sampler = MockAppUsageSampler()
        let store = SystemMonitorStore(
            service: service,
            appUsageSampler: sampler,
            intervalSeconds: 5
        )
        let stale = makeAppUsageRecord(name: "Stale", usageAmount: 10)
        let fresh = makeAppUsageRecord(name: "Fresh", usageAmount: 1)

        await store.activate()
        await sampler.waitForSampleCount(1)
        await store.setInterval(3)
        await sampler.waitForSampleCount(2)
        await sampler.push(.available(.init(records: [stale])))
        await sampler.push(.available(.init(records: [fresh])))
        await waitUntil { store.sortedAppUsageRecords == [fresh] }

        XCTAssertEqual(store.sortedAppUsageRecords, [fresh])
        XCTAssertEqual(store.generation, 3)
    }

    func test_setIntervalClampsInvalidValueToDefault() async {
        let service = MockSystemMonitorService()
        let store = SystemMonitorStore(service: service, intervalSeconds: 4)

        await store.setInterval(-1)

        XCTAssertEqual(store.intervalSeconds, SystemMonitorInterval.defaultSeconds)
        XCTAssertEqual(store.generation, 1)
    }

    func test_switchingTabDoesNotRestartMetricOrAppUsageSampling() async {
        let service = MockSystemMonitorService()
        let sampler = MockAppUsageSampler()
        let store = SystemMonitorStore(service: service, appUsageSampler: sampler)
        let record = makeAppUsageRecord(name: "Running", usageAmount: 2)

        await store.activate()
        await sampler.waitForSampleCount(1)
        await sampler.push(.available(.init(records: [record])))
        await waitUntil { store.sortedAppUsageRecords == [record] }

        store.selectedTab = .cpu
        try? await Task.sleep(nanoseconds: 50_000_000)
        let startedIntervals = await service.startedIntervals()
        let sampleCount = await sampler.sampleCount()

        XCTAssertEqual(startedIntervals, [SystemMonitorInterval.defaultSeconds])
        XCTAssertEqual(sampleCount, 1)
    }

    func test_refreshUpdatesMetricSnapshotAndAppUsage() async {
        let service = MockSystemMonitorService()
        let sampler = MockAppUsageSampler()
        let store = SystemMonitorStore(service: service, appUsageSampler: sampler)
        let initial = makeAppUsageRecord(name: "Initial", usageAmount: 1)
        let refreshed = makeAppUsageRecord(name: "Refreshed", usageAmount: 5)

        await store.activate()
        await sampler.waitForSampleCount(1)
        await sampler.push(.available(.init(records: [initial])))
        await waitUntil { store.sortedAppUsageRecords == [initial] }

        let refreshTask = Task {
            await store.refresh()
        }
        await sampler.waitForSampleCount(2)
        await sampler.push(.available(.init(records: [refreshed])))
        await refreshTask.value

        XCTAssertEqual(store.snapshot?.disk?.snapshot?.volumeIdentifier, "refresh")
        XCTAssertEqual(store.sortedAppUsageRecords, [refreshed])
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

    private func makeAppUsageRecord(
        name: String,
        usageAmount: Double
    ) -> AppUsageRecord {
        .init(
            displayName: name,
            bundleIdentifier: "test.\(name)",
            memoryBytes: Int64(usageAmount * 1_000),
            usageAmount: usageAmount
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

private actor MockAppUsageSampler: AppUsageSampling {
    private var pendingResults: [AppUsageAvailability] = []
    private var resultContinuations: [CheckedContinuation<AppUsageAvailability, Never>] = []
    private var countContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    private var count = 0

    func sampleAppUsage() async -> AppUsageAvailability {
        count += 1
        resumeCountContinuations()
        if !pendingResults.isEmpty {
            return pendingResults.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            resultContinuations.append(continuation)
        }
    }

    func push(_ availability: AppUsageAvailability) {
        if resultContinuations.isEmpty {
            pendingResults.append(availability)
        } else {
            let continuation = resultContinuations.removeFirst()
            continuation.resume(returning: availability)
        }
    }

    func sampleCount() -> Int {
        count
    }

    func waitForSampleCount(_ expectedCount: Int) async {
        guard count < expectedCount else { return }
        await withCheckedContinuation { continuation in
            countContinuations.append((expectedCount, continuation))
        }
    }

    private func resumeCountContinuations() {
        let ready = countContinuations.filter { $0.0 <= count }
        countContinuations.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
    }
}

private actor MockSystemMonitorService: SystemMonitorService {
    private var continuation: AsyncStream<SystemMetricSnapshot>.Continuation?
    private var retiredContinuations: [AsyncStream<SystemMetricSnapshot>.Continuation] = []
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
        if let continuation {
            retiredContinuations.append(continuation)
        }
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

    func pushRetired(_ snapshot: SystemMetricSnapshot) {
        retiredContinuations.last?.yield(snapshot)
    }

    func startedIntervals() -> [Double] {
        started
    }

    func stopCallCount() -> Int {
        stopCountValue
    }
}
