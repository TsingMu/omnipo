import XCTest
@testable import Omnipo

final class CarbonShortcutServiceTests: XCTestCase {

    private func makeLogger() -> any LoggingService {
        OSLogLoggingService(subsystem: "com.omnipo.tests.shortcut")
    }

    func test_register_validShortcut_succeeds() async {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())

        let result = await service.register(
            KeyboardShortcut(keyCode: 11, modifierFlags: [.command, .shift])
        )

        if case .success(let shortcut) = result {
            XCTAssertEqual(shortcut.keyCode, 11)
        } else {
            XCTFail("expected success")
        }
        XCTAssertEqual(backend.registerCount, 1, "should attempt one register")
        let current = await service.currentShortcut()
        XCTAssertEqual(current.keyCode, 11)
    }

    func test_register_invalidShortcut_returnsInvalidWithoutBackendCall() async {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())

        let result = await service.register(
            KeyboardShortcut(keyCode: 49, modifierFlags: [])
        )

        XCTAssertEqual(result, .failure(.invalidShortcut))
        XCTAssertEqual(backend.registerCount, 0, "invalid should not call backend register")
    }

    func test_register_sameShortcut_isIdempotent() async {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())

        let first = KeyboardShortcut(keyCode: 11, modifierFlags: .command)
        _ = await service.register(first)
        let firstCount = backend.registerCount
        let second = await service.register(first)

        if case .success(let shortcut) = second {
            XCTAssertEqual(shortcut, first)
        } else {
            XCTFail("idempotent register should succeed")
        }
        XCTAssertEqual(backend.registerCount, firstCount, "idempotent register must not call backend again")
    }

    func test_register_conflict_keepsOldShortcut() async {
        // 初始:全部成功
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(
            backend: backend,
            logger: makeLogger(),
            initial: KeyboardShortcut(keyCode: 49, modifierFlags: .option)
        )

        // 第一次成功注册 default
        _ = await service.register(.default)

        // 第二次:候选 keyCode 失败,其他(回滚 default)成功
        backend.registerResultProvider = { keyCode, _ in keyCode != 11 }
        let failed = await service.register(
            KeyboardShortcut(keyCode: 11, modifierFlags: .command)
        )

        XCTAssertEqual(failed, .failure(.conflict))
        // 旧快捷键应该被恢复 — register 应该被调用至少 3 次:
        //   1) 初始 default
        //   2) 新候选(失败)
        //   3) 回滚 default
        XCTAssertGreaterThanOrEqual(backend.registerCount, 3)
        let current = await service.currentShortcut()
        XCTAssertEqual(current, .default, "current should still be the previous shortcut")
    }

    func test_register_firstAttemptFails_returnsConflictNotSystemFailure() async {
        let backend = FakeShortcutBackend(registerResult: { _, _ in false })
        let service = CarbonShortcutService(
            backend: backend,
            logger: makeLogger(),
            initial: KeyboardShortcut(keyCode: 49, modifierFlags: .option)
        )

        // 首次注册失败 — 没有"旧"需要回滚,直接返回 conflict
        let failed = await service.register(
            KeyboardShortcut(keyCode: 11, modifierFlags: .command)
        )

        XCTAssertEqual(failed, .failure(.conflict))
    }

    func test_register_rollbackAlsoFails_returnsSystemFailure() async {
        let backend = FakeShortcutBackend(registerResult: { keyCode, _ in keyCode == 49 })
        let service = CarbonShortcutService(
            backend: backend,
            logger: makeLogger(),
            initial: KeyboardShortcut(keyCode: 49, modifierFlags: .option)
        )

        // 先成功注册 default(keyCode 49)
        _ = await service.register(.default)

        // 现在所有 register 都失败(回滚 default 也失败)
        backend.registerResultProvider = { _, _ in false }
        let failed = await service.register(
            KeyboardShortcut(keyCode: 11, modifierFlags: .command)
        )

        XCTAssertEqual(failed, .failure(.systemFailure))
    }

    func test_unregister_callsBackendAndKeepsCurrent() async {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())
        _ = await service.register(KeyboardShortcut(keyCode: 11, modifierFlags: .command))

        await service.unregister()

        XCTAssertGreaterThanOrEqual(backend.unregisterCount, 1)
    }

    func test_restoreDefault_registersOptionSpace() async {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())

        let result = await service.restoreDefault()

        if case .success(let shortcut) = result {
            XCTAssertEqual(shortcut, .default)
        } else {
            XCTFail("expected default to register")
        }
    }

    func test_onTrigger_firesWhenBackendFires() async throws {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())

        let expectation = expectation(description: "trigger fired")
        await MainActor.run {
            service.onTrigger = {
                expectation.fulfill()
            }
        }

        backend.fire(id: ShortcutAction.launcher.rawValue)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func test_actionTriggers_areIndependent() async throws {
        let backend = FakeShortcutBackend(registerResult: { _, _ in true })
        let service = CarbonShortcutService(backend: backend, logger: makeLogger())
        let launcherExpectation = expectation(description: "launcher trigger fired")
        launcherExpectation.isInverted = true
        let clipboardExpectation = expectation(description: "clipboard trigger fired")

        await MainActor.run {
            service.onTrigger = {
                launcherExpectation.fulfill()
            }
            service.setTrigger(for: .clipboardPanel) {
                clipboardExpectation.fulfill()
            }
        }

        backend.fire(id: ShortcutAction.clipboardPanel.rawValue)

        await fulfillment(of: [launcherExpectation, clipboardExpectation], timeout: 1.0)
    }
}

final class FakeShortcutBackend: ShortcutBackend, @unchecked Sendable {
    var trigger: (@Sendable (UInt32) -> Void)?
    var registerResultProvider: (UInt32, UInt32) -> Bool
    private(set) var registerCount: Int = 0
    private(set) var unregisterCount: Int = 0
    private(set) var removeHandlerCount: Int = 0
    private let lock = NSLock()

    init(registerResult: @escaping (UInt32, UInt32) -> Bool) {
        self.registerResultProvider = registerResult
    }

    func setTrigger(_ trigger: @escaping @Sendable (UInt32) -> Void) {
        lock.lock()
        self.trigger = trigger
        lock.unlock()
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        lock.lock()
        registerCount += 1
        let provider = registerResultProvider
        lock.unlock()
        return provider(keyCode, modifiers)
    }

    func unregister(id: UInt32) {
        lock.lock()
        unregisterCount += 1
        lock.unlock()
    }

    func unregisterAll() {
        lock.lock()
        unregisterCount += 1
        lock.unlock()
    }

    func removeHandler() {
        lock.lock()
        removeHandlerCount += 1
        lock.unlock()
    }

    func fire(id: UInt32) {
        lock.lock()
        let t = trigger
        lock.unlock()
        t?(id)
    }
}
