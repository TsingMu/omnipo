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
