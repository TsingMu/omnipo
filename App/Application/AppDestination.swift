import SwiftUI

public enum AppDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case overview
        case productivity
        case system

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .overview: return "概览"
            case .productivity: return "效率工具"
            case .system: return "系统工具"
            }
        }
    }

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
        case .dashboard: return "总览"
        case .launcher: return "快速启动"
        case .clipboard: return "剪切板"
        case .cleaner: return "磁盘清理"
        case .uninstaller: return "应用卸载"
        case .permissionAudit: return "权限审计"
        case .wechatManager: return "微信管理"
        case .systemMonitor: return "系统监控"
        }
    }

    public var sidebarSubtitle: String {
        switch self {
        case .dashboard: return "状态与常用入口"
        case .launcher: return "搜索应用、文件与功能"
        case .clipboard: return "管理最近复制内容"
        case .cleaner: return "分析本机空间占用"
        case .uninstaller: return "移除应用与关联文件"
        case .permissionAudit: return "查看应用隐私授权"
        case .wechatManager: return "了解本地聊天占用"
        case .systemMonitor: return "观察系统资源状态"
        }
    }

    public var section: Section {
        switch self {
        case .dashboard: return .overview
        case .launcher, .clipboard: return .productivity
        case .cleaner, .uninstaller, .permissionAudit, .wechatManager, .systemMonitor:
            return .system
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

    @MainActor
    @ViewBuilder
    func detailView(onNavigate: @escaping @MainActor (AppDestination) -> Void) -> some View {
        switch self {
        case .dashboard: DashboardView(onNavigate: onNavigate)
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
