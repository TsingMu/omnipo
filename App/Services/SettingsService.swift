import Foundation

public extension Notification.Name {
    static let menuBarVisibilitySettingDidChange = Notification.Name("com.qing.omnipo.settings.menuBarVisibilityDidChange")
}

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

public enum ClipboardSettingsDefaults {
    public static let isEnabled = false
    public static let hasAcknowledgedLocalStorageNotice = false
    public static let autoPaste = true
    public static let maxRecords = 1_000.0
    public static let retentionDays = 30.0
    public static let maxStorageMB = 500.0
    public static let pollingIntervalSeconds = 0.3
    public static let imageQuality = 0.8
    public static let showMenuBarIcon = true
    public static let panelPosition = ClipboardPanelPosition.center.rawValue

    public static func clampMaxRecords(_ value: Double) -> Double {
        min(max(value.rounded(), 1), 10_000)
    }

    public static func clampRetentionDays(_ value: Double) -> Double {
        min(max(value.rounded(), 1), 365)
    }

    public static func clampMaxStorageMB(_ value: Double) -> Double {
        min(max(value.rounded(), 16), 10_240)
    }

    public static func clampPollingIntervalSeconds(_ value: Double) -> Double {
        min(max((value * 10).rounded() / 10, 0.1), 2.0)
    }

    public static func clampImageQuality(_ value: Double) -> Double {
        min(max((value * 10).rounded() / 10, 0.1), 1.0)
    }
}

public enum ClipboardPanelPosition: String, CaseIterable, Sendable, Hashable {
    case center
    case followMouse
    case lastPosition

    public var displayName: String {
        switch self {
        case .center:
            return "居中"
        case .followMouse:
            return "跟随鼠标"
        case .lastPosition:
            return "上次位置"
        }
    }
}

public extension SettingsKey {
    static let launchDashboardAtStart = SettingsKey(
        "omnipo.settings.launchDashboardAtStart",
        default: .bool(true)
    )

    static let launchAtLogin = SettingsKey(
        "omnipo.settings.launchAtLogin",
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

    static let clipboardPanelShortcutKeyCode = SettingsKey(
        "omnipo.settings.clipboard.panel.shortcut.keyCode",
        default: .double(0)
    )

    static let clipboardPanelShortcutModifiers = SettingsKey(
        "omnipo.settings.clipboard.panel.shortcut.modifiers",
        default: .double(0)
    )

    /// 用户授权的大文件扫描根 security-scoped bookmark(base64 字符串)。
    /// 空串表示未授权。
    static let largeFileRootBookmark = SettingsKey(
        "omnipo.settings.disk.largeFileRootBookmark",
        default: .string("")
    )

    /// 聚焦搜索文件操作已授权目录的 security-scoped bookmark 列表。
    /// 使用换行分隔 base64 字符串;空串表示未授权。
    static let launcherFileDirectoryBookmarks = SettingsKey(
        "omnipo.settings.launcher.fileDirectoryBookmarks",
        default: .string("")
    )

    /// 用户授权的微信存储扫描根 security-scoped bookmark 列表。
    static let weChatStorageRootBookmarks = SettingsKey(
        "omnipo.settings.wechat.storageRootBookmarks",
        default: .string("")
    )

    /// 用户是否明确同意在微信管理页显示敏感名称。聊天别名不写入设置。
    static let weChatSensitiveNamesEnabled = SettingsKey(
        "omnipo.settings.wechat.sensitiveNamesEnabled",
        default: .bool(false)
    )

    static let systemMonitorIntervalSeconds = SettingsKey(
        "omnipo.settings.systemMonitor.intervalSeconds",
        default: .double(SystemMonitorInterval.defaultSeconds)
    )

    static let clipboardIsEnabled = SettingsKey(
        "omnipo.settings.clipboard.isEnabled",
        default: .bool(ClipboardSettingsDefaults.isEnabled)
    )

    static let clipboardHasAcknowledgedLocalStorageNotice = SettingsKey(
        "omnipo.settings.clipboard.hasAcknowledgedLocalStorageNotice",
        default: .bool(ClipboardSettingsDefaults.hasAcknowledgedLocalStorageNotice)
    )

    static let clipboardAutoPaste = SettingsKey(
        "omnipo.settings.clipboard.autoPaste",
        default: .bool(ClipboardSettingsDefaults.autoPaste)
    )

    static let clipboardMaxRecords = SettingsKey(
        "omnipo.settings.clipboard.maxRecords",
        default: .double(ClipboardSettingsDefaults.maxRecords)
    )

    static let clipboardRetentionDays = SettingsKey(
        "omnipo.settings.clipboard.retentionDays",
        default: .double(ClipboardSettingsDefaults.retentionDays)
    )

    static let clipboardMaxStorageMB = SettingsKey(
        "omnipo.settings.clipboard.maxStorageMB",
        default: .double(ClipboardSettingsDefaults.maxStorageMB)
    )

    static let clipboardExcludedApplications = SettingsKey(
        "omnipo.settings.clipboard.excludedApplications",
        default: .string("")
    )

    static let clipboardExcludedPatterns = SettingsKey(
        "omnipo.settings.clipboard.excludedPatterns",
        default: .string("")
    )

    static let clipboardPollingIntervalSeconds = SettingsKey(
        "omnipo.settings.clipboard.pollingIntervalSeconds",
        default: .double(ClipboardSettingsDefaults.pollingIntervalSeconds)
    )

    static let clipboardImageQuality = SettingsKey(
        "omnipo.settings.clipboard.imageQuality",
        default: .double(ClipboardSettingsDefaults.imageQuality)
    )

    static let showMenuBarIcon = SettingsKey(
        "omnipo.settings.showMenuBarIcon",
        default: .bool(ClipboardSettingsDefaults.showMenuBarIcon)
    )

    static let clipboardPanelPosition = SettingsKey(
        "omnipo.settings.clipboard.panelPosition",
        default: .string(ClipboardSettingsDefaults.panelPosition)
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

    /// 读取已保存的 Clipboard 悬浮面板快捷键;键不存在或损坏时返回 nil。
    func readClipboardPanelShortcut() -> KeyboardShortcut? {
        readShortcut(keyCodeKey: .clipboardPanelShortcutKeyCode, modifiersKey: .clipboardPanelShortcutModifiers)
    }

    /// 仅在调用方确认新组合注册成功后调用。
    func writeClipboardPanelShortcut(_ shortcut: KeyboardShortcut) {
        writeShortcut(shortcut, keyCodeKey: .clipboardPanelShortcutKeyCode, modifiersKey: .clipboardPanelShortcutModifiers)
    }

    func clearClipboardPanelShortcut() {
        remove(forKey: .clipboardPanelShortcutKeyCode)
        remove(forKey: .clipboardPanelShortcutModifiers)
    }

    private func readShortcut(keyCodeKey: SettingsKey, modifiersKey: SettingsKey) -> KeyboardShortcut? {
        let keyCodeRaw = readDouble(forKey: keyCodeKey)
        let modifiersRaw = readDouble(forKey: modifiersKey)
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

    private func writeShortcut(_ shortcut: KeyboardShortcut, keyCodeKey: SettingsKey, modifiersKey: SettingsKey) {
        write(Double(shortcut.keyCode), forKey: keyCodeKey)
        write(Double(shortcut.modifierFlags.rawValue), forKey: modifiersKey)
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

    func readLauncherFileDirectoryBookmarks() -> [Data] {
        guard let stored = readString(forKey: .launcherFileDirectoryBookmarks),
              !stored.isEmpty else {
            return []
        }
        return stored
            .split(separator: "\n")
            .compactMap { Data(base64Encoded: String($0)) }
    }

    func writeLauncherFileDirectoryBookmarks(_ bookmarks: [Data]) {
        let encoded = bookmarks
            .filter { !$0.isEmpty }
            .map { $0.base64EncodedString() }
        guard !encoded.isEmpty else {
            remove(forKey: .launcherFileDirectoryBookmarks)
            return
        }
        write(encoded.joined(separator: "\n"), forKey: .launcherFileDirectoryBookmarks)
    }

    func readWeChatStorageRootBookmarks() -> [Data] {
        guard let stored = readString(forKey: .weChatStorageRootBookmarks),
              !stored.isEmpty else {
            return []
        }
        return stored
            .split(separator: "\n")
            .compactMap { Data(base64Encoded: String($0)) }
    }

    func writeWeChatStorageRootBookmarks(_ bookmarks: [Data]) {
        let encoded = bookmarks
            .filter { !$0.isEmpty }
            .map { $0.base64EncodedString() }
        guard !encoded.isEmpty else {
            remove(forKey: .weChatStorageRootBookmarks)
            return
        }
        write(encoded.joined(separator: "\n"), forKey: .weChatStorageRootBookmarks)
    }

    /// 读取系统监控采样间隔;损坏值回退到默认 5 秒。
    func readSystemMonitorIntervalSeconds() -> Double {
        let stored = readDouble(forKey: .systemMonitorIntervalSeconds)
        return SystemMonitorInterval.clampOrFallback(stored)
    }

    /// 持久化系统监控采样间隔;非法值写入前钳到默认。
    func writeSystemMonitorIntervalSeconds(_ value: Double) {
        let clamped = SystemMonitorInterval.clampOrFallback(value)
        write(clamped, forKey: .systemMonitorIntervalSeconds)
    }

    func readClipboardMaxRecords() -> Double {
        ClipboardSettingsDefaults.clampMaxRecords(readDouble(forKey: .clipboardMaxRecords))
    }

    func writeClipboardMaxRecords(_ value: Double) {
        write(ClipboardSettingsDefaults.clampMaxRecords(value), forKey: .clipboardMaxRecords)
    }

    func readClipboardRetentionDays() -> Double {
        ClipboardSettingsDefaults.clampRetentionDays(readDouble(forKey: .clipboardRetentionDays))
    }

    func writeClipboardRetentionDays(_ value: Double) {
        write(ClipboardSettingsDefaults.clampRetentionDays(value), forKey: .clipboardRetentionDays)
    }

    func readClipboardMaxStorageMB() -> Double {
        ClipboardSettingsDefaults.clampMaxStorageMB(readDouble(forKey: .clipboardMaxStorageMB))
    }

    func writeClipboardMaxStorageMB(_ value: Double) {
        write(ClipboardSettingsDefaults.clampMaxStorageMB(value), forKey: .clipboardMaxStorageMB)
    }

    func readClipboardExcludedApplications() -> [String] {
        readStringList(forKey: .clipboardExcludedApplications)
    }

    func writeClipboardExcludedApplications(_ bundleIDs: [String]) {
        writeStringList(bundleIDs, forKey: .clipboardExcludedApplications)
    }

    func readClipboardExcludedPatterns() -> [String] {
        readStringList(forKey: .clipboardExcludedPatterns)
    }

    func writeClipboardExcludedPatterns(_ patterns: [String]) {
        writeStringList(patterns, forKey: .clipboardExcludedPatterns)
    }

    func readClipboardPollingIntervalSeconds() -> Double {
        ClipboardSettingsDefaults.clampPollingIntervalSeconds(readDouble(forKey: .clipboardPollingIntervalSeconds))
    }

    func writeClipboardPollingIntervalSeconds(_ value: Double) {
        write(ClipboardSettingsDefaults.clampPollingIntervalSeconds(value), forKey: .clipboardPollingIntervalSeconds)
    }

    func readClipboardImageQuality() -> Double {
        ClipboardSettingsDefaults.clampImageQuality(readDouble(forKey: .clipboardImageQuality))
    }

    func writeClipboardImageQuality(_ value: Double) {
        write(ClipboardSettingsDefaults.clampImageQuality(value), forKey: .clipboardImageQuality)
    }

    func readClipboardPanelPosition() -> ClipboardPanelPosition {
        guard let stored = readString(forKey: .clipboardPanelPosition),
              let position = ClipboardPanelPosition(rawValue: stored) else {
            return .center
        }
        return position
    }

    func writeClipboardPanelPosition(_ position: ClipboardPanelPosition) {
        write(position.rawValue, forKey: .clipboardPanelPosition)
    }

    func resetClippyStyleSettingsToDefaults() {
        write(true, forKey: .launchDashboardAtStart)
        write(ClipboardSettingsDefaults.autoPaste, forKey: .clipboardAutoPaste)
        writeClipboardPanelPosition(.center)
        writeClipboardMaxRecords(ClipboardSettingsDefaults.maxRecords)
        writeClipboardRetentionDays(ClipboardSettingsDefaults.retentionDays)
        writeClipboardMaxStorageMB(ClipboardSettingsDefaults.maxStorageMB)
        writeClipboardExcludedApplications([])
        writeClipboardExcludedPatterns([])
        writeClipboardPollingIntervalSeconds(ClipboardSettingsDefaults.pollingIntervalSeconds)
        writeClipboardImageQuality(ClipboardSettingsDefaults.imageQuality)
        write(ClipboardSettingsDefaults.showMenuBarIcon, forKey: .showMenuBarIcon)
    }

    private func readStringList(forKey key: SettingsKey) -> [String] {
        guard let stored = readString(forKey: key), !stored.isEmpty else {
            return []
        }
        return stored
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func writeStringList(_ values: [String], forKey key: SettingsKey) {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else {
            remove(forKey: key)
            return
        }
        write(normalized.joined(separator: "\n"), forKey: key)
    }
}
