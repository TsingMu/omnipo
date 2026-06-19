import SwiftUI

@main
struct OmnipoApp: App {
    @State private var container: DependencyContainer
    @State private var appState: AppState

    init() {
        let container = DependencyContainer.production()
        container.logging.log(.lifecycleStart())
        var initialState: AppDestination = .dashboard
        if container.settings.readBool(forKey: .reopenLastDestination),
           let stored = container.settings.readString(forKey: .lastOpenedDestinationKey),
           let destination = AppDestination(rawValue: stored) {
            initialState = destination
        }
        _container = State(initialValue: container)
        _appState = State(initialValue: AppState(lastOpenedDestination: initialState))
    }

    var body: some Scene {
        WindowGroup(id: "omnipo.main") {
            RootView()
                .environment(container)
                .environment(appState)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(container)
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
