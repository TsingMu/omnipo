import Foundation

/// Dashboard 上只负责导航的安全快捷入口。
public enum DashboardShortcut: String, CaseIterable, Identifiable, Sendable {
    case scanDisk
    case uninstallApplication
    case auditPermissions
    case manageWeChat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .scanDisk: return "磁盘扫描"
        case .uninstallApplication: return "应用卸载"
        case .auditPermissions: return "权限审计"
        case .manageWeChat: return "微信管理"
        }
    }

    public var subtitle: String {
        switch self {
        case .scanDisk: return "查看空间占用"
        case .uninstallApplication: return "安全移除应用"
        case .auditPermissions: return "了解隐私授权"
        case .manageWeChat: return "分析本地占用"
        }
    }

    public var symbol: String {
        switch self {
        case .scanDisk: return "internaldrive"
        case .uninstallApplication: return "shippingbox"
        case .auditPermissions: return "checkmark.shield"
        case .manageWeChat: return "bubble.left.and.bubble.right"
        }
    }

    public var destination: AppDestination {
        switch self {
        case .scanDisk: return .cleaner
        case .uninstallApplication: return .uninstaller
        case .auditPermissions: return .permissionAudit
        case .manageWeChat: return .wechatManager
        }
    }
}
