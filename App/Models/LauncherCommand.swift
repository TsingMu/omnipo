import Foundation

/// Launcher 内置命令的稳定标识。
///
/// 执行逻辑只依赖 `rawValue`,不依赖本地化标题。
public enum LauncherCommand: String, Sendable, Hashable, CaseIterable, Identifiable {
    case openClipboard
    case scanDisk
    case uninstallApplication
    case auditPermissions
    case inspectWeChatStorage
    case openSystemMonitor

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .openClipboard: return "打开剪切板"
        case .scanDisk: return "扫描磁盘"
        case .uninstallApplication: return "卸载应用"
        case .auditPermissions: return "权限审计"
        case .inspectWeChatStorage: return "查看微信占用"
        case .openSystemMonitor: return "打开系统监控"
        }
    }

    public var englishTitle: String {
        switch self {
        case .openClipboard: return "Open Clipboard"
        case .scanDisk: return "Scan Disk"
        case .uninstallApplication: return "Uninstall Application"
        case .auditPermissions: return "Audit Permissions"
        case .inspectWeChatStorage: return "Inspect WeChat Storage"
        case .openSystemMonitor: return "Open System Monitor"
        }
    }

    public var keywords: [String] {
        switch self {
        case .openClipboard:
            return ["clipboard", "剪贴板", "粘贴", "paste"]
        case .scanDisk:
            return ["cleaner", "清理", "磁盘", "scan", "disk", "空间"]
        case .uninstallApplication:
            return ["uninstall", "卸载", "应用", "remove"]
        case .auditPermissions:
            return ["permission", "权限", "隐私", "tcc", "审计"]
        case .inspectWeChatStorage:
            return ["wechat", "微信", "空间", "storage", "缓存"]
        case .openSystemMonitor:
            return ["monitor", "监控", "cpu", "memory", "性能"]
        }
    }

    public var symbolName: String {
        switch self {
        case .openClipboard: return "doc.on.clipboard"
        case .scanDisk: return "sparkles"
        case .uninstallApplication: return "trash.circle"
        case .auditPermissions: return "checkmark.shield"
        case .inspectWeChatStorage: return "bubble.left.and.bubble.right"
        case .openSystemMonitor: return "chart.xyaxis.line"
        }
    }

    public var searchableTexts: [String] {
        [displayTitle, englishTitle] + keywords
    }
}
