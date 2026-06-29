import Foundation
import Observation

/// 系统监控页面状态容器。
///
/// 负责系统监控页面的快照状态、激活生命周期和流订阅。
@MainActor
@Observable
public final class SystemMonitorStore {
    public var selectedTab: SystemMonitorTab = .overview
    public private(set) var snapshot: SystemMetricSnapshot?
    public private(set) var appUsage: AppUsageAvailability = .idle
    public var sortedAppUsageRecords: [AppUsageRecord] {
        appUsage.records.sortedByDefaultUsage()
    }
    public private(set) var generation: UInt64 = 0
    public private(set) var isActive = false
    public private(set) var intervalSeconds: Double

    private let service: any SystemMonitorService
    private let appUsageSampler: (any AppUsageSampling)?
    private let settings: (any SettingsService)?
    private var subscriptionTask: Task<Void, Never>?
    private var appUsageTask: Task<Void, Never>?

    public init(
        service: any SystemMonitorService,
        appUsageSampler: (any AppUsageSampling)? = nil,
        settings: (any SettingsService)? = nil,
        intervalSeconds: Double = SystemMonitorInterval.defaultSeconds
    ) {
        self.service = service
        self.appUsageSampler = appUsageSampler
        self.settings = settings
        self.intervalSeconds = SystemMonitorInterval.clampOrFallback(intervalSeconds)
    }

    public func activate() async {
        if isActive {
            deactivateSubscription()
        }
        isActive = true
        let expectedGeneration = advanceGeneration()

        await service.start(intervalSeconds: intervalSeconds)
        let stream = await service.updates()

        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await nextSnapshot in stream {
                if Task.isCancelled {
                    return
                }
                await MainActor.run {
                    self.applySnapshot(
                        nextSnapshot,
                        expectedGeneration: expectedGeneration
                    )
                }
            }
        }
        startAppUsageSampling(expectedGeneration: expectedGeneration)
    }

    public func deactivate() async {
        guard isActive else { return }
        advanceGeneration()
        deactivateSubscription()
        cancelAppUsageSampling()
        await service.stop()
    }

    public func refresh() async {
        let expectedGeneration = generation
        let appUsageRefreshTask = Task {
            await appUsageSampler?.sampleAppUsage()
        }
        let refreshed = await service.refreshOnce()
        applySnapshot(refreshed, expectedGeneration: expectedGeneration)
        if let refreshedAppUsage = await appUsageRefreshTask.value {
            applyAppUsage(refreshedAppUsage, expectedGeneration: expectedGeneration)
        }
    }

    public func setInterval(_ newValue: Double) async {
        let clamped = SystemMonitorInterval.clampOrFallback(newValue)
        guard clamped != intervalSeconds else { return }
        let wasActive = isActive
        intervalSeconds = clamped
        settings?.writeSystemMonitorIntervalSeconds(clamped)
        advanceGeneration()

        guard wasActive else { return }
        deactivateSubscription()
        cancelAppUsageSampling()
        await service.stop()
        await activate()
    }

    private func applySnapshot(
        _ nextSnapshot: SystemMetricSnapshot,
        expectedGeneration: UInt64
    ) {
        guard isActive, expectedGeneration == generation else {
            return
        }
        snapshot = nextSnapshot
    }

    private func applyAppUsage(
        _ nextAppUsage: AppUsageAvailability,
        expectedGeneration: UInt64
    ) {
        guard isActive, expectedGeneration == generation else {
            return
        }
        appUsage = nextAppUsage.sortedByDefaultUsage()
    }

    private func deactivateSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        isActive = false
    }

    private func startAppUsageSampling(expectedGeneration: UInt64) {
        guard let appUsageSampler else { return }
        appUsage = .loading
        appUsageTask?.cancel()
        let intervalSeconds = self.intervalSeconds
        appUsageTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let sampledAppUsage = await appUsageSampler.sampleAppUsage()
                if Task.isCancelled {
                    return
                }
                await MainActor.run {
                    self.applyAppUsage(
                        sampledAppUsage,
                        expectedGeneration: expectedGeneration
                    )
                }

                let sleepNanoseconds = UInt64(max(1, intervalSeconds) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    return
                }
            }
        }
    }

    private func cancelAppUsageSampling() {
        appUsageTask?.cancel()
        appUsageTask = nil
    }

    @discardableResult
    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }
}
