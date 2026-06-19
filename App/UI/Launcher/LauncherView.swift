import SwiftUI

struct LauncherView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "Launcher",
            symbol: "magnifyingglass",
            summary: "全局快捷启动面板将在对应 change 中以独立 NSPanel 实现。",
            capabilitiesNotImplemented: [
                "全局快捷键",
                "应用索引",
                "搜索面板"
            ]
        )
    }
}

#Preview {
    LauncherView()
        .frame(width: 720, height: 540)
}
