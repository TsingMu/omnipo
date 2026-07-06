import XCTest
import AppKit
@testable import Omnipo

@MainActor
final class LauncherCoordinatorTests: XCTestCase {

    func test_executeInline_failurePublishesTransientError() async {
        let store = LauncherStore(service: FakeSearchService())
        let coordinator = makeCoordinator(
            store: store,
            resultExecutor: FakeResultExecutor(result: .failure(.resourceUnavailable(reason: "offline")))
        )
        let result = SearchResult(
            kind: .command,
            title: "失败结果",
            subtitle: nil,
            matchScore: 100,
            sourceIdentifier: "command:test",
            iconDescriptor: .systemSymbol(name: "bolt"),
            executionPayload: .launcherCommand(LauncherCommand.openClipboard.rawValue)
        )

        coordinator.executeInline(result)
        await waitFor(store) { $0.transientError != nil }

        XCTAssertEqual(store.transientError, .resourceUnavailable(reason: "offline"))
    }

    func test_executeInline_successKeepsTransientErrorEmpty() async {
        let store = LauncherStore(service: FakeSearchService())
        let coordinator = makeCoordinator(
            store: store,
            resultExecutor: FakeResultExecutor(result: .success(()))
        )
        let result = SearchResult(
            kind: .command,
            title: "成功结果",
            subtitle: nil,
            matchScore: 100,
            sourceIdentifier: "command:test",
            iconDescriptor: .systemSymbol(name: "bolt"),
            executionPayload: .launcherCommand(LauncherCommand.openClipboard.rawValue)
        )

        coordinator.executeInline(result)
        // 给 fire-and-forget task 充分时间完成,确保不会因调度延迟错过状态。
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(store.transientError)
    }

    /// 轮询主线程上的 store,直到 predicate 返回 true 或超时。
    /// 用来等待 fire-and-forget Task 把状态写回 store。
    private func waitFor(
        _ store: LauncherStore,
        predicate: @escaping (LauncherStore) -> Bool,
        timeout: TimeInterval = 1.0
    ) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if predicate(store) { return }
            try? await Task.sleep(for: .milliseconds(10))
            await Task.yield()
        }
    }

    private func makeCoordinator(
        store: LauncherStore,
        resultExecutor: some LauncherResultExecutor
    ) -> LauncherCoordinator {
        let cache = ApplicationResourceCache(
            capacity: 4,
            notificationCenter: NotificationCenter(),
            notificationNames: [],
            resolveURL: { _ in nil },
            loadIcon: { _ in NSImage() }
        )
        let panelController = LauncherPanelController(
            store: store,
            applicationResourceCache: cache
        )
        return LauncherCoordinator(
            shortcutService: FakeShortcutService(),
            store: store,
            panelController: panelController,
            resultExecutor: resultExecutor,
            settings: FakeSettingsService(),
            logger: FakeLoggingService()
        )
    }
}

private final class FakeSearchService: SearchService {
    func search(query: String) -> AsyncStream<SearchBatch> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cancel() {}
}

private final class FakeResultExecutor: LauncherResultExecutor {
    private let result: Result<Void, AppError>

    init(result: Result<Void, AppError>) {
        self.result = result
    }

    func execute(_ result: SearchResult) async -> Result<Void, AppError> {
        self.result
    }
}

private final class FakeShortcutService: ShortcutService, @unchecked Sendable {
    nonisolated(unsafe) var onTrigger: (@MainActor () -> Void)?
    nonisolated(unsafe) var triggers: [ShortcutAction: @MainActor () -> Void] = [:]

    nonisolated func currentShortcut(for action: ShortcutAction) async -> KeyboardShortcut {
        defaultShortcut(for: action)
    }

    nonisolated func defaultShortcut(for action: ShortcutAction) -> KeyboardShortcut {
        switch action {
        case .launcher:
            return .default
        case .clipboardPanel:
            return .defaultClipboardPanel
        }
    }

    nonisolated func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async -> ShortcutRegistrationResult {
        .success(shortcut)
    }

    nonisolated func unregister(for action: ShortcutAction) async {}

    nonisolated func restoreDefault(for action: ShortcutAction) async -> ShortcutRegistrationResult {
        .success(defaultShortcut(for: action))
    }

    nonisolated func setTrigger(for action: ShortcutAction, _ trigger: (@MainActor () -> Void)?) {
        triggers[action] = trigger
    }
}

private final class FakeSettingsService: SettingsService {
    func readBool(forKey key: SettingsKey) -> Bool { false }
    func readString(forKey key: SettingsKey) -> String? { nil }
    func readDouble(forKey key: SettingsKey) -> Double { 0 }
    func write(_ value: Bool, forKey key: SettingsKey) {}
    func write(_ value: String?, forKey key: SettingsKey) {}
    func write(_ value: Double, forKey key: SettingsKey) {}
    func remove(forKey key: SettingsKey) {}
    func resetAll() {}
}

private final class FakeLoggingService: LoggingService {
    func log(_ event: LogEvent) {}
}
