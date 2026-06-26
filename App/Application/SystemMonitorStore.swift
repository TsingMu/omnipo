import Foundation
import Observation

/// 系统监控页面状态容器。
///
/// 负责系统监控页面的快照状态、激活生命周期和流订阅。
@MainActor
@Observable
public final class SystemMonitorStore {
    public private(set) var snapshot: SystemMetricSnapshot?
    public private(set) var generation: UInt64 = 0
    public private(set) var isActive = false
    public private(set) var intervalSeconds: Double

    private let service: any SystemMonitorService
    private let settings: (any SettingsService)?
    private var subscriptionTask: Task<Void, Never>?

    public init(
        service: any SystemMonitorService,
        settings: (any SettingsService)? = nil,
        intervalSeconds: Double = SystemMonitorInterval.defaultSeconds
    ) {
        self.service = service
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
    }

    public func deactivate() async {
        guard isActive else { return }
        advanceGeneration()
        deactivateSubscription()
        await service.stop()
    }

    public func refresh() async {
        let expectedGeneration = generation
        let refreshed = await service.refreshOnce()
        applySnapshot(refreshed, expectedGeneration: expectedGeneration)
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

    private func deactivateSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        isActive = false
    }

    @discardableResult
    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }
}
