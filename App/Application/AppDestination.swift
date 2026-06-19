import SwiftUI

public enum AppDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard
    case launcher
    case clipboard
    case cleaner
    case uninstaller
    case permissionAudit
    case wechatManager
    case systemMonitor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .launcher: return "Launcher"
        case .clipboard: return "Clipboard"
        case .cleaner: return "Cleaner"
        case .uninstaller: return "Uninstaller"
        case .permissionAudit: return "Permission Audit"
        case .wechatManager: return "WeChat Manager"
        case .systemMonitor: return "System Monitor"
        }
    }

    public var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.clipboard"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash.circle"
        case .permissionAudit: return "checkmark.shield"
        case .wechatManager: return "bubble.left.and.bubble.right"
        case .systemMonitor: return "chart.xyaxis.line"
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch self {
        case .dashboard: DashboardView()
        case .launcher: LauncherView()
        case .clipboard: ClipboardView()
        case .cleaner: CleanerView()
        case .uninstaller: UninstallerView()
        case .permissionAudit: PermissionAuditView()
        case .wechatManager: WeChatManagerView()
        case .systemMonitor: SystemMonitorView()
        }
    }
}
