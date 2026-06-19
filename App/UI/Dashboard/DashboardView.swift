import SwiftUI

struct DashboardView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "Dashboard",
            symbol: "square.grid.2x2",
            summary: "应用总览将在后续 change 中接入真实指标。",
            capabilitiesNotImplemented: [
                "磁盘占用概览",
                "近期操作日志",
                "权限状态摘要",
                "系统资源快照"
            ]
        )
    }
}

#Preview {
    DashboardView()
        .frame(width: 720, height: 540)
}
