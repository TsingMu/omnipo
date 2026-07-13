import SwiftUI

struct CleanerView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    OmnipoTheme.redWash,
                    OmnipoTheme.deepBlack.opacity(0.035),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(OmnipoTheme.brandGradient)
                            Image(systemName: "internaldrive")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 52, height: 52)

                        Text("Disk Analysis")
                            .font(.largeTitle.bold())
                    }

                    Text("查看启动卷容量，并在你授权的目录内分析最多 50 个大文件。分类和筛选只使用当前扫描结果的元数据。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    DashboardDiskCard(availability: appState.startupVolumeCapacity)

                    Button {
                        Task { await appState.refreshStartupVolumeCapacity() }
                    } label: {
                        Label("刷新容量", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("只刷新启动卷容量，不会开始目录扫描")

                    largeFileRootPicker

                    CleanerLargeFileSection(
                        availability: presentedLargeFileAvailability,
                        authorizedRootPath: container.authorizedRootManager.currentRootPathForDisplayGrouping(),
                        onRefresh: {
                            Task { await appState.refreshLargeFiles() }
                        },
                        onReveal: { record in
                            container.largeFileRevealService.reveal(
                                record: record,
                                currentRecords: presentedLargeFileAvailability.records
                            )
                        }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("当前只读边界", systemImage: "lock.shield")
                            .font(.headline)
                        Label("不会删除、移动、重命名或自动清理文件", systemImage: "checkmark.shield")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Label("不建立持久文件索引，也不代表全盘扫描结果", systemImage: "checkmark.shield")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await appState.loadLargeFilesIfNeeded()
        }
    }

    /// 大文件扫描根授权栏。
    /// Sandbox 下默认无法读取用户目录,需要用户主动通过 NSOpenPanel 授权某个目录,
    /// 由 AuthorizedRootManager 用 security-scoped bookmark 持久化。
    @ViewBuilder
    private var largeFileRootPicker: some View {
        let availability = container.authorizedRootManager.authorizationAvailability
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .foregroundStyle(availability.requiresReauthorization ? .orange : OmnipoTheme.brandRed)
            VStack(alignment: .leading, spacing: 2) {
                Text("大文件扫描目录")
                    .font(.headline)
                switch availability {
                case .notConfigured:
                    Text("尚未授权;点击右侧按钮选择需要扫描的目录(如“下载”或“文稿”)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .available:
                    Text("当前授权:\(container.authorizedRootManager.currentRootDisplayName() ?? "已选择目录")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                case .reauthorizationRequired(_, _, let reason):
                    Text("需要重新授权:\(reason.userDescription)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                Task { await pickRoot() }
            } label: {
                Label(rootPickerButtonTitle(for: availability),
                      systemImage: "folder")
            }
            if case .notConfigured = availability {
                EmptyView()
            } else {
                Button(role: .destructive) {
                    container.authorizedRootManager.clearRoot()
                    Task { await appState.refreshLargeFiles() }
                } label: {
                    Label("清除", systemImage: "xmark")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var presentedLargeFileAvailability: LargeFileAvailability {
        if container.authorizedRootManager.authorizationAvailability.requiresReauthorization {
            return .unavailable(reason: .permissionLimited)
        }
        return appState.largeFileAvailability
    }

    private func rootPickerButtonTitle(
        for availability: PersistedDirectoryAuthorizationAvailability
    ) -> String {
        switch availability {
        case .notConfigured: "选择目录…"
        case .available: "更换目录…"
        case .reauthorizationRequired: "重新选择…"
        }
    }

    private func pickRoot() async {
        let didPick = await container.authorizedRootManager.selectNewRoot()
        if didPick != nil {
            await appState.refreshLargeFiles()
        }
    }
}

#Preview {
    CleanerView()
        .environment(DependencyContainer.production())
        .environment(AppState(diskUsageService: DependencyContainer.production().diskUsageService))
        .frame(width: 720, height: 540)
}
