import SwiftUI

struct SystemMonitorView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "System Monitor",
            symbol: "chart.xyaxis.line",
            summary: "系统监控将在对应 change 中提供可取消的高频采样。",
            capabilitiesNotImplemented: [
                "CPU 与内存指标",
                "可配置采样频率",
                "可取消的后台任务"
            ]
        )
    }
}

#Preview {
    SystemMonitorView()
        .frame(width: 720, height: 540)
}
