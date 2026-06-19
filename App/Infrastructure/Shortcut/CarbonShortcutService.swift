import Foundation
import AppKit
import Carbon.HIToolbox
import os

/// 抽象的快捷键后端,便于测试替身。
///
/// 真实实现用 Carbon `RegisterEventHotKey`;测试中用 `FakeShortcutBackend` 直接控制结果。
public protocol ShortcutBackend: AnyObject, Sendable {
    func setTrigger(_ trigger: @escaping @Sendable () -> Void)
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool
    func unregister()
    func removeHandler()
}

/// Carbon `RegisterEventHotKey` 实现。
///
/// 不监听全部键盘输入,只注册明确组合,因此不需要辅助功能或输入监控权限。
/// Carbon pointer 不 Sendable,因此所有可变状态用 NSLock 在 sync 方法中保护。
final class CarbonShortcutBackend: ShortcutBackend, @unchecked Sendable {
    static let shared = CarbonShortcutBackend()

    private let lock = NSLock()
    private var trigger: (@Sendable () -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerInstalled: Bool = false

    private init() {}

    func setTrigger(_ trigger: @escaping @Sendable () -> Void) {
        lock.lock()
        self.trigger = trigger
        let needInstall = !handlerInstalled
        if needInstall {
            handlerInstalled = true
        }
        lock.unlock()
        if needInstall {
            installHandler()
        }
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        lock.lock()
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        lock.unlock()

        let target = GetApplicationEventTarget()
        let hotKeyId = EventHotKeyID(signature: Self.fourCharCode("OMNO"), id: UInt32(1))
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyId, target, 0, &newRef)
        guard status == noErr, let newRef else { return false }

        lock.lock()
        hotKeyRef = newRef
        lock.unlock()
        return true
    }

    func unregister() {
        lock.lock()
        let ref = hotKeyRef
        hotKeyRef = nil
        lock.unlock()
        if let ref {
            UnregisterEventHotKey(ref)
        }
    }

    func removeHandler() {
        lock.lock()
        let ref = handlerRef
        handlerRef = nil
        handlerInstalled = false
        lock.unlock()
        if let ref {
            RemoveEventHandler(ref)
        }
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return OSType(result)
    }

    private func installHandler() {
        let callback: EventHandlerUPP = { _, _, _ in
            CarbonShortcutBackend.shared.fire()
            return noErr
        }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            nil,
            &ref
        )
        if status == noErr {
            lock.lock()
            handlerRef = ref
            lock.unlock()
        }
    }

    fileprivate func fire() {
        lock.lock()
        let trigger = self.trigger
        lock.unlock()
        trigger?()
    }
}

/// ShortcutService 的默认实现。
///
/// 注册采用"先注销旧→注册新→失败回滚旧"流程,确保任何分支下都保留一个有效快捷键。
public final class CarbonShortcutService: ShortcutService, @unchecked Sendable {
    public var onTrigger: (@MainActor () -> Void)?

    private let backend: any ShortcutBackend
    private let logger: any LoggingService
    private let stateLock = OSAllocatedUnfairLock<ServiceState>(initialState: ServiceState())

    private struct ServiceState: Sendable {
        var current: KeyboardShortcut = .default
        var registered: Bool = false
    }

    public init(
        backend: (any ShortcutBackend)? = nil,
        logger: any LoggingService,
        initial: KeyboardShortcut = .default
    ) {
        let resolved = backend ?? CarbonShortcutBackend.shared
        self.backend = resolved
        self.logger = logger
        if initial != ServiceState().current {
            stateLock.withLock { state in
                state.current = initial
            }
        }
        resolved.setTrigger { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.onTrigger?()
            }
        }
    }

    public func currentShortcut() async -> KeyboardShortcut {
        stateLock.withLock { $0.current }
    }

    public func defaultShortcut() -> KeyboardShortcut {
        .default
    }

    public func register(_ shortcut: KeyboardShortcut) async -> ShortcutRegistrationResult {
        guard shortcut.isValid else {
            logger.log(Self.logInvalid())
            return .failure(.invalidShortcut)
        }

        let snapshot = stateLock.withLock { state -> (KeyboardShortcut, Bool) in
            return (state.current, state.registered)
        }
        let old = snapshot.0
        let alreadyRegistered = snapshot.1

        if old == shortcut && alreadyRegistered {
            return .success(shortcut)
        }

        backend.unregister()
        let ok = backend.register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifierFlags.carbonModifierFlags
        )
        if !ok {
            if alreadyRegistered {
                let recovered = backend.register(
                    keyCode: old.keyCode,
                    modifiers: old.modifierFlags.carbonModifierFlags
                )
                if !recovered {
                    logger.log(Self.logRollbackFailed())
                    stateLock.withLock { state in
                        state.registered = false
                    }
                    return .failure(.systemFailure)
                }
            }
            logger.log(Self.logConflict())
            return .failure(.conflict)
        }

        stateLock.withLock { state in
            state.current = shortcut
            state.registered = true
        }

        logger.log(Self.logRegistered())
        return .success(shortcut)
    }

    public func unregister() async {
        backend.unregister()
        stateLock.withLock { state in
            state.registered = false
        }
    }

    public func restoreDefault() async -> ShortcutRegistrationResult {
        await register(.default)
    }

    deinit {
        backend.unregister()
        backend.removeHandler()
    }

    private static func logRegistered() -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "shortcut.registered",
            stableCode: "I_SHORTCUT_REGISTERED",
            sanitizedContext: ["code": "I_SHORTCUT_REGISTERED", "reason": "ok"]
        )
    }

    private static func logConflict() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "shortcut.conflict",
            stableCode: "W_SHORTCUT_CONFLICT",
            sanitizedContext: ["code": "W_SHORTCUT_CONFLICT", "reason": "conflict"]
        )
    }

    private static func logInvalid() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "shortcut.invalid",
            stableCode: "W_SHORTCUT_INVALID",
            sanitizedContext: ["code": "W_SHORTCUT_INVALID", "reason": "invalid"]
        )
    }

    private static func logRollbackFailed() -> LogEvent {
        LogEvent(
            level: .error,
            category: .application,
            message: "shortcut.rollback.failed",
            stableCode: "E_SHORTCUT_ROLLBACK",
            sanitizedContext: ["code": "E_SHORTCUT_ROLLBACK", "reason": "rollback"]
        )
    }
}
