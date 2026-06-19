import Foundation
import AppKit
import Combine

/// 通过 `pendingDestination` 与 `openWindowRequestId` 把导航请求广播给主窗口视图。
///
/// Launcher 命令执行后通过此对象触发主窗口切换与重新打开。
/// 主窗口关闭后,`activateMainWindow` 会发出新的 `openWindowRequestId`,
/// 由 RootView 通过 `@Environment(\.openWindow)` 调用 `openWindow(id:)` 重新创建。
@MainActor
public final class MainWindowNavigator: LauncherNavigation, ObservableObject {
    @Published public private(set) var pendingDestination: AppDestination?
    @Published public private(set) var activateRequested: Int = 0
    @Published public private(set) var openWindowRequestId: Int = 0

    public init() {}

    public func activateMainWindow() {
        openWindowRequestId &+= 1
        activateRequested &+= 1
        for window in NSApp.windows where window.identifier?.rawValue == "omnipo.main" {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public func navigate(to destination: AppDestination) {
        activateMainWindow()
        pendingDestination = destination
    }

    /// 主窗口已消费 pendingDestination,清空。
    public func consumePendingDestination() {
        pendingDestination = nil
    }
}
