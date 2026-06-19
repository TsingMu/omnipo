import SwiftUI

struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var selection: AppDestination = .dashboard
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState
        return NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
        } detail: {
            selection.detailView
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
        }
    }

    private var sidebar: some View {
        List(AppDestination.allCases, selection: $selection) { destination in
            Label(destination.title, systemImage: destination.symbol)
                .tag(destination)
                .accessibilityIdentifier("nav.\(destination.rawValue)")
        }
        .navigationTitle("Omnipo")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
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
        .environment(AppState())
        .frame(width: 960, height: 640)
}
