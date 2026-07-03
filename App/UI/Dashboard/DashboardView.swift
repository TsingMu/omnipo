import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    let onNavigate: @MainActor (AppDestination) -> Void

    init(onNavigate: @escaping @MainActor (AppDestination) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OmnipoTheme.redWash,
                    OmnipoTheme.deepBlack.opacity(0.035),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    DashboardBrandHeader()
                    DashboardDiskCard(availability: appState.startupVolumeCapacity)
                    DashboardShortcutGrid(onNavigate: onNavigate)
                    DashboardSafetyNote()
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 28)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    DashboardView()
        .frame(width: 720, height: 540)
}
