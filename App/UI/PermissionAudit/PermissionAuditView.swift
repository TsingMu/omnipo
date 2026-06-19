import SwiftUI

struct PermissionAuditView: View {
    var body: some View {
        PlaceholderFeatureView(
            title: "Permission Audit",
            symbol: "checkmark.shield",
            summary: "权限审计将以只读方式枚举已授权能力,不读取隐私内容。",
            capabilitiesNotImplemented: [
                "应用权限扫描",
                "权限分类视图",
                "降级与不可读取说明"
            ]
        )
    }
}

#Preview {
    PermissionAuditView()
        .frame(width: 720, height: 540)
}
