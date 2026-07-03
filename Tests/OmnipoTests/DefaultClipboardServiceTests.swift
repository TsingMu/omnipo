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

    private func capturedPlainText(hash: String) -> ClipboardCapturedContent {
        ClipboardCapturedContent(
            contentHash: hash,
            contentType: .plainText,
            textPreview: "hello",
            sourceApplicationID: "com.example.source",
            payloads: [
                ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))
            ]
        )
    }

    private func makeFixture(
        acknowledged: Bool = false,
        enabled: Bool = false
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

    func start(interval: TimeInterval) {
        lock.lock()
        starts += 1
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
