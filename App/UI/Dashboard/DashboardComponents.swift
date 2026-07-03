import SwiftUI

struct DashboardBrandHeader: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                OmnipoTheme.deepBlack,
                                OmnipoTheme.deepRed.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(OmnipoTheme.brandRed.opacity(0.28), lineWidth: 1)
                Image("DashboardBrandIcon")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .padding(5)
            }
            .frame(width: 76, height: 76)
            .shadow(color: OmnipoTheme.brandRed.opacity(0.24), radius: 18, y: 8)

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
    let availability: DiskCapacityAvailability

    var body: some View {
        let presentation = DashboardDiskCardPresentation(availability: availability)

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("启动磁盘", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                statusBadge(presentation: presentation)
            }

            progressBar(presentation: presentation)

            HStack(spacing: 0) {
                DashboardDiskMetric(
                    value: presentation.usedValue,
                    title: "已用空间",
                    tint: OmnipoTheme.brandRed
                )
                Divider().frame(height: 34)
                DashboardDiskMetric(
                    value: presentation.availableValue,
                    title: "可用空间",
                    tint: OmnipoTheme.infoCyan
                )
                Divider().frame(height: 34)
                DashboardDiskMetric(
                    value: presentation.totalValue,
                    title: "总容量",
                    tint: .secondary
                )
            }

            Divider()

            Label(presentation.footerText, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(presentation.footerColor)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private func statusBadge(presentation: DashboardDiskCardPresentation) -> some View {
        Text(presentation.statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }

    private func progressBar(presentation: DashboardDiskCardPresentation) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [OmnipoTheme.brandRed.opacity(0.88), OmnipoTheme.deepRed.opacity(0.76)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * presentation.progressFraction)
            }
        }
        .frame(height: 10)
    }
}

private struct DashboardDiskMetric: View {
    let value: String
    let title: String
    let tint: Color?

    init(value: String, title: String, tint: Color? = nil) {
        self.value = value
        self.title = title
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
            HStack(spacing: 6) {
                if let tint {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

enum DiskCapacityFormatting {
    static func string(fromBytes bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.allowedUnits = [.useTB, .useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
}

struct DashboardDiskCardPresentation {
    let statusText: String
    let usedValue: String
    let availableValue: String
    let totalValue: String
    let footerText: String
    let progressFraction: CGFloat
    let state: DashboardDiskCardPresentationState

    init(
        availability: DiskCapacityAvailability
    ) {
        switch availability {
        case .idle, .loading:
            self.statusText = "读取中"
            self.usedValue = "…"
            self.availableValue = "…"
            self.totalValue = "…"
            self.footerText = "应用启动后正在读取启动卷容量，不会扫描目录或读取文件内容。"
            self.progressFraction = 0
            self.state = .loading
        case .available(let snapshot):
            self.statusText = "已更新"
            self.usedValue = DiskCapacityFormatting.string(fromBytes: snapshot.usedBytes)
            self.availableValue = DiskCapacityFormatting.string(fromBytes: snapshot.availableBytes)
            self.totalValue = DiskCapacityFormatting.string(fromBytes: snapshot.totalBytes)
            self.footerText = "容量来自启动卷只读元数据；最近更新于 \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))。"
            self.progressFraction = CGFloat(snapshot.utilizationFraction ?? 0)
            self.state = .available
        case .unavailable(let reason):
            self.statusText = "暂不可用"
            self.usedValue = "—"
            self.availableValue = "—"
            self.totalValue = "—"
            self.footerText = "\(reason.userDescription) 你仍可前往“磁盘清理”页手动重试。"
            self.progressFraction = 0
            self.state = .unavailable
        }
    }

    var statusColor: Color {
        switch state {
        case .loading:
            return .secondary
        case .available:
            return OmnipoTheme.brandRed
        case .unavailable:
            return .orange
        }
    }

    var footerColor: Color {
        switch state {
        case .unavailable:
            return .orange
        case .loading, .available:
            return .secondary
        }
    }

}

enum DashboardDiskCardPresentationState {
    case loading
    case available
    case unavailable
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
                            .foregroundStyle(OmnipoTheme.brandRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.title)
                                .font(.headline)
                            Text(shortcut.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                    .padding(16)
                    .background(
                        OmnipoTheme.subtleBrandGradient,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(OmnipoTheme.brandRed.opacity(0.14), lineWidth: 1)
                    }
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
