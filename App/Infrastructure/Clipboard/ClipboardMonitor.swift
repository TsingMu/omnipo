import AppKit
import Foundation

public struct ClipboardChange: Sendable, Hashable {
    public let changeCount: Int
    public let capturedContent: ClipboardCapturedContent?

    public init(changeCount: Int, capturedContent: ClipboardCapturedContent? = nil) {
        self.changeCount = changeCount
        self.capturedContent = capturedContent
    }
}

public protocol ClipboardChangeCountProviding: AnyObject, Sendable {
    var changeCount: Int { get }
}

public final class SystemClipboardChangeCountProvider: ClipboardChangeCountProviding, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }
}

/// Polls the system pasteboard change counter and reports distinct changes.
public final class ClipboardMonitor: @unchecked Sendable {
    public typealias Handler = @Sendable (ClipboardChange) -> Void

    private let provider: any ClipboardChangeCountProviding
    private let contentReader: (any ClipboardContentReading)?
    private let sourceApplicationProvider: (any ClipboardSourceApplicationProviding)?
    private let queue: DispatchQueue
    private let handler: Handler
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastObservedChangeCount: Int

    public init(
        provider: any ClipboardChangeCountProviding = SystemClipboardChangeCountProvider(),
        contentReader: (any ClipboardContentReading)? = SystemClipboardContentReader(),
        sourceApplicationProvider: (any ClipboardSourceApplicationProviding)? = SystemClipboardSourceApplicationProvider(),
        queue: DispatchQueue = DispatchQueue(label: "com.qing.omnipo.clipboard.monitor", qos: .utility),
        handler: @escaping Handler
    ) {
        self.provider = provider
        self.contentReader = contentReader
        self.sourceApplicationProvider = sourceApplicationProvider
        self.queue = queue
        self.handler = handler
        self.lastObservedChangeCount = provider.changeCount
    }

    deinit {
        stop()
    }

    public func start(interval: TimeInterval = 0.8) {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }

        lastObservedChangeCount = provider.changeCount
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            do {
                _ = try self?.pollOnce()
            } catch {
                // Content-reading failures are isolated to the current tick.
            }
        }
        timer = source
        source.resume()
    }

    public func stop() {
        lock.lock()
        let source = timer
        timer = nil
        lock.unlock()

        source?.cancel()
    }

    @discardableResult
    public func pollOnce() throws -> ClipboardChange? {
        let changeCount: Int?
        lock.lock()
        let currentChangeCount = provider.changeCount
        if currentChangeCount == lastObservedChangeCount {
            changeCount = nil
        } else {
            lastObservedChangeCount = currentChangeCount
            changeCount = currentChangeCount
        }
        lock.unlock()

        guard let changeCount else {
            return nil
        }
        let capturedContent = try contentReader?.readCurrentContent()
        let change = ClipboardChange(
            changeCount: changeCount,
            capturedContent: capturedContent?.withSourceApplicationID(safeSourceApplicationID())
        )
        handler(change)
        return change
    }

    private func safeSourceApplicationID() -> String? {
        do {
            return try sourceApplicationProvider?.sourceApplicationID()
        } catch {
            return nil
        }
    }
}
