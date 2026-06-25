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
