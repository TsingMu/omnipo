import SwiftUI

@main
struct OmnipoApp: App {
    private let statusBarManager: StatusBarManager
    @State private var container: DependencyContainer
    @State private var appState: AppState

    init() {
        let container = DependencyContainer.production()
        statusBarManager = StatusBarManager(container: container)
        container.logging.log(.lifecycleStart())
        var initialState: AppDestination = .dashboard
        if container.settings.readBool(forKey: .reopenLastDestination),
           let stored = container.settings.readString(forKey: .lastOpenedDestinationKey),
           let destination = AppDestination(rawValue: stored) {
            initialState = destination
        }
        _container = State(initialValue: container)
        _appState = State(initialValue: AppState(
            lastOpenedDestination: initialState,
            diskUsageService: container.diskUsageService
        ))

        Task { @MainActor in
            await container.launcherCoordinator.registerShortcutOnLaunch()
        }
    }

    var body: some Scene {
        WindowGroup(id: "omnipo.main") {
            RootView()
                .environment(container)
                .environment(appState)
                .tint(OmnipoTheme.brandRed)
                .frame(minWidth: 720, minHeight: 480)
                .task {
                    statusBarManager.setup()
                }
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(container)
                .tint(OmnipoTheme.brandRed)
        }
    }
}

private extension LogEvent {
    static func lifecycleStart() -> LogEvent {
        LogEvent(
            level: .info,
            category: .lifecycle,
            message: "application.didLaunch",
            stableCode: "I_APP_LAUNCH"
        )
    }
}
