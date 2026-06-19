import Foundation

/// Launcher 命令执行后的导航目标抽象。
///
/// 让 LauncherCommandExecutor 不直接依赖 SwiftUI/AppKit,便于测试替身。
@MainActor
public protocol LauncherNavigation: AnyObject, Sendable {
    func activateMainWindow()
    func navigate(to destination: AppDestination)
}
