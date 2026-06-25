import SwiftUI

struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var selection: AppDestination = .dashboard
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var windowTitlebarHeight: CGFloat = 0

    var body: some View {
        @Bindable var appState = appState
        return GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                SidebarView(
                    selection: $selection,
                    windowTitlebarHeight: windowTitlebarHeight
                )
            } detail: {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(
                            height: MainWindowLayout.detailTopInset(
                                safeAreaTop: geometry.safeAreaInsets.top,
                                windowTitlebarHeight: windowTitlebarHeight
                            )
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    selection.detailView(onNavigate: navigate)
                }
                .navigationTitle(selection.title)
            }
            .background(WindowTitlebarHeightReader(height: $windowTitlebarHeight))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        container.launcherCoordinator.panelController.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("打开 Launcher")
                    .accessibilityLabel("打开 Launcher")
                }
            }
            .onChange(of: selection) { _, newValue in
                appState.lastOpenedDestination = newValue
                container.settings.write(newValue.rawValue, forKey: .lastOpenedDestinationKey)
                container.logging.log(.navigation(destination: newValue.rawValue))
            }
            .onChange(of: container.mainNavigator.pendingDestination) { _, newValue in
                if let newValue {
                    selection = newValue
                    container.mainNavigator.consumePendingDestination()
                }
            }
            .onChange(of: container.mainNavigator.openWindowRequestId) { _, _ in
                openWindow(id: "omnipo.main")
            }
            .task {
                if container.settings.readBool(forKey: .reopenLastDestination) {
                    if let stored = container.settings.readString(forKey: .lastOpenedDestinationKey),
                       let destination = AppDestination(rawValue: stored) {
                        selection = destination
                    }
                }
                if let pending = container.mainNavigator.pendingDestination {
                    selection = pending
                    container.mainNavigator.consumePendingDestination()
                }
                await appState.loadStartupVolumeCapacityIfNeeded()
            }
        }
    }

    private func navigate(to destination: AppDestination) {
        selection = destination
    }
}

private extension LogEvent {
    static func navigation(destination: String) -> LogEvent {
        LogEvent(
            level: .info,
            category: .navigation,
            message: "navigation.selected",
            stableCode: "I_NAVIGATION",
            sanitizedContext: ["destination": destination]
        )
    }
}

#Preview {
    RootView()
        .environment(DependencyContainer.production())
        .environment(AppState(diskUsageService: DependencyContainer.production().diskUsageService))
        .frame(width: 960, height: 640)
}
