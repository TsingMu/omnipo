import XCTest
@testable import Omnipo

final class DiskUsageServiceTests: XCTestCase {

    func test_convenienceLoad_usesInitialLoadTrigger() async {
        let service = RecordingDiskUsageService()

        _ = await service.loadStartupVolumeCapacity()

        let triggers = await service.recordedTriggers()
        XCTAssertEqual(triggers, [.initialLoad])
    }

    func test_convenienceRefresh_usesUserRefreshTrigger() async {
        let service = RecordingDiskUsageService()

        _ = await service.refreshStartupVolumeCapacity()

        let triggers = await service.recordedTriggers()
        XCTAssertEqual(triggers, [.userRefresh])
    }

    func test_explicitTrigger_allowsCallerToDifferentiateIntent() async {
        let service = RecordingDiskUsageService()

        _ = await service.loadStartupVolumeCapacity(trigger: .initialLoad)
        _ = await service.loadStartupVolumeCapacity(trigger: .userRefresh)

        let triggers = await service.recordedTriggers()
        XCTAssertEqual(triggers, [.initialLoad, .userRefresh])
    }
}

private actor RecordingDiskUsageService: DiskUsageService {
    private var triggers: [DiskCapacityLoadTrigger] = []

    func loadStartupVolumeCapacity(
        trigger: DiskCapacityLoadTrigger
    ) async -> DiskCapacityAvailability {
        triggers.append(trigger)
        return .unavailable(reason: .metadataNotReady)
    }

    func loadLargeFiles(
        limit: Int,
        trigger: LargeFileLoadTrigger
    ) async -> LargeFileAvailability {
        .unavailable(reason: .scanNotStarted)
    }

    func recordedTriggers() -> [DiskCapacityLoadTrigger] {
        triggers
    }
}
