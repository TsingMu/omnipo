import Foundation
import Observation

@Observable
@MainActor
public final class DependencyContainer {
    public let settings: any SettingsService
    public let logging: any LoggingService
    public let launchAtLoginService: any LaunchAtLoginService
    public let shortcutService: any ShortcutService
    public let diskUsageService: any DiskUsageService
    public let systemMonitorService: any SystemMonitorService
    public let appUsageSampler: any AppUsageSampling
    public let systemMonitorStore: SystemMonitorStore
    public let clipboardService: any ClipboardService
    public let permissionAuditService: any PermissionAuditService
    public let uninstallerService: any UninstallerService
    public let weChatStorageService: any WeChatStorageService
    public let weChatStorageAuthorizationManager: WeChatStorageAuthorizationManager
    public let authorizedRootManager: AuthorizedRootManager
    public var largeFileRevealService: LargeFileRevealService {
        LargeFileRevealService(rootManager: authorizedRootManager, logger: logging)
    }
    public let applicationResourceCache: ApplicationResourceCache
    public let launcherCoordinator: LauncherCoordinator
    public let clipboardCoordinator: ClipboardCoordinator
    public let mainNavigator: MainWindowNavigator

    public init(
        settings: any SettingsService,
        logging: any LoggingService,
        launchAtLoginService: any LaunchAtLoginService,
        shortcutService: any ShortcutService,
        diskUsageService: any DiskUsageService,
        systemMonitorService: any SystemMonitorService,
        appUsageSampler: any AppUsageSampling,
        systemMonitorStore: SystemMonitorStore,
        clipboardService: any ClipboardService,
        permissionAuditService: any PermissionAuditService,
        uninstallerService: any UninstallerService,
        weChatStorageService: any WeChatStorageService,
        weChatStorageAuthorizationManager: WeChatStorageAuthorizationManager,
        authorizedRootManager: AuthorizedRootManager,
        applicationResourceCache: ApplicationResourceCache,
        launcherCoordinator: LauncherCoordinator,
        clipboardCoordinator: ClipboardCoordinator,
        mainNavigator: MainWindowNavigator
    ) {
        self.settings = settings
        self.logging = logging
        self.launchAtLoginService = launchAtLoginService
        self.shortcutService = shortcutService
        self.diskUsageService = diskUsageService
        self.systemMonitorService = systemMonitorService
        self.appUsageSampler = appUsageSampler
        self.systemMonitorStore = systemMonitorStore
        self.clipboardService = clipboardService
        self.permissionAuditService = permissionAuditService
        self.uninstallerService = uninstallerService
        self.weChatStorageService = weChatStorageService
        self.weChatStorageAuthorizationManager = weChatStorageAuthorizationManager
        self.authorizedRootManager = authorizedRootManager
        self.applicationResourceCache = applicationResourceCache
        self.launcherCoordinator = launcherCoordinator
        self.clipboardCoordinator = clipboardCoordinator
        self.mainNavigator = mainNavigator
    }

    public static func production() -> DependencyContainer {
        let settings = UserDefaultsSettingsService()
        let logging = OSLogLoggingService()
        let launchAtLoginService = SystemLaunchAtLoginService()
        let shortcut = CarbonShortcutService(logger: logging)
        let authorizedRootManager = AuthorizedRootManager(settings: settings, logger: logging)
        let diskUsageService = SystemDiskUsageService(
            logger: logging,
            largeFileRootsProvider: { @MainActor in
                if let url = authorizedRootManager.currentRoot() {
                    return [url]
                }
                return []
            },
            largeFileRootsRelease: { @MainActor in
                authorizedRootManager.releaseRoot()
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
        let clipboardService = makeClipboardService(settings: settings, logging: logging)
        let permissionAuditService = DefaultPermissionAuditService(logger: logging)
        let uninstallerService = DefaultUninstallerService()
        let weChatStorageAuthorizationManager = WeChatStorageAuthorizationManager(
            settings: settings,
            logger: logging
        )
        let weChatStorageService = DefaultWeChatStorageService(
            resolver: WeChatStorageRootResolver(),
            scanner: WeChatStorageScanner(),
            userSelectedRootsProvider: { @MainActor in
                weChatStorageAuthorizationManager.currentRoots()
            },
            userSelectedRootsRelease: { @MainActor in
                weChatStorageAuthorizationManager.releaseRoots()
            },
            scanOptionsProvider: { @MainActor in
                WeChatStorageScanOptions(
                    includeSensitiveNames: weChatStorageAuthorizationManager.sensitiveNamesEnabled
                )
            }
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
        let clipboardPanelController = ClipboardPanelController(
            clipboardService: clipboardService,
            settings: settings,
            applicationResourceCache: applicationResourceCache
        )
        let clipboardCoordinator = ClipboardCoordinator(
            shortcutService: shortcut,
            panelController: clipboardPanelController,
            settings: settings,
            logger: logging
        )

        Task(priority: .utility) {
            await applicationIndex.prewarm()
        }

        return DependencyContainer(
            settings: settings,
            logging: logging,
            launchAtLoginService: launchAtLoginService,
            shortcutService: shortcut,
            diskUsageService: diskUsageService,
            systemMonitorService: systemMonitorService,
            appUsageSampler: appUsageSampler,
            systemMonitorStore: systemMonitorStore,
            clipboardService: clipboardService,
            permissionAuditService: permissionAuditService,
            uninstallerService: uninstallerService,
            weChatStorageService: weChatStorageService,
            weChatStorageAuthorizationManager: weChatStorageAuthorizationManager,
            authorizedRootManager: authorizedRootManager,
            applicationResourceCache: applicationResourceCache,
            launcherCoordinator: coordinator,
            clipboardCoordinator: clipboardCoordinator,
            mainNavigator: navigator
        )
    }

    internal static func makeClipboardService(
        settings: any SettingsService,
        logging: any LoggingService,
        locationProvider: () throws -> ClipboardStorageLocation = {
            try ClipboardStorageLocation.applicationSupport()
        },
        databaseProvider: (ClipboardStorageLocation) throws -> ClipboardDatabase = {
            try ClipboardDatabase(location: $0)
        },
        databaseInitializer: (ClipboardDatabase) throws -> Void = {
            try $0.initialize()
        }
    ) -> any ClipboardService {
        var initializationStage = "application-support"
        do {
            let location = try locationProvider()
            initializationStage = "sqlite"
            let database = try databaseProvider(location)
            initializationStage = "schema"
            try databaseInitializer(database)
            let repository = ClipboardRepository(database: database)
            let binaryStore = BinaryContentStore(rootDirectory: location.binaryPayloadsDirectory)
            let writer = SystemClipboardContentWriter()
            let pasteController = ClipboardPasteController(
                repository: repository,
                binaryStore: binaryStore,
                writer: writer
            )
            return DefaultClipboardService(
                settings: settings,
                repository: repository,
                binaryStore: binaryStore,
                pasteController: pasteController
            )
        } catch {
            logging.log(LogEvent(
                level: .error,
                category: .lifecycle,
                message: "clipboard.storage.initializationFailed",
                stableCode: "E_CLIPBOARD_STORAGE_INIT",
                sanitizedContext: [
                    "stage": initializationStage,
                    "reason": "initialization-failed"
                ]
            ))
            return UnavailableClipboardService()
        }
    }
}
