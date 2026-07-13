import XCTest
@testable import Omnipo

final class DefaultClipboardServiceTests: XCTestCase {

    func test_setEnabledBeforeAcknowledgement_failsAndDoesNotStartMonitoring() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = await fixture.service.setEnabled(true)

        guard case .failure(.invalidState(detail: "clipboard-local-storage-notice-unacknowledged")) = result else {
            return XCTFail("Expected unacknowledged enable to fail")
        }
        XCTAssertFalse(fixture.settings.readBool(forKey: .clipboardIsEnabled))
        XCTAssertEqual(fixture.monitorFactory.monitorCount, 0)
        XCTAssertEqual(try fixture.repository.count(), 0)
    }

    func test_acknowledgeLocalStorageNotice_persistsAcknowledgementEnablesAndStartsMonitoring() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let result = await fixture.service.acknowledgeLocalStorageNotice()

        guard case .success = result else {
            return XCTFail("Expected acknowledgement to succeed")
        }
        XCTAssertTrue(fixture.settings.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice))
        XCTAssertTrue(fixture.settings.readBool(forKey: .clipboardIsEnabled))
        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.startCount, 1)
    }

    func test_startMonitoring_usesConfiguredPollingInterval() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true) { settings in
            settings.writeClipboardPollingIntervalSeconds(0.4)
        }
        defer { fixture.cleanup() }

        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.lastInterval, 0.4)
    }

    func test_setEnabledFalse_stopsMonitoringAndPreventsPersistence() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true)
        defer { fixture.cleanup() }
        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.startCount, 1)

        let result = await fixture.service.setEnabled(false)
        fixture.service.handleClipboardChange(ClipboardChange(
            changeCount: 1,
            capturedContent: capturedPlainText(hash: "disabled")
        ))

        guard case .success = result else {
            return XCTFail("Expected disable to succeed")
        }
        XCTAssertFalse(fixture.settings.readBool(forKey: .clipboardIsEnabled))
        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.stopCount, 1)
        XCTAssertEqual(try fixture.repository.count(), 0)
    }

    func test_setEnabledTrueAfterAcknowledgement_restartsMonitoring() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: false)
        defer { fixture.cleanup() }
        XCTAssertEqual(fixture.monitorFactory.monitorCount, 0)

        let result = await fixture.service.setEnabled(true)

        guard case .success = result else {
            return XCTFail("Expected re-enable to succeed")
        }
        XCTAssertTrue(fixture.settings.readBool(forKey: .clipboardIsEnabled))
        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.startCount, 1)
    }

    func test_repeatedEnableKeepsSingleApplicationWideMonitor() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true)
        defer { fixture.cleanup() }

        _ = await fixture.service.setEnabled(true)
        _ = await fixture.service.setEnabled(true)

        XCTAssertEqual(fixture.monitorFactory.monitorCount, 1)
        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.startCount, 1)
        XCTAssertEqual(fixture.monitorFactory.latestMonitor?.stopCount, 0)
    }

    func test_monitorChangePersistsCapturedContentOnlyAfterAcknowledgedAndEnabled() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true)
        defer { fixture.cleanup() }

        fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
            changeCount: 2,
            capturedContent: capturedPlainText(hash: "hello-hash")
        ))

        let records = try fixture.repository.records(matching: ClipboardQuery())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.contentHash, "hello-hash")
        XCTAssertEqual(records.first?.contentType, .plainText)
        XCTAssertEqual(records.first?.textPreview, "hello")
        XCTAssertEqual(records.first?.sourceApplicationID, "com.example.source")

        let payloads = try fixture.repository.payloads(for: try XCTUnwrap(records.first?.id))
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.format, .plainText)
        XCTAssertTrue(fixture.binaryStore.exists(try XCTUnwrap(payloads.first?.storagePath)))
    }

    func test_monitorChangePersistsAllSupportedContentTypes() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true)
        defer { fixture.cleanup() }

        let samples: [(ClipboardContentType, ClipboardCapturedContent)] = [
            (.plainText, capturedContent(
                hash: "plain-text",
                type: .plainText,
                preview: "plain",
                payloads: [.init(format: .plainText, data: Data("plain".utf8))]
            )),
            (.richText, capturedContent(
                hash: "rtf",
                type: .richText,
                preview: "rich",
                payloads: [
                    .init(format: .rtf, data: Data("{\\rtf1 rich}".utf8)),
                    .init(format: .plainText, data: Data("rich".utf8))
                ]
            )),
            (.html, capturedContent(
                hash: "html",
                type: .html,
                preview: "html",
                payloads: [
                    .init(format: .html, data: Data("<p>html</p>".utf8)),
                    .init(format: .plainText, data: Data("html".utf8))
                ]
            )),
            (.image, capturedContent(
                hash: "image",
                type: .image,
                preview: nil,
                payloads: [.init(format: .image, data: Data([0x01, 0x02, 0x03]))]
            )),
            (.fileURL, capturedContent(
                hash: "file-url",
                type: .fileURL,
                preview: "report.pdf",
                payloads: [
                    .init(format: .fileURLs, data: try JSONEncoder().encode(["/tmp/report.pdf"])),
                    .init(format: .plainText, data: Data("/tmp/report.pdf".utf8))
                ]
            ))
        ]

        for (index, sample) in samples.enumerated() {
            fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
                changeCount: index + 2,
                capturedContent: sample.1
            ))
        }

        let records = try fixture.repository.records(matching: ClipboardQuery(limit: 10))
        XCTAssertEqual(Set(records.map(\.contentType)), Set(samples.map(\.0)))
        XCTAssertEqual(records.count, samples.count)

        for record in records {
            let payloads = try fixture.repository.payloads(for: record.id)
            XCTAssertFalse(payloads.isEmpty)
            for payload in payloads {
                XCTAssertTrue(fixture.binaryStore.exists(payload.storagePath))
            }
        }
    }

    func test_monitorChangePostsHistoryDidChangeAfterPersistence() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true)
        defer { fixture.cleanup() }
        let didPostHistoryChange = expectation(
            forNotification: .clipboardHistoryDidChange,
            object: fixture.service
        )

        fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
            changeCount: 2,
            capturedContent: capturedPlainText(hash: "published")
        ))

        await fulfillment(of: [didPostHistoryChange], timeout: 1.0)
    }

    func test_monitorChange_skipsExcludedApplication() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true) { settings in
            settings.writeClipboardExcludedApplications(["com.example.source"])
        }
        defer { fixture.cleanup() }

        fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
            changeCount: 2,
            capturedContent: capturedPlainText(hash: "excluded-app")
        ))

        XCTAssertEqual(try fixture.repository.count(), 0)
    }

    func test_monitorChange_skipsExcludedPattern() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true) { settings in
            settings.writeClipboardExcludedPatterns(["hello"])
        }
        defer { fixture.cleanup() }

        fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
            changeCount: 2,
            capturedContent: capturedPlainText(hash: "excluded-pattern")
        ))

        XCTAssertEqual(try fixture.repository.count(), 0)
    }

    func test_monitorChange_enforcesMaxRecords() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true) { settings in
            settings.writeClipboardMaxRecords(2)
        }
        defer { fixture.cleanup() }

        for index in 0..<3 {
            fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
                changeCount: index + 2,
                capturedContent: capturedPlainText(hash: "record-\(index)")
            ))
        }

        let records = try fixture.repository.records(matching: ClipboardQuery(limit: 10))
        XCTAssertEqual(records.count, 2)
    }

    func test_monitorChange_enforcesRetentionDays() async throws {
        let fixture = try makeFixture(acknowledged: true, enabled: true) { settings in
            settings.writeClipboardRetentionDays(1)
        }
        defer { fixture.cleanup() }
        let oldItem = ClipboardItem(
            contentHash: "old",
            contentType: .plainText,
            textPreview: "old",
            createdAt: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60),
            updatedAt: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)
        )
        let savedOldItem = try fixture.repository.insert(oldItem)
        let oldStoragePath = try fixture.binaryStore.write(
            Data("old".utf8),
            for: savedOldItem.id,
            format: .plainText
        )
        _ = try fixture.repository.insertPayload(ClipboardBinaryPayload(
            recordID: savedOldItem.id,
            format: .plainText,
            storagePath: oldStoragePath,
            fileSize: 3,
            createdAt: oldItem.createdAt
        ))

        fixture.monitorFactory.latestMonitor?.emit(ClipboardChange(
            changeCount: 2,
            capturedContent: capturedPlainText(hash: "new")
        ))

        XCTAssertEqual(try fixture.repository.count(), 1)
        XCTAssertFalse(fixture.binaryStore.exists(oldStoragePath))
    }

    func test_unavailableService_reportsUnavailableAndRejectsEveryOperation() async {
        let expectedError = UnavailableClipboardService.initializationError
        let service = UnavailableClipboardService()
        let itemID = UUID()
        let availability = await service.availability
        let isEnabled = await service.isEnabled
        let hasAcknowledgedNotice = await service.hasAcknowledgedLocalStorageNotice

        XCTAssertEqual(availability, .unavailable(expectedError))
        XCTAssertFalse(isEnabled)
        XCTAssertFalse(hasAcknowledgedNotice)

        let results: [AppError?] = [
            failure(from: await service.setEnabled(true)),
            failure(from: await service.acknowledgeLocalStorageNotice()),
            failure(from: await service.records(matching: ClipboardQuery())),
            failure(from: await service.setFavorite(true, for: itemID)),
            failure(from: await service.delete(itemID)),
            failure(from: await service.copyToPasteboard(itemID)),
            failure(from: await service.copyAndPaste(itemID)),
            failure(from: await service.copyAndPaste(itemID, targetProcessIdentifier: 42))
        ]

        XCTAssertEqual(results, Array(repeating: expectedError, count: results.count))
    }

    func test_factory_applicationSupportFailure_returnsUnavailableServiceAndSafeLog() async {
        let settings = makeFactorySettings()
        let logger = RecordingClipboardInitializationLogger()

        let service = await MainActor.run {
            DependencyContainer.makeClipboardService(
                settings: settings,
                logging: logger,
                locationProvider: {
                    throw AppError.unknown(code: "/Users/private/clipboard-location")
                }
            )
        }

        await assertUnavailableFactoryResult(
            service,
            logger: logger,
            expectedStage: "application-support"
        )
        XCTAssertTrue(settings.readBool(forKey: .reopenLastDestination))
    }

    func test_factory_sqliteFailure_returnsUnavailableServiceAndSafeLog() async {
        let settings = makeFactorySettings()
        let logger = RecordingClipboardInitializationLogger()
        let location = ClipboardStorageLocation(
            rootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("omnipo-clipboard-factory-unused-\(UUID().uuidString)")
        )

        let service = await MainActor.run {
            DependencyContainer.makeClipboardService(
                settings: settings,
                logging: logger,
                locationProvider: { location },
                databaseProvider: { _ in
                    throw AppError.systemFailure(code: "sqlite-test-failure")
                }
            )
        }

        await assertUnavailableFactoryResult(service, logger: logger, expectedStage: "sqlite")
    }

    func test_factory_schemaFailure_returnsUnavailableServiceAndSafeLog() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-clipboard-factory-schema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeFactorySettings()
        let logger = RecordingClipboardInitializationLogger()
        let location = ClipboardStorageLocation(rootDirectory: root)
        let database = try ClipboardDatabase(location: location)

        let service = await MainActor.run {
            DependencyContainer.makeClipboardService(
                settings: settings,
                logging: logger,
                locationProvider: { location },
                databaseProvider: { _ in database },
                databaseInitializer: { _ in
                    throw AppError.dataCorrupted(detail: "schema-test-failure")
                }
            )
        }

        await assertUnavailableFactoryResult(service, logger: logger, expectedStage: "schema")
    }

    private func failure<T>(from result: Result<T, AppError>) -> AppError? {
        guard case .failure(let error) = result else { return nil }
        return error
    }

    private func makeFactorySettings() -> UserDefaultsSettingsService {
        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.clipboard.factory.\(UUID().uuidString)"
        )
        settings.write(true, forKey: .reopenLastDestination)
        return settings
    }

    private func assertUnavailableFactoryResult(
        _ service: any ClipboardService,
        logger: RecordingClipboardInitializationLogger,
        expectedStage: String
    ) async {
        let availability = await service.availability
        XCTAssertEqual(
            availability,
            .unavailable(UnavailableClipboardService.initializationError)
        )
        XCTAssertEqual(logger.events.count, 1)
        XCTAssertEqual(logger.events.first?.stableCode, "E_CLIPBOARD_STORAGE_INIT")
        XCTAssertEqual(logger.events.first?.sanitizedContext, [
            "stage": expectedStage,
            "reason": "initialization-failed"
        ])
        XCTAssertFalse(logger.events.description.contains("/Users/"))
        XCTAssertFalse(logger.events.description.contains("schema-test-failure"))
        XCTAssertFalse(logger.events.description.contains("sqlite-test-failure"))
    }

    private func capturedPlainText(hash: String) -> ClipboardCapturedContent {
        capturedContent(
            hash: hash,
            type: .plainText,
            preview: "hello",
            payloads: [
                ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))
            ]
        )
    }

    private func capturedContent(
        hash: String,
        type: ClipboardContentType,
        preview: String?,
        payloads: [ClipboardCapturedPayload]
    ) -> ClipboardCapturedContent {
        ClipboardCapturedContent(
            contentHash: hash,
            contentType: type,
            textPreview: preview,
            sourceApplicationID: "com.example.source",
            payloads: payloads
        )
    }

    private func makeFixture(
        acknowledged: Bool = false,
        enabled: Bool = false,
        configureSettings: (UserDefaultsSettingsService) -> Void = { _ in }
    ) throws -> ClipboardServiceFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-clipboard-service-\(UUID().uuidString)", isDirectory: true)
        let location = ClipboardStorageLocation(rootDirectory: root)
        let database = try ClipboardDatabase(location: location)
        try database.initialize()
        let repository = ClipboardRepository(database: database)
        let binaryStore = BinaryContentStore(rootDirectory: location.binaryPayloadsDirectory)
        let settings = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.clipboard.service.\(UUID().uuidString)")
        settings.write(acknowledged, forKey: .clipboardHasAcknowledgedLocalStorageNotice)
        settings.write(enabled, forKey: .clipboardIsEnabled)
        configureSettings(settings)

        let pasteController = ClipboardPasteController(
            repository: repository,
            binaryStore: binaryStore,
            writer: NoopClipboardContentWriter()
        )
        let monitorFactory = RecordingClipboardMonitorFactory()
        let service = DefaultClipboardService(
            settings: settings,
            repository: repository,
            binaryStore: binaryStore,
            pasteController: pasteController,
            monitorFactory: { handler in
                monitorFactory.make(handler: handler)
            }
        )

        return ClipboardServiceFixture(
            root: root,
            settings: settings,
            repository: repository,
            binaryStore: binaryStore,
            monitorFactory: monitorFactory,
            service: service
        )
    }
}

private struct ClipboardServiceFixture {
    let root: URL
    let settings: UserDefaultsSettingsService
    let repository: ClipboardRepository
    let binaryStore: BinaryContentStore
    let monitorFactory: RecordingClipboardMonitorFactory
    let service: DefaultClipboardService

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class RecordingClipboardMonitorFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var monitors: [RecordingClipboardMonitor] = []

    var latestMonitor: RecordingClipboardMonitor? {
        lock.lock()
        defer { lock.unlock() }
        return monitors.last
    }

    var monitorCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return monitors.count
    }

    func make(handler: @escaping ClipboardMonitor.Handler) -> any ClipboardMonitoring {
        let monitor = RecordingClipboardMonitor(handler: handler)
        lock.lock()
        monitors.append(monitor)
        lock.unlock()
        return monitor
    }
}

private final class RecordingClipboardMonitor: ClipboardMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: ClipboardMonitor.Handler
    private var starts = 0
    private var stops = 0
    private var interval: TimeInterval?

    init(handler: @escaping ClipboardMonitor.Handler) {
        self.handler = handler
    }

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    var lastInterval: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return interval
    }

    func start(interval: TimeInterval) {
        lock.lock()
        starts += 1
        self.interval = interval
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stops += 1
        lock.unlock()
    }

    func emit(_ change: ClipboardChange) {
        handler(change)
    }
}

private final class NoopClipboardContentWriter: ClipboardContentWriting, @unchecked Sendable {
    func write(_ payloads: [ClipboardCapturedPayload], as contentType: ClipboardContentType) throws {}
}

private final class RecordingClipboardInitializationLogger: LoggingService, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [LogEvent] = []

    var events: [LogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func log(_ event: LogEvent) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }
}
