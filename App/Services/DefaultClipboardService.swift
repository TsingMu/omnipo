import CoreGraphics
import Foundation
import ImageIO

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
    private let thumbnailGenerator: @Sendable (URL) -> Data?
    private let lock = NSLock()
    private var monitor: (any ClipboardMonitoring)?

    private let thumbnailCache: NSCache<NSUUID, NSData> = {
        let cache = NSCache<NSUUID, NSData>()
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    private let decodingGate = ThumbnailConcurrencyGate(limit: 3)

    public init(
        settings: any SettingsService,
        repository: ClipboardRepository,
        binaryStore: BinaryContentStore,
        pasteController: ClipboardPasteController,
        thumbnailGenerator: (@Sendable (URL) -> Data?)? = nil,
        monitorFactory: @escaping MonitorFactory = { handler in
            ClipboardMonitor(handler: handler)
        }
    ) {
        self.settings = settings
        self.repository = repository
        self.binaryStore = binaryStore
        self.pasteController = pasteController
        self.thumbnailGenerator = thumbnailGenerator ?? { url in
            DefaultClipboardService.makeThumbnailData(from: url)
        }
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

    public func imageThumbnail(for itemID: ClipboardItem.ID) async -> Result<ClipboardImageThumbnail?, AppError> {
        if let cached = thumbnailCache.object(forKey: itemID as NSUUID) {
            return .success(ClipboardImageThumbnail(data: cached as Data))
        }
        await decodingGate.acquire(for: itemID)
        let result: Result<ClipboardImageThumbnail?, AppError>
        if Task.isCancelled {
            result = .failure(.cancelled)
        } else if let cached = thumbnailCache.object(forKey: itemID as NSUUID) {
            result = .success(ClipboardImageThumbnail(data: cached as Data))
        } else {
            result = await produceThumbnail(for: itemID)
        }
        await decodingGate.release(for: itemID)
        return result
    }

    private func produceThumbnail(for itemID: ClipboardItem.ID) async -> Result<ClipboardImageThumbnail?, AppError> {
        if Task.isCancelled {
            return .failure(.cancelled)
        }
        do {
            let payloads = try repository.payloads(for: itemID)
            guard let imagePayload = payloads.first(where: { $0.format == .image }) else {
                return .success(nil)
            }
            let payloadURL = try binaryStore.fileURL(for: imagePayload.storagePath)
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            guard let thumbnailData = thumbnailGenerator(payloadURL) else {
                return .failure(.dataCorrupted(detail: "clipboard-image-decode-failed"))
            }
            thumbnailCache.setObject(
                thumbnailData as NSData,
                forKey: itemID as NSUUID,
                cost: thumbnailData.count
            )
            return .success(ClipboardImageThumbnail(data: thumbnailData))
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.resourceUnavailable(reason: "clipboard-image-payload-unreadable"))
        }
    }

    private static func makeThumbnailData(from url: URL) -> Data? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: ClipboardImageThumbnail.maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return buffer as Data
    }

    public func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        runCatching {
            _ = try repository.setFavorite(isFavorite, for: itemID)
        }
    }

    public func delete(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        thumbnailCache.removeObject(forKey: itemID as NSUUID)
        return runCatching {
            _ = try repository.softDelete(itemID)
        }
    }

    public func copyToPasteboard(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        pasteController.copyToPasteboard(itemID)
    }

    public func copyAndPaste(_ itemID: ClipboardItem.ID) async -> Result<ClipboardPasteOutcome, AppError> {
        await copyAndPaste(itemID, targetProcessIdentifier: nil)
    }

    public func copyAndPaste(
        _ itemID: ClipboardItem.ID,
        targetProcessIdentifier: pid_t?
    ) async -> Result<ClipboardPasteOutcome, AppError> {
        pasteController.copyAndPaste(itemID, targetProcessIdentifier: targetProcessIdentifier)
    }

    internal func handleClipboardChange(_ change: ClipboardChange) {
        guard settings.readBool(forKey: .clipboardIsEnabled),
              settings.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice),
              let capturedContent = change.capturedContent else {
            return
        }
        guard !shouldExclude(capturedContent) else {
            return
        }
        do {
            try persist(capturedContent)
        } catch {
            // Clipboard capture is best-effort; the next pasteboard tick can still succeed.
        }
    }

    private func shouldExclude(_ capturedContent: ClipboardCapturedContent) -> Bool {
        if let sourceApplicationID = capturedContent.sourceApplicationID,
           settings.readClipboardExcludedApplications().contains(sourceApplicationID) {
            return true
        }
        guard let textPreview = capturedContent.textPreview, !textPreview.isEmpty else {
            return false
        }
        return settings.readClipboardExcludedPatterns().contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            let range = NSRange(textPreview.startIndex..., in: textPreview)
            return regex.firstMatch(in: textPreview, range: range) != nil
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
        try enforceStoragePolicy(now: now)
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: self)
    }

    private func enforceStoragePolicy(now: Date) throws {
        let visibleItems = try repository.records(matching: ClipboardQuery(limit: 10_000))
        var itemsToDelete: [ClipboardItem] = []

        let retentionCutoff = now.addingTimeInterval(-settings.readClipboardRetentionDays() * 24 * 60 * 60)
        itemsToDelete.append(contentsOf: visibleItems.filter { $0.updatedAt < retentionCutoff })

        let retainedByDate = visibleItems.filter { $0.updatedAt >= retentionCutoff }
        let maxRecords = Int(settings.readClipboardMaxRecords())
        if retainedByDate.count > maxRecords {
            itemsToDelete.append(contentsOf: retainedByDate.dropFirst(maxRecords))
        }

        let uniqueDateAndCountDeletes = Dictionary(grouping: itemsToDelete, by: \.id)
            .compactMap { $0.value.first }
        for item in uniqueDateAndCountDeletes {
            try deletePayloadFilesAndMetadata(for: item.id)
            _ = try repository.softDelete(item.id)
        }

        try enforceStorageSize()
    }

    private func enforceStorageSize() throws {
        let maxBytes = Int(settings.readClipboardMaxStorageMB() * 1_024 * 1_024)
        var items = try repository.records(matching: ClipboardQuery(limit: 10_000))
        var payloadsByRecord: [ClipboardItem.ID: [ClipboardBinaryPayload]] = [:]
        var totalBytes = 0
        for item in items {
            let payloads = try repository.payloads(for: item.id)
            payloadsByRecord[item.id] = payloads
            totalBytes += payloads.reduce(0) { $0 + $1.fileSize }
        }

        while totalBytes > maxBytes, let item = items.popLast() {
            let payloads = payloadsByRecord[item.id] ?? []
            totalBytes -= payloads.reduce(0) { $0 + $1.fileSize }
            try deletePayloadFilesAndMetadata(for: item.id)
            _ = try repository.softDelete(item.id)
        }
    }

    private func deletePayloadFilesAndMetadata(for itemID: ClipboardItem.ID) throws {
        let payloads = try repository.payloads(for: itemID)
        for payload in payloads {
            try? binaryStore.delete(payload.storagePath)
        }
        try binaryStore.deleteAll(for: itemID)
        _ = try repository.deletePayloads(for: itemID)
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
        newMonitor.start(interval: settings.readClipboardPollingIntervalSeconds())
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

/// Keeps the rest of the application usable when the local clipboard store cannot start.
public final class UnavailableClipboardService: ClipboardService, @unchecked Sendable {
    public static let initializationError = AppError.resourceUnavailable(
        reason: "clipboard-storage-initialization-failed"
    )

    private let error: AppError

    public init(error: AppError = UnavailableClipboardService.initializationError) {
        self.error = error
    }

    public var availability: ClipboardServiceAvailability {
        get async { .unavailable(error) }
    }

    public var isEnabled: Bool {
        get async { false }
    }

    public var hasAcknowledgedLocalStorageNotice: Bool {
        get async { false }
    }

    public func setEnabled(_ isEnabled: Bool) async -> Result<Void, AppError> {
        .failure(error)
    }

    public func acknowledgeLocalStorageNotice() async -> Result<Void, AppError> {
        .failure(error)
    }

    public func records(matching query: ClipboardQuery) async -> Result<[ClipboardItem], AppError> {
        .failure(error)
    }

    public func imageThumbnail(for itemID: ClipboardItem.ID) async -> Result<ClipboardImageThumbnail?, AppError> {
        .failure(error)
    }

    public func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        .failure(error)
    }

    public func delete(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        .failure(error)
    }

    public func copyToPasteboard(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError> {
        .failure(error)
    }

    public func copyAndPaste(
        _ itemID: ClipboardItem.ID,
        targetProcessIdentifier: pid_t?
    ) async -> Result<ClipboardPasteOutcome, AppError> {
        .failure(error)
    }
}

/// Bounds the number of image thumbnails decoded at once, so a freshly opened
/// list of image records cannot trigger concurrent disk reads and decode spikes.
/// Permits are handed off to waiters in FIFO order; a cancelled waiter still
/// resumes (then bails out cooperatively) so permits are never stranded.
private actor ThumbnailConcurrencyGate {
    private struct Waiter {
        let itemID: ClipboardItem.ID
        let continuation: CheckedContinuation<Void, Never>
    }

    private let limit: Int
    private var available: Int
    private var activeItemIDs: Set<ClipboardItem.ID> = []
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
        self.available = self.limit
    }

    func acquire(for itemID: ClipboardItem.ID) async {
        if available > 0, !activeItemIDs.contains(itemID) {
            available -= 1
            activeItemIDs.insert(itemID)
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(Waiter(itemID: itemID, continuation: continuation))
        }
    }

    func release(for itemID: ClipboardItem.ID) {
        guard activeItemIDs.remove(itemID) != nil else { return }
        available = min(limit, available + 1)

        while available > 0,
              let nextIndex = waiters.firstIndex(where: { !activeItemIDs.contains($0.itemID) }) {
            let next = waiters.remove(at: nextIndex)
            available -= 1
            activeItemIDs.insert(next.itemID)
            next.continuation.resume()
        }
    }
}
