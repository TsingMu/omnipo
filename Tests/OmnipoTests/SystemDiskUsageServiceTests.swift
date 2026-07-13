import XCTest
@testable import Omnipo

final class SystemDiskUsageServiceTests: XCTestCase {

    func test_load_mapsMetadataIntoSnapshot() async {
        let logger = RecordingLogger()
        let service = SystemDiskUsageService(
            logger: logger,
            metadataLoader: {
                .init(
                    volumeName: "Macintosh HD",
                    volumeIdentifier: "startup-root",
                    totalBytes: 1_000,
                    availableBytes: 250
                )
            },
            dateProvider: { Date(timeIntervalSince1970: 123) }
        )

        let result = await service.loadStartupVolumeCapacity(trigger: .initialLoad)

        guard case .available(let snapshot) = result else {
            return XCTFail("expected available snapshot")
        }
        XCTAssertEqual(snapshot.volumeName, "Macintosh HD")
        XCTAssertEqual(snapshot.volumeIdentifier, "startup-root")
        XCTAssertEqual(snapshot.totalBytes, 1_000)
        XCTAssertEqual(snapshot.availableBytes, 250)
        XCTAssertEqual(snapshot.usedBytes, 750)
        XCTAssertEqual(snapshot.capturedAt, Date(timeIntervalSince1970: 123))

        let events = logger.events
        XCTAssertEqual(events.last?.stableCode, "I_DISK_CAPACITY_LOADED")
        XCTAssertEqual(events.last?.sanitizedContext["reason"], "success")
    }

    func test_concurrentLoads_shareSingleFlightTask() async {
        let logger = RecordingLogger()
        let counter = InvocationCounter()
        let service = SystemDiskUsageService(
            logger: logger,
            metadataLoader: {
                await counter.increment()
                try? await Task.sleep(nanoseconds: 150_000_000)
                return .init(
                    volumeName: "Macintosh HD",
                    volumeIdentifier: "startup-root",
                    totalBytes: 500,
                    availableBytes: 200
                )
            }
        )

        async let first = service.loadStartupVolumeCapacity(trigger: .initialLoad)
        async let second = service.loadStartupVolumeCapacity(trigger: .userRefresh)
        let firstResult = await first
        let secondResult = await second

        let invocationCount = await counter.value
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(firstResult, secondResult)
        XCTAssertTrue(logger.events.contains { $0.stableCode == "I_DISK_SINGLE_FLIGHT" })
    }

    func test_cocoaFailures_mapToResourceUnavailable() async {
        let logger = RecordingLogger()
        let service = SystemDiskUsageService(
            logger: logger,
            metadataLoader: {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue)
            }
        )

        let result = await service.loadStartupVolumeCapacity(trigger: .initialLoad)

        XCTAssertEqual(result, .unavailable(reason: .resourceUnavailable))
        XCTAssertEqual(logger.events.last?.stableCode, "W_DISK_RESOURCE_UNAVAILABLE")
    }

    func test_typedLoadErrors_mapToStableReasons() async {
        let logger = RecordingLogger()

        let metadataNotReady = SystemDiskUsageService(
            logger: logger,
            metadataLoader: {
                throw SystemDiskUsageService.LoadError.metadataNotReady
            }
        )
        let unsupported = SystemDiskUsageService(
            logger: logger,
            metadataLoader: {
                throw SystemDiskUsageService.LoadError.unsupportedVolume
            }
        )

        let first = await metadataNotReady.loadStartupVolumeCapacity(trigger: .initialLoad)
        let second = await unsupported.loadStartupVolumeCapacity(trigger: .userRefresh)

        XCTAssertEqual(first, .unavailable(reason: .metadataNotReady))
        XCTAssertEqual(second, .unavailable(reason: .unsupportedVolume))
    }

    func test_logs_doNotExposePathsOrUnknownKeys() async {
        let logger = RecordingLogger()
        let service = SystemDiskUsageService(
            logger: logger,
            metadataLoader: {
                .init(
                    volumeName: "Macintosh HD",
                    volumeIdentifier: "startup-root",
                    totalBytes: 100,
                    availableBytes: 50
                )
            }
        )

        _ = await service.loadStartupVolumeCapacity(trigger: .userRefresh)

        guard let event = logger.events.last else {
            return XCTFail("expected log event")
        }
        XCTAssertEqual(event.message, "disk.capacity.loaded")
        XCTAssertEqual(event.sanitizedContext["code"], "I_DISK_CAPACITY_LOADED")
        XCTAssertEqual(event.sanitizedContext["reason"], "success")
        XCTAssertEqual(event.sanitizedContext["trigger"], "userRefresh")
        XCTAssertNil(event.sanitizedContext["path"])
        XCTAssertFalse(event.message.contains("/Users/"))
    }

    func test_largeFileScan_releasesAuthorizedRootsAfterSuccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-large-file-release-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(count: 8).write(to: root.appendingPathComponent("sample.bin"))
        defer { try? FileManager.default.removeItem(at: root) }
        let releases = AsyncInvocationCounter()
        let service = SystemDiskUsageService(
            logger: RecordingLogger(),
            metadataLoader: { Self.metadataFixture },
            largeFileRootsProvider: { [root] },
            largeFileRootsRelease: { await releases.increment() }
        )

        let result = await service.loadLargeFiles(limit: 10, trigger: .initialLoad)

        guard case .available = result else {
            return XCTFail("expected available result")
        }
        let releaseCount = await releases.value
        XCTAssertEqual(releaseCount, 1)
    }

    func test_replacingLargeFileScan_cancelsOldScanAndReleasesBothScopes() async {
        let root = FileManager.default.temporaryDirectory
        let provider = SuspendingLargeFileRootsProvider(root: root)
        let releases = AsyncInvocationCounter()
        let service = SystemDiskUsageService(
            logger: RecordingLogger(),
            metadataLoader: { Self.metadataFixture },
            largeFileRootsProvider: { await provider.roots() },
            largeFileRootsRelease: { await releases.increment() }
        )

        let first = Task {
            await service.loadLargeFiles(limit: 1, trigger: .initialLoad)
        }
        await provider.waitUntilFirstCallStarts()
        let second = Task {
            await service.loadLargeFiles(limit: 1, trigger: .userRefresh)
        }

        _ = await first.value
        _ = await second.value
        let providerCallCount = await provider.callCount
        let releaseCount = await releases.value

        XCTAssertEqual(providerCallCount, 2)
        XCTAssertEqual(releaseCount, 2)
    }

    private static var metadataFixture: SystemDiskUsageService.VolumeMetadata {
        .init(
            volumeName: "Test Volume",
            volumeIdentifier: "test-volume",
            totalBytes: 100,
            availableBytes: 50
        )
    }
}

private final class RecordingLogger: @unchecked Sendable, LoggingService {
    private let lock = NSLock()
    private var storedEvents: [LogEvent] = []

    var events: [LogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    func log(_ event: LogEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor AsyncInvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private actor SuspendingLargeFileRootsProvider {
    let root: URL
    private(set) var callCount = 0
    private var firstCallStarted = false
    private var firstCallWaiter: CheckedContinuation<Void, Never>?

    init(root: URL) {
        self.root = root
    }

    func roots() async -> [URL] {
        callCount += 1
        if callCount == 1 {
            firstCallStarted = true
            firstCallWaiter?.resume()
            firstCallWaiter = nil
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                // 新扫描取消旧 task 后立即返回，让旧 scope 走统一释放路径。
            }
        }
        return [root]
    }

    func waitUntilFirstCallStarts() async {
        guard !firstCallStarted else { return }
        await withCheckedContinuation { continuation in
            firstCallWaiter = continuation
        }
    }
}
