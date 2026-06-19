import SwiftUI

struct CleanerView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "Cleaner",
            symbol: "sparkles",
            summary: "磁盘分析与清理将在全局扫描 change 中提供。",
            capabilitiesNotImplemented: [
                "磁盘扫描",
                "可清理项目列表",
                "废纸篓确认删除"
            ]
        )
    }
}

#Preview {
    CleanerView()
        .frame(width: 720, height: 540)
}
