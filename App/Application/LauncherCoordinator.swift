import Foundation
import Observation

/// 连接快捷键、面板和执行器。
///
/// 唯一订阅快捷键触发;接收面板的 hide/execute 请求并转发到正确组件。
@MainActor
@Observable
public final class LauncherCoordinator: LauncherPanelDelegate {
    public let store: LauncherStore
    public let panelController: LauncherPanelController
    public let resultExecutor: LauncherResultExecutor

    private let shortcutService: any ShortcutService
    private let settings: any SettingsService
    private let logger: any LoggingService

    public init(
        shortcutService: any ShortcutService,
        store: LauncherStore,
        panelController: LauncherPanelController,
        resultExecutor: LauncherResultExecutor,
        settings: any SettingsService,
        logger: any LoggingService
    ) {
        self.shortcutService = shortcutService
        self.store = store
        self.panelController = panelController
        self.resultExecutor = resultExecutor
        self.settings = settings
        self.logger = logger

        panelController.attach(delegate: self)
        shortcutService.onTrigger = { [weak self] in
            self?.panelController.toggle()
        }
    }

    public func launcherPanelDidRequestHide() {
        panelController.hide()
    }

    public func launcherPanelDidRequestExecute(_ result: SearchResult) {
        execute(result, hidesPanelOnSuccess: true)
    }

    public func executeInline(_ result: SearchResult) {
        execute(result, hidesPanelOnSuccess: false)
    }

    /// 应用启动时读取保存的快捷键,失败回退到 Option + Space。
    public func registerShortcutOnLaunch() async {
        let shortcut = settings.readLauncherShortcut() ?? .default
        let result = await shortcutService.register(shortcut)
        if case .failure(let error) = result {
            logger.log(Self.logShortcutBootstrap(reason: error.stableCode))
        }
    }

    private static func logShortcutBootstrap(reason: String) -> LogEvent {
        LogEvent(
            level: .warning,
            category: .lifecycle,
            message: "launcher.shortcut.bootstrap",
            stableCode: "W_SHORTCUT_BOOT",
            sanitizedContext: ["code": "W_SHORTCUT_BOOT", "reason": reason]
        )
    }

    private func execute(
        _ result: SearchResult,
        hidesPanelOnSuccess: Bool
    ) {
        let captured = result
        Task { [weak self] in
            guard let self else { return }
            let execResult = await self.resultExecutor.execute(captured)
            await MainActor.run {
                switch execResult {
                case .success:
                    if hidesPanelOnSuccess {
                        self.panelController.hide()
                    }
                case .failure(let error):
                    self.store.setTransientError(error)
                }
            }
        }
    }
}
