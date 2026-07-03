import XCTest
@testable import Omnipo

final class ClipboardMonitorTests: XCTestCase {

    func test_pollOnce_ignoresInitialChangeCount() throws {
        let provider = FakeClipboardChangeCountProvider(changeCount: 10)
        let recorder = ClipboardChangeRecorder()
        let monitor = ClipboardMonitor(provider: provider, contentReader: nil, sourceApplicationProvider: nil) { change in
            recorder.append(change)
        }

        XCTAssertNil(try monitor.pollOnce())
        XCTAssertTrue(recorder.changes.isEmpty)
    }

    func test_pollOnce_emitsWhenChangeCountAdvances() throws {
        let provider = FakeClipboardChangeCountProvider(changeCount: 10)
        let recorder = ClipboardChangeRecorder()
        let monitor = ClipboardMonitor(provider: provider, contentReader: nil, sourceApplicationProvider: nil) { change in
            recorder.append(change)
        }

        provider.changeCount = 11
        let change = try monitor.pollOnce()

        XCTAssertEqual(change, ClipboardChange(changeCount: 11))
        XCTAssertEqual(recorder.changes, [ClipboardChange(changeCount: 11)])
    }

    func test_pollOnce_emitsOnlyDistinctChangeCounts() throws {
        let provider = FakeClipboardChangeCountProvider(changeCount: 1)
        let recorder = ClipboardChangeRecorder()
        let monitor = ClipboardMonitor(provider: provider, contentReader: nil, sourceApplicationProvider: nil) { change in
            recorder.append(change)
        }

        provider.changeCount = 2
        try monitor.pollOnce()
        try monitor.pollOnce()
        provider.changeCount = 3
        try monitor.pollOnce()

        XCTAssertEqual(recorder.changes, [
            ClipboardChange(changeCount: 2),
            ClipboardChange(changeCount: 3)
        ])
    }

    func test_start_pollsRepeatedlyUntilStopped() {
        let provider = FakeClipboardChangeCountProvider(changeCount: 1)
        let expectation = expectation(description: "monitor emits change")
        let monitor = ClipboardMonitor(provider: provider, contentReader: nil, sourceApplicationProvider: nil) { change in
            if change.changeCount == 2 {
                expectation.fulfill()
            }
        }

        monitor.start(interval: 0.01)
        provider.changeCount = 2
        wait(for: [expectation], timeout: 1.0)
        monitor.stop()
    }

    func test_pollOnce_readsContentWhenChangeCountAdvances() throws {
        let provider = FakeClipboardChangeCountProvider(changeCount: 1)
        let content = ClipboardCapturedContent(
            contentHash: "hash",
            contentType: .plainText,
            textPreview: "hello",
            payloads: [ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))]
        )
        let reader = FakeClipboardContentReader(content: content)
        let monitor = ClipboardMonitor(
            provider: provider,
            contentReader: reader,
            sourceApplicationProvider: nil
        ) { _ in }

        provider.changeCount = 2
        let change = try monitor.pollOnce()

        XCTAssertEqual(change?.capturedContent, content)
        XCTAssertEqual(reader.readCount, 1)
    }

    func test_pollOnce_attachesSourceApplicationIDToCapturedContent() throws {
        let provider = FakeClipboardChangeCountProvider(changeCount: 1)
        let content = ClipboardCapturedContent(
            contentHash: "hash",
            contentType: .plainText,
            textPreview: "hello",
            payloads: [ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))]
        )
        let reader = FakeClipboardContentReader(content: content)
        let sourceProvider = FakeClipboardSourceApplicationProvider(result: .success("com.example.Source"))
        let monitor = ClipboardMonitor(
            provider: provider,
            contentReader: reader,
            sourceApplicationProvider: sourceProvider
        ) { _ in }

        provider.changeCount = 2
        let change = try monitor.pollOnce()

        XCTAssertEqual(change?.capturedContent?.sourceApplicationID, "com.example.Source")
        XCTAssertEqual(sourceProvider.readCount, 1)
    }

    func test_pollOnce_sourceApplicationFailureDoesNotFailChange() throws {
        let provider = FakeClipboardChangeCountProvider(changeCount: 1)
        let content = ClipboardCapturedContent(
            contentHash: "hash",
            contentType: .plainText,
            textPreview: "hello",
            payloads: [ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))]
        )
        let reader = FakeClipboardContentReader(content: content)
        let sourceProvider = FakeClipboardSourceApplicationProvider(result: .failure(.systemFailure(code: "boom")))
        let monitor = ClipboardMonitor(
            provider: provider,
            contentReader: reader,
            sourceApplicationProvider: sourceProvider
        ) { _ in }

        provider.changeCount = 2
        let change = try monitor.pollOnce()

        XCTAssertEqual(change?.capturedContent?.contentHash, "hash")
        XCTAssertNil(change?.capturedContent?.sourceApplicationID)
        XCTAssertEqual(sourceProvider.readCount, 1)
    }
}

private final class FakeClipboardChangeCountProvider: ClipboardChangeCountProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedChangeCount: Int

    init(changeCount: Int) {
        self.storedChangeCount = changeCount
    }

    var changeCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedChangeCount
        }
        set {
            lock.lock()
            storedChangeCount = newValue
            lock.unlock()
        }
    }
}

private final class ClipboardChangeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedChanges: [ClipboardChange] = []

    var changes: [ClipboardChange] {
        lock.lock()
        defer { lock.unlock() }
        return storedChanges
    }

    func append(_ change: ClipboardChange) {
        lock.lock()
        storedChanges.append(change)
        lock.unlock()
    }
}

private final class FakeClipboardContentReader: ClipboardContentReading, @unchecked Sendable {
    private let lock = NSLock()
    private let content: ClipboardCapturedContent?
    private var storedReadCount = 0

    init(content: ClipboardCapturedContent?) {
        self.content = content
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReadCount
    }

    func readCurrentContent() throws -> ClipboardCapturedContent? {
        lock.lock()
        storedReadCount += 1
        lock.unlock()
        return content
    }
}

private final class FakeClipboardSourceApplicationProvider: ClipboardSourceApplicationProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<String?, AppError>
    private var storedReadCount = 0

    init(result: Result<String?, AppError>) {
        self.result = result
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReadCount
    }

    func sourceApplicationID() throws -> String? {
        lock.lock()
        storedReadCount += 1
        lock.unlock()
        return try result.get()
    }
}
