import XCTest
@testable import Omnipo

@MainActor
final class WeChatManagerStoreTests: XCTestCase {

    func test_refresh_loadsResult() async {
        let service = FakeWeChatStorageService(result: .success(makeResult(totalBytes: 100)))
        let store = WeChatManagerStore(service: service)

        await store.refresh()

        guard case .loaded(let result) = store.state else {
            return XCTFail("expected loaded, got \(store.state)")
        }
        XCTAssertEqual(result.totalVisibleBytes, 100)
    }

    func test_refresh_setsFailedOnError() async {
        let service = FakeWeChatStorageService(result: .failure(.systemFailure(code: "wechat_scan_failed")))
        let store = WeChatManagerStore(service: service)

        await store.refresh()

        guard case .failed(let error) = store.state else {
            return XCTFail("expected failed, got \(store.state)")
        }
        XCTAssertEqual(error, .systemFailure(code: "wechat_scan_failed"))
    }

    func test_loadIfNeeded_skipsWhenNotIdle() async {
        let service = FakeWeChatStorageService(result: .success(makeResult(totalBytes: 50)))
        let store = WeChatManagerStore(service: service)
        await store.refresh()
        service.callCount = 0

        await store.loadIfNeeded()

        XCTAssertEqual(service.callCount, 0)
    }

    func test_loadIfNeeded_refreshesWhenIdle() async {
        let service = FakeWeChatStorageService(result: .success(makeResult(totalBytes: 30)))
        let store = WeChatManagerStore(service: service)

        await store.loadIfNeeded()

        XCTAssertEqual(service.callCount, 1)
        guard case .loaded(let result) = store.state else {
            return XCTFail("expected loaded, got \(store.state)")
        }
        XCTAssertEqual(result.totalVisibleBytes, 30)
    }

    func test_cancel_invokesServiceCancel() async {
        let service = FakeWeChatStorageService(result: .success(makeResult(totalBytes: 0)))
        let store = WeChatManagerStore(service: service)

        await store.cancel()

        XCTAssertTrue(service.cancelCalled)
    }

    func test_cancel_keepsCancelledPartialResultInsteadOfLoadingForever() async {
        let partialResult = WeChatStorageScanResult(
            totalVisibleBytes: 40,
            issues: [WeChatStorageIssue(reason: .scanCancelled)]
        )
        let service = CancellableWeChatStorageService(resultAfterCancel: partialResult)
        let store = WeChatManagerStore(service: service)

        let refreshTask = Task { await store.refresh() }
        await service.waitUntilRefreshStarts()
        await store.cancel()
        await refreshTask.value

        guard case .loaded(let result) = store.state else {
            return XCTFail("expected partial loaded result, got \(store.state)")
        }
        XCTAssertEqual(result.totalVisibleBytes, 40)
        XCTAssertTrue(result.issues.contains { $0.reason == .scanCancelled })
        let cancelCalled = await service.wasCancelCalled()
        XCTAssertTrue(cancelCalled)
    }

    func test_replacingRefreshRejectsCancelledResultAndKeepsFreshResult() async {
        let stale = makeResult(totalBytes: 10)
        let fresh = makeResult(totalBytes: 90)
        let service = ReplacingWeChatStorageService(stale: stale, fresh: fresh)
        let store = WeChatManagerStore(service: service)

        let first = Task { await store.refresh() }
        await service.waitUntilFirstRefreshStarts()
        let second = Task { await store.refresh() }
        await first.value
        await second.value

        guard case .loaded(let result) = store.state else {
            return XCTFail("expected fresh loaded result, got \(store.state)")
        }
        let cancelCallCount = await service.cancelCallCount
        XCTAssertEqual(result.totalVisibleBytes, 90)
        XCTAssertEqual(cancelCallCount, 1)
    }

    func test_authorizationManager_restoresAndClearsPersistedRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-wechat-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.wechat.authorization.\(UUID().uuidString)"
        )
        let bookmark = try root.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        settings.writeWeChatStorageRootBookmarks([bookmark])

        let manager = WeChatStorageAuthorizationManager(settings: settings)
        XCTAssertEqual(
            manager.currentRoots().map { $0.standardizedFileURL.path },
            [root.standardizedFileURL.path]
        )

        manager.clearRoots()
        XCTAssertTrue(manager.currentRoots().isEmpty)
        XCTAssertTrue(settings.readWeChatStorageRootBookmarks().isEmpty)
    }

    func test_authorizationManager_partialFailure_preservesInvalidBookmarkAndValidRoot() {
        let validBookmark = Data([0x01])
        let invalidBookmark = Data([0x02])
        let validRoot = URL(fileURLWithPath: "/private/tmp/wechat-valid-root")
        let settings = makeAuthorizationSettings(bookmarks: [validBookmark, invalidBookmark])
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { bookmark in
                guard bookmark == validBookmark else { throw WeChatAuthorizationTestError.invalidBookmark }
                return .init(url: validRoot, isStale: false)
            }
        )

        XCTAssertEqual(manager.currentRoots(), [validRoot])
        XCTAssertEqual(
            manager.authorizationAvailability,
            .reauthorizationRequired(
                validRootCount: 1,
                invalidRootCount: 1,
                reason: .bookmarkInvalid
            )
        )
        XCTAssertEqual(settings.readWeChatStorageRootBookmarks(), [validBookmark, invalidBookmark])
    }

    func test_authorizationManager_allInvalid_reportsRecoveryInsteadOfNotConfigured() {
        let bookmarks = [Data([0x01]), Data([0x02])]
        let settings = makeAuthorizationSettings(bookmarks: bookmarks)
        let logger = RecordingWeChatAuthorizationLogger()
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { _ in throw WeChatAuthorizationTestError.invalidBookmark },
            logger: logger
        )

        XCTAssertTrue(manager.currentRoots().isEmpty)
        XCTAssertEqual(
            manager.authorizationAvailability,
            .reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 2,
                reason: .bookmarkInvalid
            )
        )
        XCTAssertEqual(settings.readWeChatStorageRootBookmarks(), bookmarks)
        XCTAssertEqual(logger.events.count, 1)
        XCTAssertEqual(logger.events.first?.stableCode, "W_AUTH_BOOKMARK_INVALID")
        XCTAssertEqual(logger.events.first?.sanitizedContext["validCount"], "0")
        XCTAssertEqual(logger.events.first?.sanitizedContext["invalidCount"], "2")
        XCTAssertFalse(logger.events.description.contains("/Users/"))
        XCTAssertFalse(logger.events.description.contains(bookmarks[0].base64EncodedString()))
    }

    func test_authorizationManager_staleBookmark_refreshesPersistedData() {
        let staleBookmark = Data([0x01])
        let refreshedBookmark = Data([0x02])
        let root = URL(fileURLWithPath: "/private/tmp/wechat-stale-root")
        let settings = makeAuthorizationSettings(bookmarks: [staleBookmark])
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { _ in .init(url: root, isStale: true) },
            bookmarkCreator: { _ in refreshedBookmark }
        )

        XCTAssertEqual(manager.currentRoots(), [root])
        XCTAssertEqual(settings.readWeChatStorageRootBookmarks(), [refreshedBookmark])
        XCTAssertEqual(manager.authorizationAvailability, .available(validRootCount: 1))
    }

    func test_authorizationManager_scopeDenied_preservesBookmarkAndReportsReason() {
        let bookmark = Data([0x01])
        let settings = makeAuthorizationSettings(bookmarks: [bookmark])
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { _ in
                .init(url: URL(fileURLWithPath: "/private/tmp/wechat-denied-root"), isStale: false)
            },
            scopeStarter: { _ in false }
        )

        XCTAssertTrue(manager.currentRoots().isEmpty)
        XCTAssertEqual(
            manager.authorizationAvailability,
            .reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 1,
                reason: .accessDenied
            )
        )
        XCTAssertEqual(settings.readWeChatStorageRootBookmarks(), [bookmark])
    }

    func test_authorizationManager_duplicateRoots_areDeduplicatedAndScopeIsReleased() {
        let firstBookmark = Data([0x01])
        let duplicateBookmark = Data([0x02])
        let root = URL(fileURLWithPath: "/private/tmp/wechat-duplicate-root")
        let settings = makeAuthorizationSettings(bookmarks: [firstBookmark, duplicateBookmark])
        var stoppedRoots: [URL] = []
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { _ in .init(url: root, isStale: false) },
            scopeStopper: { stoppedRoots.append($0) }
        )

        XCTAssertEqual(manager.currentRoots(), [root])
        XCTAssertEqual(settings.readWeChatStorageRootBookmarks(), [firstBookmark])
        XCTAssertEqual(stoppedRoots, [root])
        XCTAssertEqual(manager.authorizationAvailability, .available(validRootCount: 1))
    }

    func test_authorizationManager_releaseRootsStopsActiveScopesAndAllowsReacquisition() {
        let bookmark = Data([0x01])
        let root = URL(fileURLWithPath: "/private/tmp/wechat-release-root")
        let settings = makeAuthorizationSettings(bookmarks: [bookmark])
        var startCount = 0
        var stopCount = 0
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { _ in .init(url: root, isStale: false) },
            scopeStarter: { _ in
                startCount += 1
                return true
            },
            scopeStopper: { _ in stopCount += 1 }
        )

        XCTAssertEqual(manager.currentRoots(), [root])
        manager.releaseRoots()
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(manager.currentRoots(), [root])
        XCTAssertEqual(startCount, 2)
    }

    func test_authorizationAvailability_probeReleasesAllScopesImmediately() {
        let bookmark = Data([0x01])
        let root = URL(fileURLWithPath: "/private/tmp/wechat-authorization-probe-root")
        let settings = makeAuthorizationSettings(bookmarks: [bookmark])
        var startCount = 0
        var stopCount = 0
        let manager = makeAuthorizationManager(
            settings: settings,
            resolver: { _ in .init(url: root, isStale: false) },
            scopeStarter: { _ in
                startCount += 1
                return true
            },
            scopeStopper: { _ in stopCount += 1 }
        )

        XCTAssertEqual(manager.authorizationAvailability, .available(validRootCount: 1))
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 1)
    }

    func test_sensitiveNamesRequireConsentAndAliasesClearWhenDisabled() async {
        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.wechat.sensitive.\(UUID().uuidString)"
        )
        let authorizationManager = WeChatStorageAuthorizationManager(
            settings: settings,
            sensitiveNamesConsentPrompt: { true }
        )
        let service = FakeWeChatStorageService(result: .success(makeResult(totalBytes: 10)))
        let store = WeChatManagerStore(service: service, authorizationManager: authorizationManager)

        XCTAssertFalse(store.sensitiveNamesEnabled)
        store.setConversationAlias("不应保存", for: "opaque")
        XCTAssertTrue(store.conversationAliases.isEmpty)

        await store.enableSensitiveNames()
        XCTAssertTrue(store.sensitiveNamesEnabled)
        store.setConversationAlias("测试群", for: "opaque")
        XCTAssertEqual(store.conversationAliases["opaque"], "测试群")

        await store.disableSensitiveNames()
        XCTAssertFalse(store.sensitiveNamesEnabled)
        XCTAssertTrue(store.conversationAliases.isEmpty)
    }

    func test_largeFileCandidatesSupportSelectionIgnoreAndRestore() async {
        let first = WeChatLargeFile(id: UUID(), kind: .video, displayName: "视频文件 1", sizeBytes: 200)
        let second = WeChatLargeFile(id: UUID(), kind: .image, displayName: "图片文件 1", sizeBytes: 100)
        let result = WeChatStorageScanResult(largeFiles: [first, second])
        let service = FakeWeChatStorageService(result: .success(result))
        let store = WeChatManagerStore(service: service)
        await store.refresh()

        store.setLargeFileSelection([first.id, second.id], selected: true)
        XCTAssertEqual(store.selectedLargeFileIDs, Set([first.id, second.id]))
        XCTAssertEqual(store.selectedLargeFileBytes(in: result), 300)

        store.ignoreSelectedLargeFiles()
        XCTAssertTrue(store.selectedLargeFileIDs.isEmpty)
        XCTAssertEqual(store.ignoredLargeFileIDs, Set([first.id, second.id]))

        store.setLargeFileSelection(first.id, selected: true)
        XCTAssertTrue(store.selectedLargeFileIDs.isEmpty)

        store.restoreIgnoredLargeFile(first.id)
        store.setLargeFileSelection(first.id, selected: true)
        XCTAssertEqual(store.selectedLargeFileIDs, Set([first.id]))

        store.restoreAllIgnoredLargeFiles()
        XCTAssertTrue(store.ignoredLargeFileIDs.isEmpty)
    }

    func test_refreshPrunesCandidateStateForFilesNoLongerPresent() async {
        let oldFile = WeChatLargeFile(id: UUID(), kind: .video, displayName: "视频文件 1", sizeBytes: 200)
        let newFile = WeChatLargeFile(id: UUID(), kind: .image, displayName: "图片文件 1", sizeBytes: 100)
        let service = FakeWeChatStorageService(result: .success(.init(largeFiles: [oldFile])))
        let store = WeChatManagerStore(service: service)
        await store.refresh()
        store.setLargeFileSelection(oldFile.id, selected: true)

        service.result = .success(.init(largeFiles: [newFile]))
        await store.refresh()

        XCTAssertTrue(store.selectedLargeFileIDs.isEmpty)
        XCTAssertTrue(store.ignoredLargeFileIDs.isEmpty)
    }

    // MARK: - Helpers

    private func makeResult(totalBytes: Int) -> WeChatStorageScanResult {
        WeChatStorageScanResult(totalVisibleBytes: totalBytes)
    }

    private func makeAuthorizationSettings(bookmarks: [Data]) -> UserDefaultsSettingsService {
        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.wechat.authorization.injected.\(UUID().uuidString)"
        )
        settings.writeWeChatStorageRootBookmarks(bookmarks)
        return settings
    }

    private func makeAuthorizationManager(
        settings: UserDefaultsSettingsService,
        resolver: @escaping (Data) throws -> ResolvedDirectoryBookmark,
        bookmarkCreator: @escaping (URL) throws -> Data = { _ in Data([0xFF]) },
        scopeStarter: @escaping (URL) -> Bool = { _ in true },
        scopeStopper: @escaping (URL) -> Void = { _ in },
        logger: (any LoggingService)? = nil
    ) -> WeChatStorageAuthorizationManager {
        WeChatStorageAuthorizationManager(
            settings: settings,
            maximumRootCount: 8,
            sensitiveNamesConsentPrompt: { false },
            bookmarkResolver: resolver,
            scopeStarter: scopeStarter,
            scopeStopper: scopeStopper,
            bookmarkCreator: bookmarkCreator,
            logger: logger
        )
    }
}

private final class FakeWeChatStorageService: WeChatStorageService, @unchecked Sendable {
    var result: Result<WeChatStorageScanResult, AppError>
    var callCount = 0
    private(set) var cancelCalled = false

    init(result: Result<WeChatStorageScanResult, AppError>) {
        self.result = result
    }

    func scan() async -> Result<WeChatStorageScanResult, AppError> {
        callCount += 1
        return result
    }

    func refresh() async -> Result<WeChatStorageScanResult, AppError> {
        callCount += 1
        return result
    }

    func cancel() async {
        cancelCalled = true
    }
}

private enum WeChatAuthorizationTestError: Error {
    case invalidBookmark
}

private final class RecordingWeChatAuthorizationLogger: LoggingService, @unchecked Sendable {
    private(set) var events: [LogEvent] = []
    func log(_ event: LogEvent) { events.append(event) }
}

private actor CancellableWeChatStorageService: WeChatStorageService {
    private let resultAfterCancel: WeChatStorageScanResult
    private var refreshContinuation: CheckedContinuation<Result<WeChatStorageScanResult, AppError>, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var refreshStarted = false
    private var cancelCalled = false

    init(resultAfterCancel: WeChatStorageScanResult) {
        self.resultAfterCancel = resultAfterCancel
    }

    func scan() async -> Result<WeChatStorageScanResult, AppError> {
        await refresh()
    }

    func refresh() async -> Result<WeChatStorageScanResult, AppError> {
        refreshStarted = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func cancel() async {
        cancelCalled = true
        refreshContinuation?.resume(returning: .success(resultAfterCancel))
        refreshContinuation = nil
    }

    func waitUntilRefreshStarts() async {
        guard !refreshStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func wasCancelCalled() -> Bool {
        cancelCalled
    }
}

private actor ReplacingWeChatStorageService: WeChatStorageService {
    private let stale: WeChatStorageScanResult
    private let fresh: WeChatStorageScanResult
    private var refreshCount = 0
    private var firstContinuation: CheckedContinuation<Result<WeChatStorageScanResult, AppError>, Never>?
    private var firstStarted = false
    private var firstStartWaiter: CheckedContinuation<Void, Never>?
    private(set) var cancelCallCount = 0

    init(stale: WeChatStorageScanResult, fresh: WeChatStorageScanResult) {
        self.stale = stale
        self.fresh = fresh
    }

    func scan() async -> Result<WeChatStorageScanResult, AppError> {
        await refresh()
    }

    func refresh() async -> Result<WeChatStorageScanResult, AppError> {
        refreshCount += 1
        if refreshCount == 1 {
            firstStarted = true
            firstStartWaiter?.resume()
            firstStartWaiter = nil
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        return .success(fresh)
    }

    func cancel() async {
        cancelCallCount += 1
        firstContinuation?.resume(returning: .success(stale))
        firstContinuation = nil
    }

    func waitUntilFirstRefreshStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            firstStartWaiter = continuation
        }
    }
}
