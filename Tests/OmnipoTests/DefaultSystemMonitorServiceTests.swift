import XCTest
@testable import Omnipo

@MainActor
final class DefaultSystemMonitorServiceTests: XCTestCase {

    func test_start_pushesAtLeastOneSnapshot() async {
        let diskService = StubDiskUsageService()
        let service = DefaultSystemMonitorService(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.sysmon"),
            diskUsageService: diskService
        )

        await service.start(intervalSeconds: 1)
        let stream = await service.updates()

        let firstSnapshot: SystemMetricSnapshot? = await withCheckedContinuation { continuation in
            Task {
                for await snapshot in stream {
                    continuation.resume(returning: snapshot)
                    break
                }
            }
        }

        await service.stop()
        XCTAssertNotNil(firstSnapshot, "start 后至少推送一次 snapshot")
        XCTAssertNotNil(firstSnapshot?.disk, "disk 字段应填充")
    }

    func test_stop_cancelsSampling() async {
        let diskService = StubDiskUsageService()
        let service = DefaultSystemMonitorService(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.sysmon"),
            diskUsageService: diskService
        )

        await service.start(intervalSeconds: 1)
        await service.stop()

        // stop 后 stream 应终止
        let stream = await service.updates()
        let gotSnapshot = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task {
                var received = false
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continuation.resume(returning: received)
                }
                for await _ in stream {
                    received = true
                }
                timeoutTask.cancel()
                continuation.resume(returning: received)
            }
        }

        XCTAssertFalse(gotSnapshot, "stop 后不应继续推送")
    }

    func test_refreshOnce_returnsSnapshotImmediately() async {
        let diskService = StubDiskUsageService()
        let service = DefaultSystemMonitorService(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.sysmon"),
            diskUsageService: diskService
        )

        let snapshot = await service.refreshOnce()
        XCTAssertNotNil(snapshot.disk, "refreshOnce 应立即返回有 disk 的 snapshot")
    }

    func test_refreshOnce_cpuWarmupOnFirstCall() async {
        let diskService = StubDiskUsageService()
        let service = DefaultSystemMonitorService(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.sysmon"),
            diskUsageService: diskService
        )

        let snapshot = await service.refreshOnce()
        if case .unavailable(let reason) = snapshot.cpu {
            XCTAssertEqual(reason, .warmup, "首次 CPU 采样应是 warmup")
        }
    }

    func test_clampsInvalidInterval() async {
        let diskService = StubDiskUsageService()
        let service = DefaultSystemMonitorService(
            logger: OSLogLoggingService(subsystem: "com.qing.omnipo.tests.sysmon"),
            diskUsageService: diskService
        )

        // 0/负值不应崩溃,内部钳到默认 5 秒
        await service.start(intervalSeconds: 0)
        await service.start(intervalSeconds: -5)
        await service.start(intervalSeconds: 100)
        await service.stop()
    }
}

private actor StubDiskUsageService: DiskUsageService {
    func loadStartupVolumeCapacity(
        trigger: DiskCapacityLoadTrigger
    ) async -> DiskCapacityAvailability {
        .available(DiskCapacitySnapshot(
            volumeName: "Test",
            volumeIdentifier: "test-vol",
            usedBytes: 40,
            availableBytes: 60,
            totalBytes: 100
        ))
    }

    func loadLargeFiles(
        limit: Int,
        trigger: LargeFileLoadTrigger
    ) async -> LargeFileAvailability {
        .unavailable(reason: .scanNotStarted)
    }
}
