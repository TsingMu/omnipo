import SwiftUI

struct WeChatManagerView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var store: WeChatManagerStore?

    var body: some View {
        Group {
            if let store {
                content(for: store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        let store = WeChatManagerStore(service: container.weChatStorageService)
                        self.store = store
                        Task { await store.loadIfNeeded() }
                    }
            }
        }
        .navigationTitle("微信空间分析")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for store: WeChatManagerStore) -> some View {
        switch store.state {
        case .idle, .loading:
            loadingView(store: store)
        case .failed(let error):
            failedView(error: error, store: store)
        case .loaded(let result):
            loadedView(result: result, store: store)
        }
    }

    private func loadingView(store: WeChatManagerStore) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在扫描微信存储,只读取文件元数据…")
                .foregroundStyle(.secondary)
            Button("取消") { Task { await store.cancel() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(error: AppError, store: WeChatManagerStore) -> some View {
        ContentUnavailableView {
            Label("扫描失败", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 4) {
                Text(error.userDescription)
                Text("错误码: \(error.stableCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("重试") { Task { await store.refresh() } }
        }
    }

    private func loadedView(result: WeChatStorageScanResult, store: WeChatManagerStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(result: result, store: store)
                privacyNotice()
                if isEffectivelyEmpty(result) {
                    emptyView(result: result)
                } else {
                    summaryHeader
                    categoriesView(result: result)
                    if !result.topGroups.isEmpty {
                        topGroupsView(result: result)
                    }
                }
                if !result.issues.isEmpty {
                    issuesView(result: result)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(result: WeChatStorageScanResult, store: WeChatManagerStore) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("微信存储分析").font(.title2).fontWeight(.semibold)
                if hasReadableRoot(result) {
                    Text("总可见占用 \(Self.byteFormatter.string(fromByteCount: Int64(result.totalVisibleBytes)))")
                        .foregroundStyle(.secondary)
                } else {
                    Text(result.roots.isEmpty ? "未发现可见存储" : "可见占用暂不可用")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("刷新微信存储分析")
        }
    }

    private func privacyNotice() -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
            Text("Omnipo 只统计文件元数据(大小、修改时间),不读取聊天内容、联系人、账号或媒体内容。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func isEffectivelyEmpty(_ result: WeChatStorageScanResult) -> Bool {
        result.totalVisibleBytes == 0 && result.topGroups.isEmpty
    }

    private func hasReadableRoot(_ result: WeChatStorageScanResult) -> Bool {
        result.roots.contains { root in
            if case .readable = root.availability { return true }
            return false
        }
    }

    private func emptyView(result: WeChatStorageScanResult) -> some View {
        let hasReadableRoot = hasReadableRoot(result)
        let title: String
        let description: String

        if result.roots.isEmpty {
            title = "未发现微信存储"
            description = "未在常见位置找到微信数据。若已安装,可能需要在系统设置授予完全磁盘访问。"
        } else if !hasReadableRoot {
            title = "微信存储不可读"
            description = "已发现微信存储位置,但当前均无法读取。请查看下方说明与限制。"
        } else {
            title = "可读微信存储为空"
            description = "当前可读取的微信存储中没有发现占用数据。"
        }

        return ContentUnavailableView {
            Label(title, systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text(description)
        }
    }

    private var summaryHeader: some View {
        Text("分类占用(仅元数据,类别由路径推断,不读取内容)")
            .font(.headline)
    }

    private func categoriesView(result: WeChatStorageScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(result.categories) { category in
                categoryRow(category: category)
            }
        }
    }

    private func categoryRow(category: WeChatStorageCategorySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.category.displayName).fontWeight(.medium)
                Spacer()
                Text("\(category.fileCount) 项 · \(Self.byteFormatter.string(fromByteCount: Int64(category.sizeBytes)))")
                    .foregroundStyle(.secondary)
            }
            Text(category.category.privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
    }

    private func topGroupsView(result: WeChatStorageScanResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("占用较大的分组").font(.headline)
            ForEach(result.topGroups) { group in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        // 仅展示脱敏分组名,不暴露可能含账号/联系人的原始路径。
                        Text(group.displayName).foregroundStyle(.primary)
                        Text(group.category.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Self.byteFormatter.string(fromByteCount: Int64(group.sizeBytes)))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func issuesView(result: WeChatStorageScanResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明与限制").font(.headline)
            ForEach(result.issues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.reason.displayName).fontWeight(.medium)
                        if let display = issue.sanitizedDisplayName {
                            Text("相关:\(display)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

#Preview {
    WeChatManagerView()
        .frame(width: 720, height: 540)
        .environment(DependencyContainer.production())
}
