import Foundation

public protocol SettingsService: AnyObject, Sendable {
    func readBool(forKey key: SettingsKey) -> Bool
    func readString(forKey key: SettingsKey) -> String?
    func readDouble(forKey key: SettingsKey) -> Double

    func write(_ value: Bool, forKey key: SettingsKey)
    func write(_ value: String?, forKey key: SettingsKey)
    func write(_ value: Double, forKey key: SettingsKey)

    func remove(forKey key: SettingsKey)
    func resetAll()
}

public struct SettingsKey: Sendable, Hashable {
    public let rawValue: String
    public let defaultValue: SettingsValue

    public init(_ rawValue: String, default defaultValue: SettingsValue) {
        self.rawValue = rawValue
        self.defaultValue = defaultValue
    }
}

public enum SettingsValue: Sendable, Hashable {
    case bool(Bool)
    case string(String)
    case double(Double)
}

public extension SettingsKey {
    static let launchDashboardAtStart = SettingsKey(
        "omnipo.settings.launchDashboardAtStart",
        default: .bool(true)
    )

    static let reopenLastDestination = SettingsKey(
        "omnipo.settings.reopenLastDestination",
        default: .bool(false)
    )

    static let lastOpenedDestinationKey = SettingsKey(
        "omnipo.settings.lastOpenedDestination",
        default: .string("dashboard")
    )

    static let launcherShortcutKeyCode = SettingsKey(
        "omnipo.settings.launcher.shortcut.keyCode",
        default: .double(0)
    )

    static let launcherShortcutModifiers = SettingsKey(
        "omnipo.settings.launcher.shortcut.modifiers",
        default: .double(0)
    )

    /// 用户授权的大文件扫描根 security-scoped bookmark(base64 字符串)。
    /// 空串表示未授权。
    static let largeFileRootBookmark = SettingsKey(
        "omnipo.settings.disk.largeFileRootBookmark",
        default: .string("")
    )
}

public extension SettingsService {
    func readValue(forKey key: SettingsKey) -> SettingsValue {
        switch key.defaultValue {
        case .bool:
            return .bool(readBool(forKey: key))
        case .string(let fallback):
            if let stored = readString(forKey: key) {
                return .string(stored)
            }
            return .string(fallback)
        case .double:
            return .double(readDouble(forKey: key))
        }
    }

    /// 读取已保存的 Launcher 快捷键;键不存在或值损坏时返回 nil,调用方应回退到默认。
    func readLauncherShortcut() -> KeyboardShortcut? {
        let keyCodeRaw = readDouble(forKey: .launcherShortcutKeyCode)
        let modifiersRaw = readDouble(forKey: .launcherShortcutModifiers)
        if keyCodeRaw == 0 && modifiersRaw == 0 {
            return nil
        }
        guard keyCodeRaw >= 0, keyCodeRaw <= Double(UInt32.max),
              modifiersRaw >= 0, modifiersRaw <= Double(UInt32.max) else {
            return nil
        }
        let keyCode = UInt32(keyCodeRaw)
        let modifiers = UInt32(modifiersRaw)
        let flags = KeyboardShortcut.ModifierFlags(rawValue: modifiers)
        let shortcut = KeyboardShortcut(keyCode: keyCode, modifierFlags: flags)
        return shortcut.isValid ? shortcut : nil
    }

    /// 仅在调用方确认新组合注册成功后调用。
    func writeLauncherShortcut(_ shortcut: KeyboardShortcut) {
        write(Double(shortcut.keyCode), forKey: .launcherShortcutKeyCode)
        write(Double(shortcut.modifierFlags.rawValue), forKey: .launcherShortcutModifiers)
    }

    func clearLauncherShortcut() {
        remove(forKey: .launcherShortcutKeyCode)
        remove(forKey: .launcherShortcutModifiers)
    }

    /// 读取已保存的大文件根 bookmark;未授权或损坏返回 nil。
    func readLargeFileRootBookmark() -> Data? {
        guard let base64 = readString(forKey: .largeFileRootBookmark),
              !base64.isEmpty,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return data
    }

    /// 持久化新 bookmark;传 nil 清除授权。
    func writeLargeFileRootBookmark(_ data: Data?) {
        guard let data, !data.isEmpty else {
            remove(forKey: .largeFileRootBookmark)
            return
        }
        let base64 = data.base64EncodedString()
        write(base64, forKey: .largeFileRootBookmark)
    }
}
