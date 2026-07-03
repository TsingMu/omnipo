import Foundation

public protocol ClipboardMonitoring: AnyObject, Sendable {
    func start(interval: TimeInterval)
    func stop()
}

extension ClipboardMonitor: ClipboardMonitoring {}

public final class DefaultClipboardService: ClipboardService, @unchecked Sendable {
    public typealias MonitorFactory = @Sendable (@escaping ClipboardMonitor.Handler) -> any ClipboardMonitoring

    private let settings: any SettingsService
    private let repository: ClipboardRepository
    private let binaryStore: BinaryContentStore
    private let pasteController: ClipboardPasteController
    private let monitorFactory: MonitorFactory
    private let lock = NSLock()
    private var monitor: (any ClipboardMonitoring)?

    public init(
        settings: any SettingsService,
        repository: ClipboardRepository,
        binaryStore: BinaryContentStore,
        pasteController: ClipboardPasteController,
        monitorFactory: @escaping MonitorFactory = { handler in
            ClipboardMonitor(handler: handler)
        }
    ) {
        self.settings = settings
        self.repository = repository
        self.binaryStore = binaryStore
        self.pasteController = pasteController
        self.monitorFactory = monitorFactory
        startMonitoringIfAllowed()
    }

    deinit {
        stopMonitoring()
    }

    public var isEnabled: Bool {
        get async { settings.readBool(forKey: .clipboardIsEnabled) }
    }

    public var hasAcknowledgedLocalStorageNotice: Bool {
        get async { settings.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice) }
    }

    public func setEnabled(_ isEnabled: Bool) async -> Result<Void, AppError> {
        do {
            if isEnabled {
                guard settings.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice) else {
                    throw AppError.invalidState(detail: "clipboard-local-storage-notice-unacknowledged")
                }
                settings.write(true, forKey: .clipboardIsEnabled)
                startMonitoringIfAllowed()
            } else {
                settings.write(false, forKey: .clipboardIsEnabled)
                stopMonitoring()
            }
            return .success(())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.unknown(code: String(describing: error)))
        }
    }

    public func acknowledgeLocalStorageNotice() async -> Result<Void, AppError> {
        settings.write(true, forKey: .clipboardHasAcknowledgedLocalStorageNotice)
        settings.write(true, forKey: .clipboardIsEnabled)
        startMonitoringIfAllowed()
        return .success(())
    }

    public func records(matching query: ClipboardQuery) async -> Result<[ClipboardItem], AppError> {
        runCatching {
            try repository.records(matching: query)
        }
    }

    public func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        runCatching {
            _ = try repository.setFavorite(isFavorite, for: itemID)
        }
    }

    public func delete(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        runCatching {
            _ = try repository.softDelete(itemID)
        }
    }

    public func copyToPasteboard(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        pasteController.copyToPasteboard(itemID)
    }

    public func copyAndPaste(_ itemID: ClipboardItem.ID) async -> Result<ClipboardPasteOutcome, AppError> {
        pasteController.copyAndPaste(itemID)
    }

    internal func handleClipboardChange(_ change: ClipboardChange) {
        guard settings.readBool(forKey: .clipboardIsEnabled),
              settings.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice),
              let capturedContent = change.capturedContent else {
            return
        }
        do {
            try persist(capturedContent)
        } catch {
            // Clipboard capture is best-effort; the next pasteboard tick can still succeed.
        }
    }

    private func persist(_ capturedContent: ClipboardCapturedContent) throws {
        let now = Date()
        let item = ClipboardItem(
            contentHash: capturedContent.contentHash,
            contentType: capturedContent.contentType,
            textPreview: capturedContent.textPreview,
            sourceApplicationID: capturedContent.sourceApplicationID,
            createdAt: now,
            updatedAt: now
        )
        let savedItem = try repository.insert(item)
        for payload in capturedContent.payloads {
            let storagePath = try binaryStore.write(
                payload.data,
                for: savedItem.id,
                format: payload.format
            )
            _ = try repository.insertPayload(ClipboardBinaryPayload(
                recordID: savedItem.id,
                format: payload.format,
                storagePath: storagePath,
                fileSize: payload.data.count,
                createdAt: now
            ))
        }
    }

    private func startMonitoringIfAllowed() {
        guard settings.readBool(forKey: .clipboardIsEnabled),
              settings.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }

        let newMonitor = monitorFactory { [weak self] change in
            self?.handleClipboardChange(change)
        }
        monitor = newMonitor
        newMonitor.start(interval: 0.8)
    }

    private func stopMonitoring() {
        lock.lock()
        let current = monitor
        monitor = nil
        lock.unlock()
        current?.stop()
    }

    private func runCatching<T>(_ body: () throws -> T) -> Result<T, AppError> {
        do {
            return .success(try body())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.unknown(code: String(describing: error)))
        }
    }
}
