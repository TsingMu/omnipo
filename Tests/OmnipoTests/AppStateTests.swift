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

    func test_refreshLargeFiles_ignoresLateResultFromSupersededLoad() async {
        let stale: LargeFileAvailability = .available([
            LargeFileRecord(
                name: "stale.bin",
                displayPath: "/stale",
                sizeBytes: 1,
                sourceVolumeIdentifier: "v"
            )
        ])
        let fresh: LargeFileAvailability = .available([
            LargeFileRecord(
                name: "fresh.bin",
                displayPath: "/fresh",
                sizeBytes: 2,
                sourceVolumeIdentifier: "v"
            )
        ])
        let service = OutOfOrderDiskUsageService(stale: stale, fresh: fresh)
        let state = AppState(diskUsageService: service)

        let first = Task { await state.loadLargeFilesIfNeeded() }
        await service.waitUntilFirstLargeFileLoadStarts()
        await state.refreshLargeFiles()
        await service.finishFirstLargeFileLoad()
        await first.value

        XCTAssertEqual(state.largeFileAvailability, fresh)
    }

    // MARK: - Persisted Root Authorization

    func test_authorizedRoot_withoutBookmark_isNotConfigured() {
        let settings = makeAuthorizationSettings()
        let manager = AuthorizedRootManager(settings: settings)

        XCTAssertEqual(manager.authorizationAvailability, .notConfigured)
        XCTAssertNil(manager.currentRoot())
    }

    func test_authorizedRoot_validBookmark_isAvailable() {
        let settings = makeAuthorizationSettings(bookmark: Data([0x01]))
        let root = URL(fileURLWithPath: "/private/tmp/authorized-root")
        let manager = makeAuthorizedRootManager(
            settings: settings,
            resolved: .init(url: root, isStale: false)
        )

        XCTAssertEqual(manager.currentRoot(), root)
        XCTAssertEqual(manager.authorizationAvailability, .available(validRootCount: 1))
    }

    func test_authorizationAvailability_probeReleasesScopeImmediately() {
        let settings = makeAuthorizationSettings(bookmark: Data([0x01]))
        let root = URL(fileURLWithPath: "/private/tmp/authorization-probe-root")
        var startCount = 0
        var stopCount = 0
        let manager = AuthorizedRootManager(
            settings: settings,
            bookmarkResolver: { _ in .init(url: root, isStale: false) },
            scopeStarter: { _ in
                startCount += 1
                return true
            },
            scopeStopper: { _ in stopCount += 1 },
            bookmarkCreator: { _ in Data([0x02]) }
        )

        XCTAssertEqual(manager.authorizationAvailability, .available(validRootCount: 1))
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 1)
    }

    func test_authorizedRoot_staleBookmark_refreshesPersistedData() {
        let original = Data([0x01])
        let refreshed = Data([0x02])
        let settings = makeAuthorizationSettings(bookmark: original)
        let root = URL(fileURLWithPath: "/private/tmp/stale-root")
        let manager = makeAuthorizedRootManager(
            settings: settings,
            resolved: .init(url: root, isStale: true),
            refreshedBookmark: refreshed
        )

        XCTAssertEqual(manager.currentRoot(), root)
        XCTAssertEqual(settings.readLargeFileRootBookmark(), refreshed)
        XCTAssertEqual(manager.authorizationAvailability, .available(validRootCount: 1))
    }

    func test_authorizedRoot_invalidBookmark_preservesRecoveryState() {
        let bookmark = Data([0xCA, 0xFE])
        let settings = makeAuthorizationSettings(bookmark: bookmark)
        let logger = RecordingDiskAuthorizationLogger()
        let manager = AuthorizedRootManager(
            settings: settings,
            bookmarkResolver: { _ in throw AuthorizationTestError.invalidBookmark },
            scopeStarter: { _ in true },
            scopeStopper: { _ in },
            bookmarkCreator: { _ in Data() },
            logger: logger
        )

        XCTAssertNil(manager.currentRoot())
        XCTAssertEqual(
            manager.authorizationAvailability,
            .reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 1,
                reason: .bookmarkInvalid
            )
        )
        XCTAssertEqual(settings.readLargeFileRootBookmark(), bookmark)
        XCTAssertEqual(logger.events.count, 1)
        XCTAssertEqual(logger.events.first?.stableCode, "W_AUTH_BOOKMARK_INVALID")
        XCTAssertEqual(logger.events.first?.sanitizedContext["validCount"], "0")
        XCTAssertEqual(logger.events.first?.sanitizedContext["invalidCount"], "1")
        XCTAssertFalse(logger.events.description.contains("/Users/"))
        XCTAssertFalse(logger.events.description.contains(bookmark.base64EncodedString()))
    }

    func test_authorizedRoot_scopeDenied_requiresReauthorization() {
        let bookmark = Data([0x01])
        let settings = makeAuthorizationSettings(bookmark: bookmark)
        let manager = makeAuthorizedRootManager(
            settings: settings,
            resolved: .init(url: URL(fileURLWithPath: "/private/tmp/denied-root"), isStale: false),
            canStartScope: false
        )

        XCTAssertNil(manager.currentRoot())
        XCTAssertEqual(
            manager.authorizationAvailability,
            .reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 1,
                reason: .accessDenied
            )
        )
        XCTAssertEqual(settings.readLargeFileRootBookmark(), bookmark)
    }

    func test_authorizationRecoveryReasons_haveStableSafePresentation() {
        let codes = DirectoryAuthorizationRecoveryReason.allCases.map(\.stableCode)
        XCTAssertEqual(Set(codes).count, codes.count)
        for reason in DirectoryAuthorizationRecoveryReason.allCases {
            XCTAssertFalse(reason.userDescription.isEmpty)
            XCTAssertFalse(reason.userDescription.contains("/Users/"))
            XCTAssertFalse(reason.userDescription.contains("bookmarkData"))
        }
    }

    private func makeAuthorizationSettings(bookmark: Data? = nil) -> UserDefaultsSettingsService {
        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.authorized-root.\(UUID().uuidString)"
        )
        settings.writeLargeFileRootBookmark(bookmark)
        return settings
    }

    private func makeAuthorizedRootManager(
        settings: UserDefaultsSettingsService,
        resolved: ResolvedDirectoryBookmark,
        refreshedBookmark: Data = Data([0x03]),
        canStartScope: Bool = true
    ) -> AuthorizedRootManager {
        AuthorizedRootManager(
            settings: settings,
            bookmarkResolver: { _ in resolved },
            scopeStarter: { _ in canStartScope },
            scopeStopper: { _ in },
            bookmarkCreator: { _ in refreshedBookmark }
        )
    }
}

private enum AuthorizationTestError: Error {
    case invalidBookmark
}

private final class RecordingDiskAuthorizationLogger: LoggingService, @unchecked Sendable {
    private(set) var events: [LogEvent] = []
    func log(_ event: LogEvent) { events.append(event) }
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

private actor OutOfOrderDiskUsageService: DiskUsageService {
    private let stale: LargeFileAvailability
    private let fresh: LargeFileAvailability
    private var largeFileCallCount = 0
    private var firstContinuation: CheckedContinuation<LargeFileAvailability, Never>?
    private var firstStarted = false
    private var firstStartWaiter: CheckedContinuation<Void, Never>?

    init(stale: LargeFileAvailability, fresh: LargeFileAvailability) {
        self.stale = stale
        self.fresh = fresh
    }

    func loadStartupVolumeCapacity(trigger: DiskCapacityLoadTrigger) async -> DiskCapacityAvailability {
        .unavailable(reason: .unknown)
    }

    func loadLargeFiles(limit: Int, trigger: LargeFileLoadTrigger) async -> LargeFileAvailability {
        largeFileCallCount += 1
        if largeFileCallCount == 1 {
            firstStarted = true
            firstStartWaiter?.resume()
            firstStartWaiter = nil
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        return fresh
    }

    func waitUntilFirstLargeFileLoadStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiter = continuation
        }
    }

    func finishFirstLargeFileLoad() {
        firstContinuation?.resume(returning: stale)
        firstContinuation = nil
    }
}
