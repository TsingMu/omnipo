import Foundation
import Observation

@Observable
@MainActor
public final class DependencyContainer {
    public let settings: any SettingsService
    public let logging: any LoggingService
    public let shortcutService: any ShortcutService
    public let diskUsageService: any DiskUsageService
    public let systemMonitorService: any SystemMonitorService
    public let appUsageSampler: any AppUsageSampling
    public let systemMonitorStore: SystemMonitorStore
    public let authorizedRootManager: AuthorizedRootManager
    public let applicationResourceCache: ApplicationResourceCache
    public let launcherCoordinator: LauncherCoordinator
    public let mainNavigator: MainWindowNavigator

    public init(
        settings: any SettingsService,
        logging: any LoggingService,
        shortcutService: any ShortcutService,
        diskUsageService: any DiskUsageService,
        systemMonitorService: any SystemMonitorService,
        appUsageSampler: any AppUsageSampling,
        systemMonitorStore: SystemMonitorStore,
        authorizedRootManager: AuthorizedRootManager,
        applicationResourceCache: ApplicationResourceCache,
        launcherCoordinator: LauncherCoordinator,
        mainNavigator: MainWindowNavigator
    ) {
        self.settings = settings
        self.logging = logging
        self.shortcutService = shortcutService
        self.diskUsageService = diskUsageService
        self.systemMonitorService = systemMonitorService
        self.appUsageSampler = appUsageSampler
        self.systemMonitorStore = systemMonitorStore
        self.authorizedRootManager = authorizedRootManager
        self.applicationResourceCache = applicationResourceCache
        self.launcherCoordinator = launcherCoordinator
        self.mainNavigator = mainNavigator
    }

    public static func production() -> DependencyContainer {
        let settings = UserDefaultsSettingsService()
        let logging = OSLogLoggingService()
        let shortcut = CarbonShortcutService(logger: logging)
        let authorizedRootManager = AuthorizedRootManager(settings: settings)
        let diskUsageService = SystemDiskUsageService(
            logger: logging,
            largeFileRootsProvider: { @MainActor in
                if let url = authorizedRootManager.currentRoot() {
                    return [url]
                }
                return []
            }
        )
        let systemMonitorService = DefaultSystemMonitorService(
            logger: logging,
            diskUsageService: diskUsageService
        )
        let appUsageSampler = DefaultAppUsageSampler(logger: logging)
        let systemMonitorStore = SystemMonitorStore(
            service: systemMonitorService,
            appUsageSampler: appUsageSampler,
            settings: settings,
            intervalSeconds: settings.readSystemMonitorIntervalSeconds()
        )

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
        let fileLauncher = FileLauncher(
            logger: logging,
            settings: settings,
            authorizedRootManager: authorizedRootManager
        )
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
            diskUsageService: diskUsageService,
            systemMonitorService: systemMonitorService,
            appUsageSampler: appUsageSampler,
            systemMonitorStore: systemMonitorStore,
            authorizedRootManager: authorizedRootManager,
            applicationResourceCache: applicationResourceCache,
            launcherCoordinator: coordinator,
            mainNavigator: navigator
        )
    }
}
