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

                    Text("当前阶段仅展示启动卷容量概览。目录分析、分类占用和清理建议将在后续 change 中提供。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    DashboardDiskCard(availability: appState.startupVolumeCapacity)

                    largeFileRootPicker

                    Button {
                        Task {
                            await appState.refreshStartupVolumeCapacity()
                            await appState.refreshLargeFiles()
                        }
                    } label: {
                        Label("刷新容量摘要与大文件", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)

                    CleanerLargeFileSection(
                        availability: appState.largeFileAvailability,
                        onRefresh: {
                            Task { await appState.refreshLargeFiles() }
                        }
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Phase 0 暂未实现", systemImage: "sparkles")
                            .font(.headline)
                        Label("目录分析", systemImage: "circle.dashed")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Label("分类占用", systemImage: "circle.dashed")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Label("清理建议", systemImage: "circle.dashed")
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
        let authorizedURL = container.authorizedRootManager.currentRoot()
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .foregroundStyle(OmnipoTheme.brandRed)
            VStack(alignment: .leading, spacing: 2) {
                Text("大文件扫描目录")
                    .font(.headline)
                if let name = container.authorizedRootManager.currentRootDisplayName() {
                    Text("当前授权:\(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("尚未授权;点击右侧按钮选择需要扫描的目录(如“下载”或“文稿”)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                Task { await pickRoot() }
            } label: {
                Label(authorizedURL == nil ? "选择目录…" : "更换目录…",
                      systemImage: "folder")
            }
            if authorizedURL != nil {
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
