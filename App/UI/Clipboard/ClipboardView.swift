import SwiftUI

struct ClipboardView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "Clipboard",
            symbol: "doc.on.clipboard",
            summary: "剪切板管理将在 Clippo 集成 change 中提供。",
            capabilitiesNotImplemented: [
                "剪切板历史",
                "Clippo 数据迁移",
                "本地持久化"
            ]
        )
    }
}

#Preview {
    ClipboardView()
        .frame(width: 720, height: 540)
}
