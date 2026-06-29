import SwiftUI

struct SystemMonitorView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    let onNavigate: @MainActor (AppDestination) -> Void

    init(onNavigate: @escaping @MainActor (AppDestination) -> Void = { _ in }) {
        self.onNavigate = onNavigate
    }

    var body: some View {
        let store = container.systemMonitorStore

        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.cyan.opacity(0.05),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    SystemMonitorHero(
                        intervalSeconds: store.intervalSeconds,
                        isActive: store.isActive,
                        hasSnapshot: store.snapshot != nil
                    )

                    SystemMonitorControls(
                        intervalSeconds: store.intervalSeconds,
                        onRefresh: { Task { await store.refresh() } },
                        onIntervalChange: { newValue in
                            Task { await store.setInterval(newValue) }
                        }
                    )

                    SystemMonitorTabPicker(selectedTab: Binding(
                        get: { store.selectedTab },
                        set: { store.selectedTab = $0 }
                    ))

                    SystemMonitorTabContent(
                        selectedTab: store.selectedTab,
                        snapshot: store.snapshot,
                        diskAvailability: appState.startupVolumeCapacity,
                        appUsage: store.appUsage,
                        appUsageRecords: store.sortedAppUsageRecords,
                        onNavigate: onNavigate
                    )
                }
                .frame(maxWidth: 860)
                .padding(.horizontal, 28)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            Task { await store.activate() }
        }
        .onDisappear {
            Task { await store.deactivate() }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SystemMonitorTabPicker: View {
    @Binding var selectedTab: SystemMonitorTab

    var body: some View {
        Picker("系统监控页面", selection: $selectedTab) {
            ForEach(SystemMonitorTab.allCases) { tab in
                Text(tab.title)
                    .tag(tab)
                    .accessibilityLabel(tab.accessibilityLabel)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .help("切换系统监控页面")
        .accessibilityLabel("系统监控页面标签")
        .accessibilityHint("切换纵览、CPU、内存、能耗、磁盘和网络页面")
    }
}

private struct SystemMonitorTabContent: View {
    let selectedTab: SystemMonitorTab
    let snapshot: SystemMetricSnapshot?
    let diskAvailability: DiskCapacityAvailability
    let appUsage: AppUsageAvailability
    let appUsageRecords: [AppUsageRecord]
    let onNavigate: @MainActor (AppDestination) -> Void

    var body: some View {
        Group {
            switch selectedTab {
            case .overview:
                SystemMonitorOverviewPage(
                    snapshot: snapshot,
                    diskAvailability: diskAvailability
                )
            case .cpu:
                VStack(spacing: 16) {
                    SystemMonitorCPUCard(snapshot: snapshot)
                    SystemMonitorAppUsageList(
                        availability: appUsage,
                        records: appUsageRecords,
                        ranking: .cpu
                    )
                }
            case .memory:
                VStack(spacing: 16) {
                    SystemMonitorMemoryCard(snapshot: snapshot)
                    SystemMonitorAppUsageList(
                        availability: appUsage,
                        records: appUsageRecords,
                        ranking: .memory
                    )
                }
            case .energy:
                VStack(spacing: 16) {
                    SystemMonitorEnergyCard(snapshot: snapshot)
                    SystemMonitorAppUsageList(
                        availability: appUsage,
                        records: appUsageRecords,
                        ranking: .energy
                    )
                }
            case .disk:
                VStack(spacing: 16) {
                    SystemMonitorDiskCard(
                        availability: diskAvailability,
                        onNavigate: onNavigate
                    )
                    SystemMonitorAppUsageList(
                        availability: appUsage,
                        records: appUsageRecords,
                        ranking: .disk
                    )
                }
            case .network:
                VStack(spacing: 16) {
                    SystemMonitorNetworkCard(snapshot: snapshot)
                    SystemMonitorAppUsageList(
                        availability: appUsage,
                        records: appUsageRecords,
                        ranking: .network
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SystemMonitorOverviewPage: View {
    let snapshot: SystemMetricSnapshot?
    let diskAvailability: DiskCapacityAvailability

    var body: some View {
        SystemMonitorOverviewSummary(
            snapshot: snapshot,
            diskAvailability: diskAvailability
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("系统监控纵览")
    }
}

private struct SystemMonitorOverviewSummary: View {
    let snapshot: SystemMetricSnapshot?
    let diskAvailability: DiskCapacityAvailability

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 142, maximum: 220), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            SystemMonitorSummaryTile(presentation: .cpu(snapshot))
            SystemMonitorSummaryTile(presentation: .memory(snapshot))
            SystemMonitorSummaryTile(presentation: .energy(snapshot))
            SystemMonitorSummaryTile(presentation: .disk(diskAvailability))
            SystemMonitorSummaryTile(presentation: .network(snapshot))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("整机资源摘要")
    }
}

private struct SystemMonitorSummaryTile: View {
    let presentation: SystemMonitorSummaryTilePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(presentation.tint)
                    .frame(width: 28, height: 28)
                    .background(presentation.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(presentation.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(presentation.value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(presentation.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(presentation.title)，\(presentation.value)，\(presentation.subtitle)")
    }
}

private struct SystemMonitorAppUsageList: View {
    let availability: AppUsageAvailability
    let records: [AppUsageRecord]
    let ranking: SystemMonitorAppUsageRanking

    var body: some View {
        let rankedRecords = ranking.sorted(records)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ranking.title)
                        .font(.headline)
                    Text(ranking.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            if let unsupportedMessage = ranking.unsupportedMessage {
                SystemMonitorAppUsageStateView(
                    symbolName: ranking.symbolName,
                    title: ranking.unsupportedTitle,
                    message: unsupportedMessage
                )
            } else {
                switch availability {
                case .idle, .loading:
                    SystemMonitorAppUsageStateView(
                        symbolName: "hourglass",
                        title: availability.isLoading ? "正在读取 APP 使用情况" : "等待 APP 使用采样",
                        message: "进入系统监控后会读取当前运行中应用的 CPU 与内存占用。"
                    )
                case .unavailable(let reason):
                    SystemMonitorAppUsageStateView(
                        symbolName: "exclamationmark.triangle",
                        title: "\(ranking.title)暂不可用",
                        message: reason.userDescription
                    )
                case .available(let snapshot):
                    if !ranking.hasUsableMetric(in: records), let unavailableMessage = ranking.metricUnavailableMessage {
                        SystemMonitorAppUsageStateView(
                            symbolName: ranking.symbolName,
                            title: "\(ranking.title)暂不可用",
                            message: unavailableMessage
                        )
                    } else if rankedRecords.isEmpty {
                        SystemMonitorAppUsageStateView(
                            symbolName: "app.dashed",
                            title: "当前没有可展示的运行中应用",
                            message: snapshot.unavailableReason?.userDescription ?? "没有读取到符合展示条件的运行中 APP。"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(rankedRecords) { record in
                                SystemMonitorAppUsageRow(
                                    record: record,
                                    ranking: ranking
                                )
                                if record.id != rankedRecords.last?.id {
                                    Divider()
                                        .padding(.leading, 48)
                                }
                            }
                        }
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        if ranking.unsupportedMessage != nil {
            return "不支持"
        }

        switch availability {
        case .idle: return "待采样"
        case .loading: return "读取中"
        case .available:
            return ranking.hasUsableMetric(in: records) || ranking.metricUnavailableMessage == nil
                ? "已更新"
                : "暂不可用"
        case .unavailable: return "暂不可用"
        }
    }

    private var statusColor: Color {
        if ranking.unsupportedMessage != nil {
            return .secondary
        }

        switch availability {
        case .available:
            return ranking.hasUsableMetric(in: records) || ranking.metricUnavailableMessage == nil
                ? .accentColor
                : .orange
        case .unavailable: return .orange
        case .idle, .loading: return .secondary
        }
    }
}

private enum SystemMonitorAppUsageRanking {
    case cpu
    case memory
    case energy
    case disk
    case network

    var title: String {
        switch self {
        case .cpu: return "APP CPU 使用排行"
        case .memory: return "APP 内存使用排行"
        case .energy: return "APP 能耗排行"
        case .disk: return "APP 磁盘使用排行"
        case .network: return "APP 网络使用排行"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: return "按当前 CPU 占有率降序排列。"
        case .memory: return "按当前内存占用降序排列。"
        case .energy: return "macOS 未提供可靠公开应用级能耗数据。"
        case .disk: return "当前磁盘页展示整机容量，不伪造应用级磁盘排行。"
        case .network: return "仅在存在可靠应用级网络归因时展示排行。"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .energy: return "bolt.slash"
        case .disk: return "internaldrive"
        case .network: return "network.slash"
        }
    }

    var unsupportedTitle: String {
        switch self {
        case .energy: return "APP 能耗排行暂不可用"
        case .disk: return "APP 磁盘排行暂不可用"
        case .cpu, .memory, .network: return "\(title)暂不可用"
        }
    }

    var unsupportedMessage: String? {
        switch self {
        case .energy:
            return "当前实现只读取整机电池状态；不调用私有能耗接口，也不展示不可靠的应用级能耗排行。"
        case .disk:
            return "当前实现只展示整机磁盘容量摘要；未采集应用级磁盘读写或占用排行。"
        case .cpu, .memory, .network:
            return nil
        }
    }

    var metricUnavailableMessage: String? {
        switch self {
        case .network:
            return "macOS 没有可靠公开 API 可将网络流量归因到应用；因此不展示应用级网络排行。"
        case .cpu, .memory, .energy, .disk:
            return nil
        }
    }

    var primaryTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .energy: return "能耗"
        case .disk: return "磁盘"
        case .network: return "网络"
        }
    }

    func sorted(_ records: [AppUsageRecord]) -> [AppUsageRecord] {
        records.sorted { lhs, rhs in
            switch self {
            case .cpu:
                return compare(
                    lhs: lhs,
                    rhs: rhs,
                    lhsPrimary: lhs.cpuPercent,
                    rhsPrimary: rhs.cpuPercent
                )
            case .memory:
                return compare(
                    lhs: lhs,
                    rhs: rhs,
                    lhsPrimary: lhs.memoryBytes.map(Double.init),
                    rhsPrimary: rhs.memoryBytes.map(Double.init)
                )
            case .network:
                return compare(
                    lhs: lhs,
                    rhs: rhs,
                    lhsPrimary: networkUsage(for: lhs),
                    rhsPrimary: networkUsage(for: rhs)
                )
            case .energy, .disk:
                return lhs.defaultSortPrecedes(rhs)
            }
        }
    }

    func primaryValue(for record: AppUsageRecord) -> String {
        switch self {
        case .cpu:
            return record.cpuPercent.map(SystemMonitorFormatting.appCPUText) ?? "—"
        case .memory:
            return record.memoryBytes.map(SystemMonitorFormatting.byteCountText) ?? "—"
        case .network:
            return networkUsage(for: record).map(SystemMonitorFormatting.rateText) ?? "—"
        case .energy, .disk:
            return "—"
        }
    }

    func hasUsableMetric(in records: [AppUsageRecord]) -> Bool {
        switch self {
        case .cpu:
            return records.contains { $0.cpuPercent != nil }
        case .memory:
            return records.contains { $0.memoryBytes != nil }
        case .network:
            return records.contains { networkUsage(for: $0) != nil }
        case .energy, .disk:
            return false
        }
    }

    private func networkUsage(for record: AppUsageRecord) -> Double? {
        let inbound = record.networkBytesInPerSec
        let outbound = record.networkBytesOutPerSec
        guard inbound != nil || outbound != nil else { return nil }
        return (inbound ?? 0) + (outbound ?? 0)
    }

    private func compare(
        lhs: AppUsageRecord,
        rhs: AppUsageRecord,
        lhsPrimary: Double?,
        rhsPrimary: Double?
    ) -> Bool {
        switch (lhsPrimary, rhsPrimary) {
        case let (lhsValue?, rhsValue?) where lhsValue != rhsValue:
            return lhsValue > rhsValue
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.defaultSortPrecedes(rhs)
        }
    }
}

private struct SystemMonitorAppUsageRow: View {
    let record: AppUsageRecord
    let ranking: SystemMonitorAppUsageRanking

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "app.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(record.bundleIdentifier ?? "未识别 Bundle ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(ranking.primaryValue(for: record))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(ranking.primaryTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 76, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 3) {
                Text(record.cpuPercent.map(SystemMonitorFormatting.appCPUText) ?? "—")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text("CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 58, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 3) {
                Text(record.memoryBytes.map(SystemMonitorFormatting.byteCountText) ?? "—")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("内存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(record.displayName)，\(ranking.primaryTitle) \(ranking.primaryValue(for: record))，CPU \(record.cpuPercent.map(SystemMonitorFormatting.appCPUText) ?? "不可用")，内存 \(record.memoryBytes.map(SystemMonitorFormatting.byteCountText) ?? "不可用")"
        )
    }
}

private struct SystemMonitorAppUsageStateView: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct SystemMonitorEnergyCard: View {
    let snapshot: SystemMetricSnapshot?

    var body: some View {
        let presentation = SystemMonitorEnergyCardPresentation(snapshot: snapshot)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(presentation.accentColor)
                    .frame(width: 40, height: 40)
                    .background(presentation.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("能耗")
                        .font(.headline)
                    Text("电量、充放电状态与整机能耗降级提示。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(presentation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [presentation.accentColor.opacity(0.18), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(spacing: 8) {
                        Image(systemName: presentation.symbolName)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(presentation.accentColor)
                        Text(presentation.percentValue)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .frame(width: 136, height: 136)

                VStack(alignment: .leading, spacing: 12) {
                    Text(presentation.headline)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(presentation.summaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(presentation.machinePowerText, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(presentation.machinePowerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                SystemMonitorCPUMetric(
                    value: presentation.percentValue,
                    title: "电量",
                    tint: presentation.accentColor
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.stateValue,
                    title: "状态",
                    tint: presentation.stateTint
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.machinePowerValue,
                    title: "整机能耗",
                    tint: .orange
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
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("能耗卡")
    }
}

private struct SystemMonitorDiskCard: View {
    let availability: DiskCapacityAvailability
    let onNavigate: @MainActor (AppDestination) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            DashboardDiskCard(availability: availability)

            Button {
                onNavigate(.cleaner)
            } label: {
                Label("打开磁盘分析", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("打开磁盘分析页面")
            .accessibilityLabel("打开磁盘分析页面")
            .accessibilityHint("跳转到磁盘分析与清理视图")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SystemMonitorNetworkCard: View {
    let snapshot: SystemMetricSnapshot?

    var body: some View {
        let presentation = SystemMonitorNetworkCardPresentation(snapshot: snapshot)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("网络")
                        .font(.headline)
                    Text("整机接口上下行速率，不展示不可靠的应用级网络排行。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(presentation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()

                SystemMonitorDualRateBar(
                    inboundFraction: presentation.inboundFraction,
                    outboundFraction: presentation.outboundFraction
                )

                Text(presentation.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                SystemMonitorCPUMetric(
                    value: presentation.totalInboundValue,
                    title: "总下行",
                    tint: .green
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.totalOutboundValue,
                    title: "总上行",
                    tint: .cyan
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.interfaceCountValue,
                    title: "活跃接口",
                    tint: .secondary
                )
            }

            VStack(spacing: 10) {
                ForEach(presentation.interfaces) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.headline)
                                .monospaced()
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.inboundText)
                                .font(.callout.weight(.semibold))
                                .monospacedDigit()
                            Text(item.outboundText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.name)，\(item.inboundText)，\(item.outboundText)")
                }
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
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("网络卡")
    }
}

private struct SystemMonitorMemoryCard: View {
    let snapshot: SystemMetricSnapshot?

    var body: some View {
        let presentation = SystemMonitorMemoryCardPresentation(snapshot: snapshot)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "memorychip")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("内存")
                        .font(.headline)
                    Text("已用、可用与压缩内存概览。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(presentation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()

                SystemMonitorMemoryStackedBar(
                    usedFraction: presentation.usedFraction,
                    activeUsedFraction: presentation.activeUsedFraction,
                    availableFraction: presentation.availableFraction,
                    compressedFraction: presentation.compressedFraction
                )

                Text(presentation.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                SystemMonitorCPUMetric(
                    value: presentation.usedValue,
                    title: "已用",
                    tint: .accentColor
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.availableValue,
                    title: "可用",
                    tint: .green
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.compressedValue,
                    title: "压缩",
                    tint: .cyan
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
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("内存卡")
    }
}

private struct SystemMonitorDualRateBar: View {
    let inboundFraction: Double
    let outboundFraction: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green.opacity(0.78))
                        .frame(width: width * inboundFraction)
                    Spacer(minLength: 0)
                }
                .background(.quaternary.opacity(0.45), in: Capsule())
                .clipShape(Capsule())

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.cyan.opacity(0.82))
                        .frame(width: width * outboundFraction)
                    Spacer(minLength: 0)
                }
                .background(.quaternary.opacity(0.45), in: Capsule())
                .clipShape(Capsule())
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "总下行 \(SystemMonitorFormatting.percentText(from: inboundFraction))，总上行 \(SystemMonitorFormatting.percentText(from: outboundFraction))"
        )
    }
}

private struct SystemMonitorCPUCard: View {
    let snapshot: SystemMetricSnapshot?

    var body: some View {
        let presentation = SystemMonitorCPUCardPresentation(snapshot: snapshot)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("CPU")
                        .font(.headline)
                    Text("处理器占用、用户态与系统态分布。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(presentation.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .center, spacing: 20) {
                SystemMonitorCPURing(
                    fraction: presentation.busyFraction,
                    label: presentation.busyValue
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(presentation.headline)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    SystemMonitorCPUStackedBar(
                        userFraction: presentation.userFraction,
                        systemFraction: presentation.systemFraction,
                        idleFraction: presentation.idleFraction
                    )

                    Text(presentation.summaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                SystemMonitorCPUMetric(
                    value: presentation.userValue,
                    title: "用户态",
                    tint: .accentColor
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.systemValue,
                    title: "系统态",
                    tint: .cyan
                )
                Divider().frame(height: 34)
                SystemMonitorCPUMetric(
                    value: presentation.idleValue,
                    title: "空闲",
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
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CPU 卡")
    }
}

private struct SystemMonitorHero: View {
    let intervalSeconds: Double
    let isActive: Bool
    let hasSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.86), .cyan.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)
                .shadow(color: .green.opacity(0.16), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("系统监控")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("五张只读概览卡片都已接入真实指标或明确降级状态，便于快速观察整机资源。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                SystemMonitorBadge(
                    title: "采样间隔 \(Int(intervalSeconds)) 秒",
                    tint: .accentColor
                )
                SystemMonitorBadge(
                    title: isActive ? "页面已激活" : "页面未激活",
                    tint: isActive ? .green : .secondary
                )
                SystemMonitorBadge(
                    title: hasSnapshot ? "已有快照" : "等待首帧",
                    tint: hasSnapshot ? .blue : .orange
                )
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
    }
}

private struct SystemMonitorMemoryStackedBar: View {
    let usedFraction: Double
    let activeUsedFraction: Double
    let availableFraction: Double
    let compressedFraction: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: width * activeUsedFraction)
                Rectangle()
                    .fill(Color.green.opacity(0.75))
                    .frame(width: width * availableFraction)
                Rectangle()
                    .fill(Color.cyan.opacity(0.8))
                    .frame(width: width * compressedFraction)
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
            .background(.quaternary.opacity(0.45), in: Capsule())
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "已用 \(SystemMonitorFormatting.percentText(from: usedFraction))，可用 \(SystemMonitorFormatting.percentText(from: availableFraction))，压缩 \(SystemMonitorFormatting.percentText(from: compressedFraction))"
        )
    }
}

private struct SystemMonitorCPURing: View {
    let fraction: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 12)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [.accentColor, .cyan, .green],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("总占用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU 总占用 \(label)")
    }
}

private struct SystemMonitorCPUStackedBar: View {
    let userFraction: Double
    let systemFraction: Double
    let idleFraction: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: width * userFraction)
                Rectangle()
                    .fill(Color.cyan.opacity(0.82))
                    .frame(width: width * systemFraction)
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: width * idleFraction)
            }
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
            .background(.quaternary.opacity(0.45), in: Capsule())
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "用户态 \(SystemMonitorFormatting.percentText(from: userFraction))，系统态 \(SystemMonitorFormatting.percentText(from: systemFraction))，空闲 \(SystemMonitorFormatting.percentText(from: idleFraction))"
        )
    }
}

private struct SystemMonitorCPUMetric: View {
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
                .monospacedDigit()
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

private struct SystemMonitorCPUCardPresentation {
    let statusText: String
    let statusColor: Color
    let headline: String
    let busyValue: String
    let busyFraction: Double
    let userValue: String
    let systemValue: String
    let idleValue: String
    let userFraction: Double
    let systemFraction: Double
    let idleFraction: Double
    let summaryText: String
    let footerText: String
    let footerColor: Color

    init(snapshot: SystemMetricSnapshot?) {
        guard let cpu = snapshot?.cpu else {
            self.statusText = "读取中"
            self.statusColor = .secondary
            self.headline = "等待首帧"
            self.busyValue = "—"
            self.busyFraction = 0
            self.userValue = "—"
            self.systemValue = "—"
            self.idleValue = "—"
            self.userFraction = 0
            self.systemFraction = 0
            self.idleFraction = 1
            self.summaryText = "CPU 百分比需要首帧快照后才能开始展示。"
            self.footerText = "系统监控会在页面激活后持续采样，CPU 占用基于 user + system 差值计算。"
            self.footerColor = .secondary
            return
        }

        switch cpu {
        case .available(let metrics):
            self.statusText = "已更新"
            self.statusColor = .accentColor
            self.headline = "\(SystemMonitorFormatting.percentText(from: metrics.busyPercent)) 总占用"
            self.busyValue = SystemMonitorFormatting.percentText(from: metrics.busyPercent)
            self.busyFraction = metrics.busyPercent
            self.userValue = SystemMonitorFormatting.percentText(from: metrics.userPercent)
            self.systemValue = SystemMonitorFormatting.percentText(from: metrics.systemPercent)
            self.idleValue = SystemMonitorFormatting.percentText(from: metrics.idlePercent)
            self.userFraction = metrics.userPercent
            self.systemFraction = metrics.systemPercent
            self.idleFraction = metrics.idlePercent
            self.summaryText = "用户态与系统态合并为总占用，空闲比例单独展示，便于快速判断是否存在持续负载。"
            self.footerText = "最近更新于 \(snapshot?.capturedAt.formatted(date: .omitted, time: .shortened) ?? "刚刚")。"
            self.footerColor = .secondary
        case .unavailable(let reason):
            self.statusText = reason == .warmup ? "预热中" : "暂不可用"
            self.statusColor = reason == .warmup ? .orange : .secondary
            self.headline = reason == .warmup ? "正在校准" : "暂不可用"
            self.busyValue = "—"
            self.busyFraction = 0
            self.userValue = "—"
            self.systemValue = "—"
            self.idleValue = "—"
            self.userFraction = 0
            self.systemFraction = 0
            self.idleFraction = 1
            self.summaryText = reason.userDescription
            self.footerText = reason == .warmup
                ? "CPU 百分比依赖连续两次采样做差，短暂预热后会显示真实占用。"
                : reason.userDescription
            self.footerColor = .orange
        }
    }
}

private struct SystemMonitorEnergyCardPresentation {
    let statusText: String
    let statusColor: Color
    let accentColor: Color
    let symbolName: String
    let headline: String
    let percentValue: String
    let stateValue: String
    let machinePowerValue: String
    let summaryText: String
    let machinePowerText: String
    let machinePowerColor: Color
    let stateTint: Color
    let footerText: String
    let footerColor: Color

    init(snapshot: SystemMetricSnapshot?) {
        guard let energy = snapshot?.energy else {
            self.statusText = "读取中"
            self.statusColor = .secondary
            self.accentColor = .yellow
            self.symbolName = "battery.100"
            self.headline = "等待首帧"
            self.percentValue = "—"
            self.stateValue = "等待采样"
            self.machinePowerValue = "不可用"
            self.summaryText = "能耗卡会在首帧快照到达后展示电量与充放电状态。"
            self.machinePowerText = "整机能耗瓦数在 macOS 上没有公开 API。"
            self.machinePowerColor = .orange
            self.stateTint = .secondary
            self.footerText = "我们只读取公开电池信息，不调用私有框架，也不会请求额外权限。"
            self.footerColor = .secondary
            return
        }

        switch energy {
        case .available(let metrics):
            let isCharging = metrics.isCharging ?? false
            let isOnExternalPower = metrics.isOnExternalPower ?? isCharging
            self.statusText = "已更新"
            self.statusColor = .accentColor
            self.accentColor = isOnExternalPower ? .green : .yellow
            self.symbolName = isCharging ? "battery.100.bolt" : (isOnExternalPower ? "powerplug" : "battery.75")
            self.headline = isCharging ? "正在充电" : (isOnExternalPower ? "接入电源适配器" : "使用电池供电")
            self.percentValue = metrics.batteryPercent.map(SystemMonitorFormatting.percentText) ?? "—"
            self.stateValue = isCharging ? "充电中" : (isOnExternalPower ? "外接电源" : "电池供电")
            self.machinePowerValue = "降级"
            self.summaryText = "电池信息来自 IOKit 公开接口；整机瓦数没有公开 API，因此只展示明确的降级说明。"
            self.machinePowerText = "macOS 未提供公开整机能耗 API。"
            self.machinePowerColor = .orange
            self.stateTint = isCharging ? .green : (isOnExternalPower ? .blue : .yellow)
            self.footerText = "最近更新于 \(snapshot?.capturedAt.formatted(date: .omitted, time: .shortened) ?? "刚刚")。"
            self.footerColor = .secondary
        case .unavailable(let reason):
            self.statusText = "暂不可用"
            self.statusColor = .orange
            self.accentColor = .orange
            self.symbolName = "battery.slash"
            self.headline = reason == .noBattery ? "当前设备无电池" : "暂不可用"
            self.percentValue = "—"
            self.stateValue = reason == .noBattery ? "无电池" : "不可用"
            self.machinePowerValue = "降级"
            self.summaryText = reason.userDescription
            self.machinePowerText = "macOS 未提供公开整机能耗 API。"
            self.machinePowerColor = .orange
            self.stateTint = .orange
            self.footerText = reason.userDescription
            self.footerColor = .orange
        }
    }
}

private struct SystemMonitorMemoryCardPresentation {
    let statusText: String
    let statusColor: Color
    let headline: String
    let usedValue: String
    let availableValue: String
    let compressedValue: String
    let usedFraction: Double
    let activeUsedFraction: Double
    let availableFraction: Double
    let compressedFraction: Double
    let summaryText: String
    let footerText: String
    let footerColor: Color

    init(snapshot: SystemMetricSnapshot?) {
        guard let memory = snapshot?.memory else {
            self.statusText = "读取中"
            self.statusColor = .secondary
            self.headline = "等待首帧"
            self.usedValue = "—"
            self.availableValue = "—"
            self.compressedValue = "—"
            self.usedFraction = 0
            self.activeUsedFraction = 0
            self.availableFraction = 0
            self.compressedFraction = 0
            self.summaryText = "内存卡会在首帧快照到达后展示整机内存分布。"
            self.footerText = "内存信息来自系统只读统计，不会扫描文件，也不会写入磁盘。"
            self.footerColor = .secondary
            return
        }

        switch memory {
        case .available(let metrics):
            let total = max(metrics.totalBytes, 1)
            let usedFraction = Double(metrics.usedBytes) / Double(total)
            let availableFraction = Double(metrics.availableBytes) / Double(total)
            let compressedBytes = metrics.compressedBytes ?? 0
            let compressedFraction = min(Double(compressedBytes) / Double(total), 1)
            let activeUsedFraction = max(usedFraction - compressedFraction, 0)

            self.statusText = "已更新"
            self.statusColor = .accentColor
            self.headline = "总内存 \(SystemMonitorFormatting.byteCountText(from: metrics.totalBytes))"
            self.usedValue = SystemMonitorFormatting.byteCountText(from: metrics.usedBytes)
            self.availableValue = SystemMonitorFormatting.byteCountText(from: metrics.availableBytes)
            self.compressedValue = SystemMonitorFormatting.byteCountText(from: compressedBytes)
            self.usedFraction = usedFraction
            self.activeUsedFraction = activeUsedFraction
            self.availableFraction = availableFraction
            self.compressedFraction = compressedFraction
            self.summaryText = "堆叠条展示已用、可用与压缩内存；总容量单独标注，便于快速判断当前余量。"
            self.footerText = "最近更新于 \(snapshot?.capturedAt.formatted(date: .omitted, time: .shortened) ?? "刚刚")。"
            self.footerColor = .secondary
        case .unavailable(let reason):
            self.statusText = "暂不可用"
            self.statusColor = .orange
            self.headline = "暂不可用"
            self.usedValue = "—"
            self.availableValue = "—"
            self.compressedValue = "—"
            self.usedFraction = 0
            self.activeUsedFraction = 0
            self.availableFraction = 0
            self.compressedFraction = 0
            self.summaryText = reason.userDescription
            self.footerText = reason.userDescription
            self.footerColor = .orange
        }
    }
}

private struct SystemMonitorNetworkCardPresentation {
    struct InterfacePresentation: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let inboundText: String
        let outboundText: String
    }

    let statusText: String
    let statusColor: Color
    let headline: String
    let totalInboundValue: String
    let totalOutboundValue: String
    let interfaceCountValue: String
    let inboundFraction: Double
    let outboundFraction: Double
    let summaryText: String
    let interfaces: [InterfacePresentation]
    let footerText: String
    let footerColor: Color

    init(snapshot: SystemMetricSnapshot?) {
        guard let network = snapshot?.network else {
            self.statusText = "读取中"
            self.statusColor = .secondary
            self.headline = "等待首帧"
            self.totalInboundValue = "—"
            self.totalOutboundValue = "—"
            self.interfaceCountValue = "0"
            self.inboundFraction = 0
            self.outboundFraction = 0
            self.summaryText = "网络卡会在首帧快照到达后展示各接口上下行速率。"
            self.interfaces = []
            self.footerText = "这里只展示整机接口速率；macOS 无可靠公开 API 可归因应用级网络排行。"
            self.footerColor = .secondary
            return
        }

        switch network {
        case .available(let metrics):
            let sortedInterfaces = metrics.interfaces.sorted {
                ($0.bytesInPerSec + $0.bytesOutPerSec) > ($1.bytesInPerSec + $1.bytesOutPerSec)
            }
            let activeInterfaces = sortedInterfaces.filter { $0.bytesInPerSec > 0 || $0.bytesOutPerSec > 0 }
            let displayed = Array((activeInterfaces.isEmpty ? sortedInterfaces : activeInterfaces).prefix(3))
            let peak = max(metrics.totalBytesInPerSec, metrics.totalBytesOutPerSec, 1)

            self.statusText = "已更新"
            self.statusColor = .accentColor
            self.headline = "总下行 \(SystemMonitorFormatting.rateText(from: metrics.totalBytesInPerSec))"
            self.totalInboundValue = SystemMonitorFormatting.rateText(from: metrics.totalBytesInPerSec)
            self.totalOutboundValue = SystemMonitorFormatting.rateText(from: metrics.totalBytesOutPerSec)
            self.interfaceCountValue = String(activeInterfaces.isEmpty ? displayed.count : activeInterfaces.count)
            self.inboundFraction = min(metrics.totalBytesInPerSec / peak, 1)
            self.outboundFraction = min(metrics.totalBytesOutPerSec / peak, 1)
            self.summaryText = activeInterfaces.isEmpty
                ? "已识别网络接口，正在等待连续采样后展示真实速率。"
                : "优先展示当前有流量的接口，便于快速观察整机网络活动。"
            self.interfaces = displayed.map {
                InterfacePresentation(
                    id: $0.name,
                    name: $0.name,
                    subtitle: "下行 \((SystemMonitorFormatting.rateText(from: $0.bytesInPerSec)))",
                    inboundText: "入 \((SystemMonitorFormatting.rateText(from: $0.bytesInPerSec)))",
                    outboundText: "出 \((SystemMonitorFormatting.rateText(from: $0.bytesOutPerSec)))"
                )
            }
            self.footerText = "最近更新于 \(snapshot?.capturedAt.formatted(date: .omitted, time: .shortened) ?? "刚刚")；不展示应用级网络排行。"
            self.footerColor = .secondary
        case .unavailable(let reason):
            self.statusText = "暂不可用"
            self.statusColor = .orange
            self.headline = "暂不可用"
            self.totalInboundValue = "—"
            self.totalOutboundValue = "—"
            self.interfaceCountValue = "0"
            self.inboundFraction = 0
            self.outboundFraction = 0
            self.summaryText = reason.userDescription
            self.interfaces = []
            self.footerText = "\(reason.userDescription) 不展示应用级网络排行。"
            self.footerColor = .orange
        }
    }
}

private struct SystemMonitorSummaryTilePresentation {
    let title: String
    let symbolName: String
    let value: String
    let subtitle: String
    let tint: Color

    static func cpu(_ snapshot: SystemMetricSnapshot?) -> Self {
        guard let cpu = snapshot?.cpu else {
            return .init(
                title: "CPU",
                symbolName: "cpu",
                value: "—",
                subtitle: "等待首帧",
                tint: .accentColor
            )
        }
        switch cpu {
        case .available(let metrics):
            return .init(
                title: "CPU",
                symbolName: "cpu",
                value: SystemMonitorFormatting.percentText(from: metrics.busyPercent),
                subtitle: "用户 \(SystemMonitorFormatting.percentText(from: metrics.userPercent)) / 系统 \(SystemMonitorFormatting.percentText(from: metrics.systemPercent))",
                tint: .accentColor
            )
        case .unavailable(let reason):
            return .init(
                title: "CPU",
                symbolName: "cpu",
                value: "—",
                subtitle: reason == .warmup ? "预热中" : reason.userDescription,
                tint: .orange
            )
        }
    }

    static func memory(_ snapshot: SystemMetricSnapshot?) -> Self {
        guard let memory = snapshot?.memory else {
            return .init(
                title: "内存",
                symbolName: "memorychip",
                value: "—",
                subtitle: "等待首帧",
                tint: .blue
            )
        }
        switch memory {
        case .available(let metrics):
            return .init(
                title: "内存",
                symbolName: "memorychip",
                value: SystemMonitorFormatting.byteCountText(from: metrics.usedBytes),
                subtitle: "可用 \(SystemMonitorFormatting.byteCountText(from: metrics.availableBytes))",
                tint: .blue
            )
        case .unavailable(let reason):
            return .init(
                title: "内存",
                symbolName: "memorychip",
                value: "—",
                subtitle: reason.userDescription,
                tint: .orange
            )
        }
    }

    static func energy(_ snapshot: SystemMetricSnapshot?) -> Self {
        guard let energy = snapshot?.energy else {
            return .init(
                title: "能耗",
                symbolName: "battery.100",
                value: "—",
                subtitle: "等待首帧",
                tint: .yellow
            )
        }
        switch energy {
        case .available(let metrics):
            let isCharging = metrics.isCharging ?? false
            let isOnExternalPower = metrics.isOnExternalPower ?? isCharging
            return .init(
                title: "能耗",
                symbolName: isCharging ? "battery.100.bolt" : (isOnExternalPower ? "powerplug" : "battery.75"),
                value: metrics.batteryPercent.map(SystemMonitorFormatting.percentText) ?? "—",
                subtitle: isCharging ? "充电中" : (isOnExternalPower ? "外接电源" : "电池供电"),
                tint: isOnExternalPower ? .green : .yellow
            )
        case .unavailable(let reason):
            return .init(
                title: "能耗",
                symbolName: "battery.slash",
                value: "—",
                subtitle: reason.userDescription,
                tint: .orange
            )
        }
    }

    static func disk(_ availability: DiskCapacityAvailability) -> Self {
        switch availability {
        case .idle:
            return .init(
                title: "磁盘",
                symbolName: "internaldrive",
                value: "—",
                subtitle: "等待容量读取",
                tint: .purple
            )
        case .loading:
            return .init(
                title: "磁盘",
                symbolName: "internaldrive",
                value: "—",
                subtitle: "读取中",
                tint: .purple
            )
        case .available(let snapshot):
            return .init(
                title: "磁盘",
                symbolName: "internaldrive",
                value: SystemMonitorFormatting.byteCountText(from: snapshot.usedBytes),
                subtitle: "可用 \(SystemMonitorFormatting.byteCountText(from: snapshot.availableBytes))",
                tint: .purple
            )
        case .unavailable(let reason):
            return .init(
                title: "磁盘",
                symbolName: "internaldrive",
                value: "—",
                subtitle: reason.userDescription,
                tint: .orange
            )
        }
    }

    static func network(_ snapshot: SystemMetricSnapshot?) -> Self {
        guard let network = snapshot?.network else {
            return .init(
                title: "网络",
                symbolName: "network",
                value: "—",
                subtitle: "等待首帧",
                tint: .green
            )
        }
        switch network {
        case .available(let metrics):
            return .init(
                title: "网络",
                symbolName: "network",
                value: SystemMonitorFormatting.rateText(from: metrics.totalBytesInPerSec),
                subtitle: "上行 \(SystemMonitorFormatting.rateText(from: metrics.totalBytesOutPerSec))",
                tint: .green
            )
        case .unavailable(let reason):
            return .init(
                title: "网络",
                symbolName: "network",
                value: "—",
                subtitle: reason.userDescription,
                tint: .orange
            )
        }
    }
}

private enum SystemMonitorFormatting {
    static func percentText(from fraction: Double) -> String {
        let value = max(0, min(1, fraction))
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func appCPUText(from fraction: Double) -> String {
        let value = max(0, fraction) * 100
        return "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    static func byteCountText(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.allowedUnits = [.useTB, .useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    static func rateText(from bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond.rounded())))/s"
    }

    static func usageText(from amount: Double) -> String {
        guard amount.isFinite else { return "0%" }
        if amount <= 1 {
            return percentText(from: amount)
        }
        return amount.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct SystemMonitorBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.1), in: Capsule())
    }
}

private struct SystemMonitorControls: View {
    let intervalSeconds: Double
    let onRefresh: () -> Void
    let onIntervalChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                onRefresh()
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("立即请求一次系统资源刷新")
            .accessibilityLabel("立即刷新所有指标")
            .accessibilityHint("保持当前采样间隔不变，立刻更新卡片数据")

            Divider()
                .frame(height: 22)

            Stepper(
                value: Binding(
                    get: { Int(intervalSeconds) },
                    set: { onIntervalChange(Double($0)) }
                ),
                in: Int(SystemMonitorInterval.minSeconds)...Int(SystemMonitorInterval.maxSeconds)
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                    Text("采样间隔")
                        .font(.callout)
                    Text("\(Int(intervalSeconds)) 秒")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
            .help("调整系统监控采样间隔")
            .accessibilityLabel("采样间隔 \(Int(intervalSeconds)) 秒,范围 1 到 30 秒")
            .accessibilityHint("使用方向键或步进按钮调整采样频率")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    SystemMonitorView()
        .environment(DependencyContainer.production())
        .environment(AppState(diskUsageService: DependencyContainer.production().diskUsageService))
        .frame(width: 860, height: 720)
}
