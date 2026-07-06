import Foundation
import AppKit
import Carbon.HIToolbox
import os

/// 抽象的快捷键后端,便于测试替身。
///
/// 真实实现用 Carbon `RegisterEventHotKey`;测试中用 `FakeShortcutBackend` 直接控制结果。
public protocol ShortcutBackend: AnyObject, Sendable {
    func setTrigger(_ trigger: @escaping @Sendable (UInt32) -> Void)
    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool
    func unregister(id: UInt32)
    func unregisterAll()
    func removeHandler()
}

/// Carbon `RegisterEventHotKey` 实现。
///
/// 不监听全部键盘输入,只注册明确组合,因此不需要辅助功能或输入监控权限。
/// Carbon pointer 不 Sendable,因此所有可变状态用 NSLock 在 sync 方法中保护。
final class CarbonShortcutBackend: ShortcutBackend, @unchecked Sendable {
    static let shared = CarbonShortcutBackend()

    private let lock = NSLock()
    private var trigger: (@Sendable (UInt32) -> Void)?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var handlerInstalled: Bool = false

    private init() {}

    func setTrigger(_ trigger: @escaping @Sendable (UInt32) -> Void) {
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
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        lock.lock()
        if let existing = hotKeyRefs[id] {
            UnregisterEventHotKey(existing)
            hotKeyRefs[id] = nil
        }
        lock.unlock()

        let target = GetApplicationEventTarget()
        let hotKeyId = EventHotKeyID(signature: Self.fourCharCode("OMNO"), id: id)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyId, target, 0, &newRef)
        guard status == noErr, let newRef else { return false }

        lock.lock()
        hotKeyRefs[id] = newRef
        lock.unlock()
        return true
    }

    func unregister(id: UInt32) {
        lock.lock()
        let ref = hotKeyRefs[id]
        hotKeyRefs[id] = nil
        lock.unlock()
        if let ref {
            UnregisterEventHotKey(ref)
        }
    }

    func unregisterAll() {
        lock.lock()
        let refs = Array(hotKeyRefs.values)
        hotKeyRefs.removeAll()
        lock.unlock()
        for ref in refs {
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
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            if let event {
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    CarbonShortcutBackend.shared.fire(id: hotKeyID.id)
                }
            }
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

    fileprivate func fire(id: UInt32) {
        lock.lock()
        let trigger = self.trigger
        lock.unlock()
        trigger?(id)
    }
}

/// ShortcutService 的默认实现。
///
/// 注册采用"先注销旧→注册新→失败回滚旧"流程,确保任何分支下都保留一个有效快捷键。
public final class CarbonShortcutService: ShortcutService, @unchecked Sendable {
    public var onTrigger: (@MainActor () -> Void)? {
        get { trigger(for: .launcher) }
        set { setTrigger(for: .launcher, newValue) }
    }

    private let backend: any ShortcutBackend
    private let logger: any LoggingService
    private let stateLock = OSAllocatedUnfairLock<ServiceState>(initialState: ServiceState())
    private let triggerLock = NSLock()
    private var triggers: [ShortcutAction: @MainActor () -> Void] = [:]

    private struct ServiceState: Sendable {
        var current: [ShortcutAction: KeyboardShortcut] = [:]
        var registered: Set<ShortcutAction> = []
    }

    public init(
        backend: (any ShortcutBackend)? = nil,
        logger: any LoggingService,
        initial: KeyboardShortcut = .default
    ) {
        let resolved = backend ?? CarbonShortcutBackend.shared
        self.backend = resolved
        self.logger = logger
        if initial != defaultShortcut(for: .launcher) {
            stateLock.withLock { state in
                state.current[.launcher] = initial
            }
        }
        resolved.setTrigger { [weak self] rawAction in
            guard let self else { return }
            guard let action = ShortcutAction(rawValue: rawAction) else { return }
            Task { @MainActor [weak self] in
                self?.trigger(for: action)?()
            }
        }
    }

    public func currentShortcut(for action: ShortcutAction) async -> KeyboardShortcut {
        stateLock.withLock { $0.current[action] ?? defaultShortcut(for: action) }
    }

    public func defaultShortcut(for action: ShortcutAction) -> KeyboardShortcut {
        switch action {
        case .launcher:
            return .default
        case .clipboardPanel:
            return .defaultClipboardPanel
        }
    }

    public func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) async -> ShortcutRegistrationResult {
        guard shortcut.isValid else {
            logger.log(Self.logInvalid())
            return .failure(.invalidShortcut)
        }

        let snapshot = stateLock.withLock { state -> (KeyboardShortcut, Bool) in
            return (state.current[action] ?? defaultShortcut(for: action), state.registered.contains(action))
        }
        let old = snapshot.0
        let alreadyRegistered = snapshot.1

        if old == shortcut && alreadyRegistered {
            return .success(shortcut)
        }

        backend.unregister(id: action.rawValue)
        let ok = backend.register(
            id: action.rawValue,
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifierFlags.carbonModifierFlags
        )
        if !ok {
            if alreadyRegistered {
                let recovered = backend.register(
                    id: action.rawValue,
                    keyCode: old.keyCode,
                    modifiers: old.modifierFlags.carbonModifierFlags
                )
                if !recovered {
                    logger.log(Self.logRollbackFailed())
                    stateLock.withLock { state in
                        state.registered.remove(action)
                    }
                    return .failure(.systemFailure)
                }
            }
            logger.log(Self.logConflict())
            return .failure(.conflict)
        }

        stateLock.withLock { state in
            state.current[action] = shortcut
            state.registered.insert(action)
        }

        logger.log(Self.logRegistered())
        return .success(shortcut)
    }

    public func unregister(for action: ShortcutAction) async {
        backend.unregister(id: action.rawValue)
        stateLock.withLock { state in
            state.registered.remove(action)
        }
    }

    public func restoreDefault(for action: ShortcutAction) async -> ShortcutRegistrationResult {
        await register(defaultShortcut(for: action), for: action)
    }

    public func setTrigger(for action: ShortcutAction, _ trigger: (@MainActor () -> Void)?) {
        triggerLock.lock()
        triggers[action] = trigger
        triggerLock.unlock()
    }

    private func trigger(for action: ShortcutAction) -> (@MainActor () -> Void)? {
        triggerLock.lock()
        defer { triggerLock.unlock() }
        return triggers[action]
    }

    deinit {
        backend.unregisterAll()
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
