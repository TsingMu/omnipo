import SwiftUI

struct UninstallerView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "Uninstaller",
            symbol: "trash.circle",
            summary: "应用卸载将在拖拽卸载 change 中提供。",
            capabilitiesNotImplemented: [
                "应用发现",
                "拖拽卸载",
                "关联文件清理"
            ]
        )
    }
}

#Preview {
    UninstallerView()
        .frame(width: 720, height: 540)
}
