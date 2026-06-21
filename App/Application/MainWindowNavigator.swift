import Foundation
import AppKit
import Observation

/// 通过 `pendingDestination` 与 `openWindowRequestId` 把导航请求广播给主窗口视图。
///
/// Launcher 命令执行后通过此对象触发主窗口切换与重新打开。
/// 主窗口关闭后,`activateMainWindow` 会发出新的 `openWindowRequestId`,
/// 由 RootView 通过 `@Environment(\.openWindow)` 调用 `openWindow(id:)` 重新创建。
@MainActor
@Observable
public final class MainWindowNavigator: LauncherNavigation {
    public private(set) var pendingDestination: AppDestination?
    public private(set) var activateRequested: Int = 0
    public private(set) var openWindowRequestId: Int = 0

    public init() {}

    public static func isMainWindowIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifier == "omnipo.main" || identifier.hasPrefix("omnipo.main-AppWindow-")
    }

    public func activateMainWindow() {
        activateRequested &+= 1
        let mainWindows = NSApp.windows.filter {
            Self.isMainWindowIdentifier($0.identifier?.rawValue)
        }
        if mainWindows.isEmpty {
            openWindowRequestId &+= 1
        } else {
            for window in mainWindows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public func navigate(to destination: AppDestination) {
        pendingDestination = destination
    }

    /// 主窗口已消费 pendingDestination,清空。
    public func consumePendingDestination() {
        pendingDestination = nil
    }
}
