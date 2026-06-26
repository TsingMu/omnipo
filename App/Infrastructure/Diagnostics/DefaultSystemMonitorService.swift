import Foundation
import os

/// `SystemMonitorService` 的默认实现。
///
/// 装配 CPU/内存/能耗/磁盘/网络五个采样器,按间隔顺序采样并合并为 `SystemMetricSnapshot`,
/// 通过 `AsyncStream` 推送。支持采样代次(过期结果不推送)、stop 取消任务、refreshOnce 立即采样。
public actor DefaultSystemMonitorService: SystemMonitorService {

    private struct IntervalSampler {
        let cpu: CPUSampler
        let memory: MemorySampler
        let energy: EnergyStatus
        let network: NetworkSampler
    }

    private let logger: any LoggingService
    private let diskUsageService: any DiskUsageService
    private var sampler: IntervalSampler

    private var cpuPrevious: CPUSampler.Ticks?
    private var networkPrevious: NetworkSampler.Previous?

    private var streamContinuation: AsyncStream<SystemMetricSnapshot>.Continuation?
    private var stream: AsyncStream<SystemMetricSnapshot>?

    private var samplingTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(
        logger: any LoggingService,
        diskUsageService: any DiskUsageService
    ) {
        self.logger = logger
        self.diskUsageService = diskUsageService
        self.sampler = IntervalSampler(
            cpu: CPUSampler(logger: logger),
            memory: MemorySampler(logger: logger),
            energy: EnergyStatus(logger: logger),
            network: NetworkSampler(logger: logger)
        )
    }

    public func start(intervalSeconds: Double) async {
        let clamped = SystemMonitorInterval.clampOrFallback(intervalSeconds)
        stopInternal()

        generation &+= 1
        let capturedGeneration = generation

        let (stream, continuation) = AsyncStream<SystemMetricSnapshot>.makeStream()
        self.stream = stream
        self.streamContinuation = continuation

        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snapshot = await self.sampleOnce()
                continuation.yield(snapshot)
                let nanos = UInt64(clamped * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            continuation.finish()
        }
        samplingTask = task
    }

    public func stop() async {
        stopInternal()
    }

    public func updates() async -> AsyncStream<SystemMetricSnapshot> {
        if let stream {
            return stream
        }
        let (newStream, _) = AsyncStream<SystemMetricSnapshot>.makeStream()
        return newStream
    }

    public func refreshOnce() async -> SystemMetricSnapshot {
        await sampleOnce()
    }

    // MARK: - 内部

    private func stopInternal() {
        samplingTask?.cancel()
        samplingTask = nil
        streamContinuation?.finish()
        streamContinuation = nil
        stream = nil
    }

    private func sampleOnce() async -> SystemMetricSnapshot {
        let (cpuAvailability, newCpuTicks) = sampler.cpu.sample(previous: cpuPrevious)
        cpuPrevious = newCpuTicks

        let memoryAvailability = sampler.memory.sample()
        let energyAvailability = sampler.energy.sample()

        let (networkAvailability, newNetworkPrevious) = sampler.network.sample(previous: networkPrevious)
        networkPrevious = newNetworkPrevious

        let diskAvailability = await diskUsageService.loadStartupVolumeCapacity(trigger: .initialLoad)

        return SystemMetricSnapshot(
            cpu: cpuAvailability,
            memory: memoryAvailability,
            energy: energyAvailability,
            disk: diskAvailability,
            network: networkAvailability
        )
    }
}
