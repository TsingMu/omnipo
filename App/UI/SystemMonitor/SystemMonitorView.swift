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

                    VStack(spacing: 16) {
                        SystemMonitorCPUCard(snapshot: store.snapshot)
                        SystemMonitorMemoryCard(snapshot: store.snapshot)
                        SystemMonitorEnergyCard(snapshot: store.snapshot)
                        SystemMonitorDiskCard(
                            availability: appState.startupVolumeCapacity,
                            onNavigate: onNavigate
                        )
                        SystemMonitorNetworkCard(snapshot: store.snapshot)
                    }
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
                    Text("活跃接口、上下行速率与总流量栏。")
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
            self.footerText = "首次采样后会识别接口，第二次及之后会根据差值计算速率。"
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
                : "优先展示当前有流量的接口，便于快速定位是谁在上网。"
            self.interfaces = displayed.map {
                InterfacePresentation(
                    id: $0.name,
                    name: $0.name,
                    subtitle: "下行 \((SystemMonitorFormatting.rateText(from: $0.bytesInPerSec)))",
                    inboundText: "入 \((SystemMonitorFormatting.rateText(from: $0.bytesInPerSec)))",
                    outboundText: "出 \((SystemMonitorFormatting.rateText(from: $0.bytesOutPerSec)))"
                )
            }
            self.footerText = "最近更新于 \(snapshot?.capturedAt.formatted(date: .omitted, time: .shortened) ?? "刚刚")。"
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
            self.footerText = reason.userDescription
            self.footerColor = .orange
        }
    }
}

private enum SystemMonitorFormatting {
    static func percentText(from fraction: Double) -> String {
        let value = max(0, min(1, fraction))
        return value.formatted(.percent.precision(.fractionLength(0)))
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
