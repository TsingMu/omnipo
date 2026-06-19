import SwiftUI

struct WeChatManagerView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "WeChat Manager",
            symbol: "bubble.left.and.bubble.right",
            summary: "微信空间分析只统计缓存体积,不解析聊天内容。",
            capabilitiesNotImplemented: [
                "微信缓存扫描",
                "类别体积分布",
                "缓存清理确认"
            ]
        )
    }
}

#Preview {
    WeChatManagerView()
        .frame(width: 720, height: 540)
}
