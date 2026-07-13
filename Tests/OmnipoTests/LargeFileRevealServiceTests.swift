import XCTest
@testable import Omnipo

@MainActor
final class LargeFileRevealServiceTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/private/tmp/omnipo-reveal-root")

    func test_successRevealsCurrentItemAndReleasesScope() {
        let harness = makeHarness()
        let record = makeRecord(path: root.appendingPathComponent("item.bin").path)
        let result = harness.service.reveal(record: record, currentRecords: [record])

        XCTAssertEqual(result, .success)
        XCTAssertEqual(harness.startCount(), 1)
        XCTAssertEqual(harness.stopCount(), 1)
        XCTAssertEqual(harness.revealedURLs().count, 1)
    }

    func test_staleResultDoesNotAcquireAuthorization() {
        let harness = makeHarness()
        let record = makeRecord(path: root.appendingPathComponent("item.bin").path)
        XCTAssertEqual(harness.service.reveal(record: record, currentRecords: []), .failure(.staleResult))
        XCTAssertEqual(harness.startCount(), 0)
        XCTAssertEqual(harness.stopCount(), 0)
    }

    func test_outsideRootAndMissingItemReleaseScope() {
        let outsideHarness = makeHarness()
        let outside = makeRecord(path: "/private/tmp/outside.bin")
        XCTAssertEqual(
            outsideHarness.service.reveal(record: outside, currentRecords: [outside]),
            .failure(.outsideAuthorizedRoot)
        )
        XCTAssertEqual(outsideHarness.stopCount(), 1)

        let missingHarness = makeHarness(fileExists: false)
        let missing = makeRecord(path: root.appendingPathComponent("missing.bin").path)
        XCTAssertEqual(
            missingHarness.service.reveal(record: missing, currentRecords: [missing]),
            .failure(.missingItem)
        )
        XCTAssertEqual(missingHarness.stopCount(), 1)
    }

    func test_scopeDenialReturnsSafeFailureWithoutFinderCall() {
        let harness = makeHarness(canStartScope: false)
        let record = makeRecord(path: root.appendingPathComponent("item.bin").path)
        XCTAssertEqual(
            harness.service.reveal(record: record, currentRecords: [record]),
            .failure(.authorizationUnavailable)
        )
        XCTAssertEqual(harness.startCount(), 1)
        XCTAssertEqual(harness.stopCount(), 0)
        XCTAssertTrue(harness.revealedURLs().isEmpty)
    }

    func test_unexpectedFinderFailureReleasesScopeAndLogsNoPath() {
        let logger = RecordingRevealLogger()
        let harness = makeHarness(revealError: RevealTestError.failed, logger: logger)
        let sensitivePath = root.appendingPathComponent("private-name.bin").path
        let record = makeRecord(path: sensitivePath)

        XCTAssertEqual(
            harness.service.reveal(record: record, currentRecords: [record]),
            .failure(.unexpected)
        )
        XCTAssertEqual(harness.stopCount(), 1)
        XCTAssertFalse(logger.events.description.contains(sensitivePath))
        XCTAssertFalse(logger.events.description.contains("private-name.bin"))
        XCTAssertEqual(logger.events.last?.stableCode, "LARGE_FILE_REVEAL_UNEXPECTED")
    }

    private func makeRecord(path: String) -> LargeFileRecord {
        LargeFileRecord(
            name: URL(fileURLWithPath: path).lastPathComponent,
            displayPath: path,
            sizeBytes: 1,
            sourceVolumeIdentifier: "test-volume"
        )
    }

    private func makeHarness(
        canStartScope: Bool = true,
        fileExists: Bool = true,
        revealError: Error? = nil,
        logger: (any LoggingService)? = nil
    ) -> RevealHarness {
        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.reveal.\(UUID().uuidString)"
        )
        settings.writeLargeFileRootBookmark(Data([0x01]))
        var starts = 0
        var stops = 0
        var revealed: [URL] = []
        let manager = AuthorizedRootManager(
            settings: settings,
            bookmarkResolver: { [self] _ in .init(url: root, isStale: false) },
            scopeStarter: { _ in starts += 1; return canStartScope },
            scopeStopper: { _ in stops += 1 },
            bookmarkCreator: { _ in Data([0x02]) }
        )
        let service = LargeFileRevealService(
            rootManager: manager,
            fileExists: { _ in fileExists },
            revealInFinder: { urls in
                revealed = urls
                if let revealError { throw revealError }
            },
            logger: logger
        )
        return RevealHarness(
            service: service,
            startCount: { starts },
            stopCount: { stops },
            revealedURLs: { revealed }
        )
    }
}

@MainActor
private struct RevealHarness {
    let service: LargeFileRevealService
    let startCount: () -> Int
    let stopCount: () -> Int
    let revealedURLs: () -> [URL]
}

private enum RevealTestError: Error { case failed }

private final class RecordingRevealLogger: LoggingService, @unchecked Sendable {
    private(set) var events: [LogEvent] = []
    func log(_ event: LogEvent) { events.append(event) }
}
