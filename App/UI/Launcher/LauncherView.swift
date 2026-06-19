import SwiftUI

struct LauncherView: View {
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        PlaceholderFeatureView(
            title: "Launcher",
            symbol: "magnifyingglass",
            summary: "通过全局快捷键 Option + Space 唤起搜索面板。",
            capabilitiesNotImplemented: [
                "全局快捷键(设置中可改)",
                "应用搜索与启动",
                "Spotlight 文件搜索",
                "六个功能命令"
            ]
        )
        .overlay(alignment: .topTrailing) {
            Button {
                container.launcherCoordinator.panelController.show()
            } label: {
                Label("打开面板", systemImage: "rectangle.stack.badge.plus")
            }
            .padding()
        }
    }
}

#Preview {
    LauncherView()
        .environment(DependencyContainer.production())
        .frame(width: 720, height: 540)
}
