import XCTest
@testable import Omnipo

@MainActor
final class AppStateTests: XCTestCase {

    func test_loadIfNeeded_readsOnlyFromIdleState() async {
        let service = MockDiskUsageService(
            responses: [
                .available(.init(
                    volumeName: "Macintosh HD",
                    volumeIdentifier: "fs-1",
                    usedBytes: 40,
                    availableBytes: 60,
                    totalBytes: 100
                ))
            ]
        )
        let state = AppState(diskUsageService: service)

        await state.loadStartupVolumeCapacityIfNeeded()
        await state.loadStartupVolumeCapacityIfNeeded()

        let recordedTriggers = await service.recordedTriggers()
        XCTAssertEqual(recordedTriggers, [.initialLoad])
        guard case .available(let snapshot) = state.startupVolumeCapacity else {
            return XCTFail("expected available snapshot")
        }
        XCTAssertEqual(snapshot.totalBytes, 100)
    }

    func test_refresh_updatesSharedCapacityState() async {
        let first = DiskCapacityAvailability.available(.init(
            volumeName: "Macintosh HD",
            volumeIdentifier: "fs-1",
            usedBytes: 40,
            availableBytes: 60,
            totalBytes: 100
        ))
        let second = DiskCapacityAvailability.available(.init(
            volumeName: "Macintosh HD",
            volumeIdentifier: "fs-1",
            usedBytes: 70,
            availableBytes: 30,
            totalBytes: 100
        ))
        let service = MockDiskUsageService(responses: [first, second])
        let state = AppState(diskUsageService: service)

        await state.loadStartupVolumeCapacityIfNeeded()
        await state.refreshStartupVolumeCapacity()

        let recordedTriggers = await service.recordedTriggers()
        XCTAssertEqual(recordedTriggers, [.initialLoad, .userRefresh])
        XCTAssertEqual(state.startupVolumeCapacity, second)
    }

    // MARK: - Large Files

    func test_loadLargeFilesIfNeeded_startsFromIdle() async {
        let service = MockDiskUsageService(
            largeFileResponses: [
                .available([
                    LargeFileRecord(
                        name: "video.mp4",
                        displayPath: "/Users/x/Movies/video.mp4",
                        sizeBytes: 1_000_000,
                        sourceVolumeIdentifier: "fs-1"
                    )
                ])
            ]
        )
        let state = AppState(diskUsageService: service)

        await state.loadLargeFilesIfNeeded()

        let largeTriggers = await service.recordedLargeFileTriggers()
        XCTAssertEqual(largeTriggers, [.initialLoad])
        guard case .available(let records) = state.largeFileAvailability else {
            return XCTFail("expected available large file list")
        }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "video.mp4")
    }

    func test_loadLargeFilesIfNeeded_skipsWhenNotIdle() async {
        let service = MockDiskUsageService(largeFileResponses: [
            .available([
                LargeFileRecord(
                    name: "a.bin",
                    displayPath: "/a",
                    sizeBytes: 100,
                    sourceVolumeIdentifier: "v"
                )
            ])
        ])
        let state = AppState(diskUsageService: service)

        await state.loadLargeFilesIfNeeded()
        await state.loadLargeFilesIfNeeded()

        let count = await service.recordedLargeFileTriggers().count
        XCTAssertEqual(count, 1, "second call should be a no-op since state is no longer idle")
    }

    func test_refreshLargeFiles_forcesReload() async {
        let first: LargeFileAvailability = .available([
            LargeFileRecord(
                name: "old.bin",
                displayPath: "/old",
                sizeBytes: 100,
                sourceVolumeIdentifier: "v"
            )
        ])
        let second: LargeFileAvailability = .available([
            LargeFileRecord(
                name: "new.bin",
                displayPath: "/new",
                sizeBytes: 200,
                sourceVolumeIdentifier: "v"
            )
        ])
        let service = MockDiskUsageService(largeFileResponses: [first, second])
        let state = AppState(diskUsageService: service)

        await state.loadLargeFilesIfNeeded()
        await state.refreshLargeFiles()

        let triggers = await service.recordedLargeFileTriggers()
        XCTAssertEqual(triggers, [.initialLoad, .userRefresh])
        XCTAssertEqual(state.largeFileAvailability, second)
    }

    func test_refreshLargeFiles_unavailableStatePropagates() async {
        let service = MockDiskUsageService(largeFileResponses: [
            .unavailable(reason: .permissionLimited)
        ])
        let state = AppState(diskUsageService: service)

        await state.loadLargeFilesIfNeeded()

        XCTAssertEqual(state.largeFileAvailability, .unavailable(reason: .permissionLimited))
    }
}

private actor MockDiskUsageService: DiskUsageService {
    private var capacityResponses: [DiskCapacityAvailability]
    private var largeFileResponses: [LargeFileAvailability]
    private var capacityTriggers: [DiskCapacityLoadTrigger] = []
    private var largeFileTriggers: [LargeFileLoadTrigger] = []

    init(
        responses: [DiskCapacityAvailability] = [],
        largeFileResponses: [LargeFileAvailability] = []
    ) {
        self.capacityResponses = responses
        self.largeFileResponses = largeFileResponses
    }

    func loadStartupVolumeCapacity(trigger: DiskCapacityLoadTrigger) async -> DiskCapacityAvailability {
        capacityTriggers.append(trigger)
        if capacityResponses.isEmpty {
            return .unavailable(reason: .unknown)
        }
        return capacityResponses.removeFirst()
    }

    func loadLargeFiles(
        limit: Int,
        trigger: LargeFileLoadTrigger
    ) async -> LargeFileAvailability {
        largeFileTriggers.append(trigger)
        if largeFileResponses.isEmpty {
            return .unavailable(reason: .scanNotStarted)
        }
        return largeFileResponses.removeFirst()
    }

    func recordedTriggers() -> [DiskCapacityLoadTrigger] {
        capacityTriggers
    }

    func recordedLargeFileTriggers() -> [LargeFileLoadTrigger] {
        largeFileTriggers
    }
}
