import Foundation

/// 把稳定 `LauncherCommand` 映射到主窗口 `AppDestination`。
///
/// 不执行具体业务(扫描、卸载、审计),只负责打开主窗口并切换导航选择。
@MainActor
public final class LauncherCommandExecutor {
    private let navigator: any LauncherNavigation

    public init(navigator: any LauncherNavigation) {
        self.navigator = navigator
    }

    /// 六个命令到导航目标的稳定映射,与文案无关。
    public static func destination(for command: LauncherCommand) -> AppDestination {
        switch command {
        case .openClipboard: return .clipboard
        case .scanDisk: return .cleaner
        case .uninstallApplication: return .uninstaller
        case .auditPermissions: return .permissionAudit
        case .inspectWeChatStorage: return .wechatManager
        case .openSystemMonitor: return .systemMonitor
        }
    }

    public func execute(_ command: LauncherCommand) {
        navigator.activateMainWindow()
        navigator.navigate(to: Self.destination(for: command))
    }
}
