import AppKit
import SwiftUI

struct PermissionAuditView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var store: PermissionAuditStore?

    var body: some View {
        Group {
            if let store {
                PermissionAuditContent(store: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if store == nil {
                store = PermissionAuditStore(service: container.permissionAuditService)
            }
            await store?.loadIfNeeded()
        }
    }
}

private struct PermissionAuditContent: View {
    @Bindable var store: PermissionAuditStore
    @Environment(DependencyContainer.self) private var container

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
                VStack(alignment: .leading, spacing: 18) {
                    PermissionAuditHeader(
                        isLoading: store.state == .loading,
                        onRefresh: { Task { await store.refresh() } }
                    )

                    PermissionAuditFilterBar(store: store)

                    PermissionAuditStateView(
                        state: store.state,
                        applicationResourceCache: container.applicationResourceCache
                    )
                }
                .frame(maxWidth: 900, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onChange(of: store.query) { _, _ in
            Task { await store.refresh() }
        }
        .alert(
            "需要完全磁盘访问",
            isPresented: Binding(
                get: { store.isPermissionRequestPresented },
                set: { isPresented in
                    if isPresented == false {
                        store.dismissPermissionRequest()
                    }
                }
            )
        ) {
            Button("打开系统设置") {
                store.dismissPermissionRequest()
                PermissionAuditSettingsOpener.openFullDiskAccessSettings()
            }
            Button("稍后", role: .cancel) {
                store.dismissPermissionRequest()
            }
        } message: {
            Text("Omnipo 需要完全磁盘访问才能只读读取 macOS 权限数据库。授权后请回到此页面点击刷新。")
        }
        .accessibilityElement(children: .contain)
    }
}

private enum PermissionAuditSettingsOpener {
    static func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct PermissionAuditHeader: View {
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(OmnipoTheme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Permission Audit")
                    .font(.largeTitle.bold())
                Text("只读查看本机应用隐私授权状态")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRefresh) {
                Label(isLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
            .accessibilityLabel(isLoading ? "权限审计正在刷新" : "刷新权限审计")
        }
    }
}

private struct PermissionAuditFilterBar: View {
    @Bindable var store: PermissionAuditStore

    var body: some View {
        VStack(spacing: 12) {
            Picker("权限类别", selection: Binding(
                get: { store.query.category },
                set: { store.query.category = $0 }
            )) {
                Text("全部").tag(Optional<PermissionCategory>.none)
                ForEach(PermissionCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.symbolName)
                        .tag(Optional(category))
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用或 Bundle ID", text: Binding(
                    get: { store.query.searchText },
                    set: { store.query.searchText = $0 }
                ))
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PermissionAuditStateView: View {
    let state: PermissionAuditStore.LoadState
    @ObservedObject var applicationResourceCache: ApplicationResourceCache

    var body: some View {
        switch state {
        case .idle, .loading:
            PermissionAuditLoadingView()
        case .loaded(let result):
            PermissionAuditResultView(
                result: result,
                applicationResourceCache: applicationResourceCache
            )
        case .failed(let error):
            PermissionAuditFailureView(error: error)
        }
    }
}

private struct PermissionAuditLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取权限状态")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PermissionAuditResultView: View {
    let result: PermissionAuditResult
    @ObservedObject var applicationResourceCache: ApplicationResourceCache

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionAuditSummaryView(result: result)

            if result.isEmpty {
                PermissionAuditEmptyView()
            } else {
                if result.unavailableCategories.isEmpty == false {
                    PermissionAuditUnavailableCategoriesView(
                        unavailableCategories: result.unavailableCategories
                    )
                }

                if result.grants.isEmpty == false {
                    PermissionAuditList(
                        grants: result.grants,
                        applicationResourceCache: applicationResourceCache
                    )
                }
            }
        }
    }
}

private struct PermissionAuditSummaryView: View {
    let result: PermissionAuditResult

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            PermissionAuditSummaryTile(
                title: "授权记录",
                value: "\(result.summary.totalGrantCount)",
                symbolName: "list.bullet.rectangle",
                tint: OmnipoTheme.brandRed
            )
            PermissionAuditSummaryTile(
                title: "已授权",
                value: "\(result.summary.authorizedGrantCount)",
                symbolName: "checkmark.circle",
                tint: .green
            )
            PermissionAuditSummaryTile(
                title: "不可读取类别",
                value: "\(result.unavailableCategories.count)",
                symbolName: "exclamationmark.triangle",
                tint: .orange
            )
        }
    }
}

private struct PermissionAuditSummaryTile: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct PermissionAuditUnavailableCategoriesView: View {
    let unavailableCategories: [PermissionCategory: PermissionUnavailableReason]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("不可读取")
                .font(.headline)

            ForEach(unavailableCategories.keys.sorted { $0.sortOrder < $1.sortOrder }) { category in
                if let reason = unavailableCategories[category] {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: category.symbolName)
                            .foregroundStyle(.orange)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName)
                                .font(.callout.weight(.semibold))
                            Text(reason.userDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
    }
}

private struct PermissionAuditList: View {
    let grants: [AppPermissionGrant]
    @ObservedObject var applicationResourceCache: ApplicationResourceCache

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("授权明细")
                .font(.headline)

            LazyVStack(spacing: 8) {
                ForEach(grants) { grant in
                    PermissionAuditRow(
                        grant: grant,
                        applicationResourceCache: applicationResourceCache
                    )
                }
            }
        }
    }
}

private struct PermissionAuditRow: View {
    let grant: AppPermissionGrant
    @ObservedObject var applicationResourceCache: ApplicationResourceCache

    var body: some View {
        HStack(spacing: 12) {
            PermissionAuditAppIcon(
                grant: grant,
                resourceCache: applicationResourceCache,
                fallbackTint: statusTint
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(grant.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text("\(grant.category.displayName) · \(grant.bundleIdentifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            PermissionAuditStatusBadge(status: grant.status)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(grant.displayName), \(grant.category.displayName), \(grant.status.displayName)")
    }

    private var statusTint: Color {
        switch grant.status {
        case .authorized: return .green
        case .denied: return .red
        case .restricted, .notDetermined: return .orange
        case .unavailable, .unknown: return .secondary
        }
    }
}

private struct PermissionAuditAppIcon: View {
    let grant: AppPermissionGrant
    @ObservedObject var resourceCache: ApplicationResourceCache
    let fallbackTint: Color
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                fallbackIcon
            }
        }
        .frame(width: 34, height: 34)
        .task(id: "\(grant.iconIdentifier ?? "unknown"):\(resourceCache.generation)") {
            guard let iconIdentifier = grant.iconIdentifier else {
                image = nil
                return
            }
            image = resourceCache.icon(for: iconIdentifier)
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: grant.category.symbolName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(fallbackTint)
            .frame(width: 34, height: 34)
            .background(fallbackTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PermissionAuditStatusBadge: View {
    let status: PermissionGrantStatus

    var body: some View {
        Label(status.displayName, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private var tint: Color {
        switch status {
        case .authorized: return .green
        case .denied: return .red
        case .restricted, .notDetermined: return .orange
        case .unavailable, .unknown: return .secondary
        }
    }

    private var symbolName: String {
        switch status {
        case .authorized: return "checkmark.circle"
        case .denied: return "xmark.circle"
        case .restricted: return "lock.circle"
        case .notDetermined: return "questionmark.circle"
        case .unavailable: return "exclamationmark.triangle"
        case .unknown: return "questionmark.diamond"
        }
    }
}

private struct PermissionAuditEmptyView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("没有匹配的权限记录")
                .font(.headline)
            Text("当前筛选条件下没有可展示的授权状态或不可读取类别。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PermissionAuditFailureView: View {
    let error: AppError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("权限审计失败", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(error.userDescription)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    PermissionAuditView()
        .environment(DependencyContainer.production())
        .frame(width: 820, height: 620)
}
