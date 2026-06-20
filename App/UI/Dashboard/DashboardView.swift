import SwiftUI

struct DashboardView: View {
    let onNavigate: @MainActor (AppDestination) -> Void

    init(onNavigate: @escaping @MainActor (AppDestination) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.cyan.opacity(0.05),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    DashboardBrandHeader()
                    DashboardDiskCard()
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
