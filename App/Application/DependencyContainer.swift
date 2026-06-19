import Foundation
import Observation

@Observable
@MainActor
public final class DependencyContainer {
    public let settings: any SettingsService
    public let logging: any LoggingService
    public let shortcutService: any ShortcutService
    public let launcherCoordinator: LauncherCoordinator
    public let mainNavigator: MainWindowNavigator

    public init(
        settings: any SettingsService,
        logging: any LoggingService,
        shortcutService: any ShortcutService,
        launcherCoordinator: LauncherCoordinator,
        mainNavigator: MainWindowNavigator
    ) {
        self.settings = settings
        self.logging = logging
        self.shortcutService = shortcutService
        self.launcherCoordinator = launcherCoordinator
        self.mainNavigator = mainNavigator
    }

    public static func production() -> DependencyContainer {
        let settings = UserDefaultsSettingsService()
        let logging = OSLogLoggingService()
        let shortcut = CarbonShortcutService(logger: logging)

        let navigator = MainWindowNavigator()
        let commandProvider = CommandSearchProvider()
        let applicationIndex = ApplicationIndex(discover: {
            await SystemApplicationDiscovery.discover()
        })
        let applicationResourceCache = ApplicationResourceCache {
            Task(priority: .utility) {
                await applicationIndex.refresh()
            }
        }
        let commandExecutor = LauncherCommandExecutor(navigator: navigator)
        let applicationLauncher = ApplicationLauncher(
            logger: logging,
            resourceCache: applicationResourceCache
        )
        let fileLauncher = FileLauncher(logger: logging)
        let resultExecutor = DefaultLauncherResultExecutor(
            commandExecutor: commandExecutor,
            applicationLauncher: applicationLauncher,
            fileLauncher: fileLauncher,
            logger: logging
        )
        let applicationProvider = ApplicationSearchProvider(index: applicationIndex)
        let fileProvider = SpotlightFileSearchProvider(
            backend: SpotlightFileSearchBackend(logger: logging),
            logger: logging
        )
        let searchService = DefaultSearchService(
            providers: [commandProvider, applicationProvider, fileProvider],
            logger: logging
        )
        let store = LauncherStore(service: searchService)
        let panelController = LauncherPanelController(
            store: store,
            applicationResourceCache: applicationResourceCache
        )
        let coordinator = LauncherCoordinator(
            shortcutService: shortcut,
            store: store,
            panelController: panelController,
            resultExecutor: resultExecutor,
            settings: settings,
            logger: logging
        )

        Task(priority: .utility) {
            await applicationIndex.prewarm()
        }

        return DependencyContainer(
            settings: settings,
            logging: logging,
            shortcutService: shortcut,
            launcherCoordinator: coordinator,
            mainNavigator: navigator
        )
    }
}
