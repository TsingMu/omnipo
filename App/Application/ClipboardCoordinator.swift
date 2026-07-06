import Foundation
import Observation

@MainActor
@Observable
public final class ClipboardCoordinator {
    public let panelController: ClipboardPanelController

    private let shortcutService: any ShortcutService
    private let settings: any SettingsService
    private let logger: any LoggingService

    public init(
        shortcutService: any ShortcutService,
        panelController: ClipboardPanelController,
        settings: any SettingsService,
        logger: any LoggingService
    ) {
        self.shortcutService = shortcutService
        self.panelController = panelController
        self.settings = settings
        self.logger = logger

        shortcutService.setTrigger(for: .clipboardPanel) { [weak self] in
            self?.panelController.toggle()
        }
    }

    public func registerShortcutOnLaunch() async {
        let shortcut = settings.readClipboardPanelShortcut() ?? shortcutService.defaultShortcut(for: .clipboardPanel)
        let result = await shortcutService.register(shortcut, for: .clipboardPanel)
        if case .failure(let error) = result {
            logger.log(Self.logShortcutBootstrap(reason: error.stableCode))
        }
    }

    private static func logShortcutBootstrap(reason: String) -> LogEvent {
        LogEvent(
            level: .warning,
            category: .lifecycle,
            message: "clipboard.shortcut.bootstrap",
            stableCode: "W_CLIPBOARD_SHORTCUT_BOOT",
            sanitizedContext: ["code": "W_CLIPBOARD_SHORTCUT_BOOT", "reason": reason]
        )
    }
}
