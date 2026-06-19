import SwiftUI

struct PlaceholderFeatureView: View {
    let title: String
    let symbol: String
    let summary: String
    var capabilitiesNotImplemented: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.largeTitle.bold())
            }

            Text(summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !capabilitiesNotImplemented.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Phase 0 暂未实现", systemImage: "sparkles")
                        .font(.headline)
                    ForEach(capabilitiesNotImplemented, id: \.self) { capability in
                        Label(capability, systemImage: "circle.dashed")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    PlaceholderFeatureView(
        title: "示例",
        symbol: "tray",
        summary: "示例描述。",
        capabilitiesNotImplemented: ["扫描", "导出"]
    )
}
