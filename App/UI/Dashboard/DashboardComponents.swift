import SwiftUI

struct DashboardBrandHeader: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.92), .cyan.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)
            .shadow(color: .accentColor.opacity(0.22), radius: 16, y: 8)

            VStack(spacing: 5) {
                Text("Omnipo")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("清理磁盘、管理应用、看懂权限——你的本地 Mac 管家")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DashboardDiskCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("启动磁盘", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text("尚未扫描")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            Capsule()
                .fill(.quaternary)
                .frame(height: 10)

            HStack(spacing: 0) {
                DashboardDiskMetric(title: "已用空间")
                Divider().frame(height: 34)
                DashboardDiskMetric(title: "可用空间")
                Divider().frame(height: 34)
                DashboardDiskMetric(title: "总容量")
            }

            Divider()

            Label("前往“磁盘清理”开始扫描后，这里才会显示真实容量。", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }
}

private struct DashboardDiskMetric: View {
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Text("—")
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DashboardShortcutGrid: View {
    let onNavigate: @MainActor (AppDestination) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(DashboardShortcut.allCases) { shortcut in
                Button {
                    onNavigate(shortcut.destination)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: shortcut.symbol)
                            .font(.system(size: 22, weight: .medium))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title)
                                .font(.headline)
                            Text(shortcut.subtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.88), .blue.opacity(0.74)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开\(shortcut.title)页面")
            }
        }
    }
}

struct DashboardSafetyNote: View {
    var body: some View {
        Label(
            "扫描、清理、卸载和隐私读取均由你主动发起；删除操作必须再次确认。",
            systemImage: "checkmark.shield"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}
