import AppKit
import SwiftUI

struct WeChatManagerView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var store: WeChatManagerStore?

    var body: some View {
        Group {
            if let store {
                WeChatManagerContent(store: store)
            } else {
                WeChatManagerBootstrapView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if store == nil {
                store = WeChatManagerStore(
                    service: container.weChatStorageService,
                    authorizationManager: container.weChatStorageAuthorizationManager
                )
            }
            await store?.loadIfNeeded()
        }
    }
}

private struct WeChatManagerContent: View {
    @Bindable var store: WeChatManagerStore

    var body: some View {
        ZStack {
            WeChatManagerBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeChatManagerHeader(
                        isLoading: store.state == .loading,
                        onSelectDirectory: { Task { await store.selectUserRoots() } },
                        onRefresh: { Task { await store.refresh() } }
                    )

                    if case .reauthorizationRequired(
                        let validRootCount,
                        let invalidRootCount,
                        let reason
                    ) = store.authorizationAvailability {
                        WeChatAuthorizationRecoveryPanel(
                            validRootCount: validRootCount,
                            invalidRootCount: invalidRootCount,
                            reason: reason,
                            onReauthorize: { Task { await store.selectUserRoots() } }
                        )
                    }

                    stateContent
                }
                .frame(maxWidth: 900, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch store.state {
        case .idle, .loading:
            WeChatStorageLoadingPanel {
                Task { await store.cancel() }
            }
        case .failed(let error):
            WeChatStorageFailurePanel(error: error) {
                Task { await store.refresh() }
            }
        case .loaded(let result):
            WeChatStorageLoadedContent(
                result: result,
                store: store,
                authorizationAvailability: store.authorizationAvailability
            )
        }
    }
}

private struct WeChatAuthorizationRecoveryPanel: View {
    let validRootCount: Int
    let invalidRootCount: Int
    let reason: DirectoryAuthorizationRecoveryReason
    let onReauthorize: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(validRootCount > 0 ? "部分目录需要重新授权" : "微信目录需要重新授权")
                    .font(.headline)
                Text(recoveryMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("原因码: \(reason.stableCode)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Button("重新选择目录", action: onReauthorize)
                .buttonStyle(.borderedProminent)
        }
        .wechatPanel(padding: 16)
        .accessibilityElement(children: .contain)
    }

    private var recoveryMessage: String {
        if validRootCount > 0 {
            return "仍可扫描 \(validRootCount) 个有效目录;另有 \(invalidRootCount) 个授权已失效。请选择替代目录以恢复完整结果。"
        }
        return "\(invalidRootCount) 个已保存授权均无法使用。请重新选择目录;Omnipo 不会将其显示为 0 B 或无数据。"
    }
}

private struct WeChatManagerBackground: View {
    var body: some View {
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
    }
}

private struct WeChatManagerBootstrapView: View {
    var body: some View {
        ZStack {
            WeChatManagerBackground()
            ProgressView()
                .controlSize(.large)
        }
    }
}

private struct WeChatManagerHeader: View {
    let isLoading: Bool
    let onSelectDirectory: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    OmnipoTheme.brandGradient,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("微信存储")
                    .font(.largeTitle.bold())
                Text("只读分析本地占用，不读取聊天内容")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: onSelectDirectory) {
                    Label("选择目录", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .accessibilityLabel("选择微信数据目录")

                Button(action: onRefresh) {
                    Label(isLoading ? "扫描中" : "刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                .accessibilityLabel(isLoading ? "微信存储正在扫描" : "刷新微信存储分析")
            }
            .controlSize(.large)
        }
    }
}

private struct WeChatStorageLoadingPanel: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 4) {
                Text("正在扫描微信存储")
                    .font(.headline)
                Text("只读取文件大小、类型和修改时间")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("取消", action: onCancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .wechatPanel()
    }
}

private struct WeChatStorageFailurePanel: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
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
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .wechatPanel()
    }
}

private struct WeChatStorageLoadedContent: View {
    let result: WeChatStorageScanResult
    @Bindable var store: WeChatManagerStore
    let authorizationAvailability: PersistedDirectoryAuthorizationAvailability
    @State private var mode: WeChatStorageViewMode = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WeChatStoragePrivacyBanner(
                sensitiveNamesEnabled: store.sensitiveNamesEnabled,
                onToggleSensitiveNames: {
                    Task {
                        if store.sensitiveNamesEnabled {
                            await store.disableSensitiveNames()
                        } else {
                            await store.enableSensitiveNames()
                        }
                    }
                }
            )
            WeChatStorageSummaryGrid(result: result)

            if isEffectivelyEmpty {
                WeChatStorageEmptyPanel(
                    result: result,
                    authorizationAvailability: authorizationAvailability
                )
            } else {
                Picker("查看维度", selection: $mode) {
                    ForEach(WeChatStorageViewMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch mode {
                case .overview:
                    WeChatStorageAssetPanel(result: result)
                case .largeFiles:
                    WeChatStorageLargeFilesPanel(
                        result: result,
                        store: store
                    )
                case .conversations:
                    WeChatStorageConversationPanel(
                        result: result,
                        aliases: store.conversationAliases,
                        sensitiveNamesEnabled: store.sensitiveNamesEnabled,
                        onSetAlias: { name, conversationID in
                            store.setConversationAlias(name, for: conversationID)
                        }
                    )
                }
            }

            if !result.issues.isEmpty {
                WeChatStorageIssuesPanel(result: result)
            }
        }
    }

    private var isEffectivelyEmpty: Bool {
        result.totalVisibleBytes == 0
    }
}

private struct WeChatStoragePrivacyBanner: View {
    let sensitiveNamesEnabled: Bool
    let onToggleSensitiveNames: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(OmnipoTheme.brandRed)
                .frame(width: 36, height: 36)
                .background(OmnipoTheme.redTint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("隐私边界")
                    .font(.headline)
                Text("仅统计大小、类型和修改时间；不读取聊天或媒体内容。会话占用仅在识别到目录结构时匿名推断。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onToggleSensitiveNames) {
                Label(
                    sensitiveNamesEnabled ? "隐藏名称" : "显示名称",
                    systemImage: sensitiveNamesEnabled ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(.bordered)
            .tint(sensitiveNamesEnabled ? .orange : OmnipoTheme.brandRed)
            .help(sensitiveNamesEnabled ? "恢复匿名显示" : "显示真实文件名并设置本地聊天名称")
        }
        .wechatPanel(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct WeChatStorageSummaryGrid: View {
    let result: WeChatStorageScanResult

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            WeChatStorageMetricTile(
                title: "可见占用",
                value: hasReadableRoot ? Self.byteFormatter.string(fromByteCount: Int64(result.totalVisibleBytes)) : "—",
                symbol: "internaldrive",
                tint: OmnipoTheme.brandRed
            )
            WeChatStorageMetricTile(
                title: "大文件候选",
                value: "\(result.largeFiles.count)",
                symbol: "doc.badge.ellipsis",
                tint: OmnipoTheme.infoCyan
            )
            WeChatStorageMetricTile(
                title: "匿名会话",
                value: "\(result.conversations.count)",
                symbol: "bubble.left.and.bubble.right",
                tint: result.conversations.isEmpty ? .secondary : .green
            )
        }
    }

    private var readableRootCount: Int {
        result.roots.filter { root in
            if case .readable = root.availability { return true }
            return false
        }.count
    }

    private var hasReadableRoot: Bool {
        readableRootCount > 0
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct WeChatStorageMetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .wechatPanel(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct WeChatStorageEmptyPanel: View {
    let result: WeChatStorageScanResult
    let authorizationAvailability: PersistedDirectoryAuthorizationAvailability

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .wechatPanel()
    }

    private var hasReadableRoot: Bool {
        result.roots.contains { root in
            if case .readable = root.availability { return true }
            return false
        }
    }

    private var title: String {
        if case .reauthorizationRequired(let validCount, _, _) = authorizationAvailability,
           validCount == 0 {
            return "微信目录需要重新授权"
        }
        if result.roots.isEmpty { return "未发现微信存储" }
        if !hasReadableRoot { return "微信存储不可读" }
        return "可读微信存储为空"
    }

    private var description: String {
        if case .reauthorizationRequired(let validCount, let invalidCount, _) = authorizationAvailability,
           validCount == 0 {
            return "\(invalidCount) 个已保存目录授权已失效。请使用上方“重新选择目录”恢复访问。"
        }
        if result.roots.isEmpty {
            return "未在常见位置找到微信数据。可使用右上角“选择目录”授权一个微信数据目录。"
        }
        if !hasReadableRoot {
            return "已发现微信存储位置，但当前均无法读取。请查看下方说明与限制。"
        }
        return "当前可读取的微信存储中没有发现占用数据。"
    }
}

private struct WeChatStorageAssetPanel: View {
    let result: WeChatStorageScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeChatStorageSectionHeader(
                title: "文件类型占用",
                subtitle: "根据扩展名和系统文件类型推断",
                symbol: "chart.bar.xaxis"
            )

            if result.assets.isEmpty {
                Text("没有可分类的普通文件。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(result.assets.sorted { $0.sizeBytes > $1.sizeBytes }) { summary in
                        WeChatStorageAssetRow(summary: summary, totalBytes: result.totalVisibleBytes)
                        if summary.id != result.assets.sorted(by: { $0.sizeBytes > $1.sizeBytes }).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .wechatPanel()
    }
}

private struct WeChatStorageAssetRow: View {
    let summary: WeChatAssetSummary
    let totalBytes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                Image(systemName: summary.kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(summary.kind.tint)
                    .frame(width: 34, height: 34)
                    .background(summary.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                Text(summary.kind.displayName)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Self.byteFormatter.string(fromByteCount: Int64(summary.sizeBytes)))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    Text("\(summary.fileCount) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ProgressView(value: fraction)
                .tint(summary.kind.tint)
                .controlSize(.small)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(summary.sizeBytes) / Double(totalBytes))
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct WeChatStorageLargeFilesPanel: View {
    let result: WeChatStorageScanResult
    @Bindable var store: WeChatManagerStore
    @State private var kindFilter: WeChatAssetFilter = .all
    @State private var threshold: WeChatLargeFileThreshold = .fiftyMegabytes
    @State private var fileNameQuery = ""
    @State private var listMode: WeChatCleanupListMode = .candidates

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeChatStorageSectionHeader(
                title: "大文件",
                subtitle: result.sensitiveNamesIncluded ? "只读候选清单；真实文件名仅保留在本次扫描结果中" : "只读候选清单；匿名文件标签最多保留 500 项",
                symbol: "doc.badge.ellipsis"
            )

            HStack(spacing: 10) {
                if result.sensitiveNamesIncluded {
                    TextField("搜索文件名", text: $fileNameQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
                Spacer(minLength: 12)
                Picker("类型", selection: $kindFilter) {
                    ForEach(WeChatAssetFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 112)
                Picker("大小", selection: $threshold) {
                    ForEach(WeChatLargeFileThreshold.allCases) { threshold in
                        Text(threshold.displayName).tag(threshold)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
            }

            HStack(spacing: 10) {
                Picker("候选清单", selection: $listMode) {
                    ForEach(WeChatCleanupListMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)

                Spacer(minLength: 12)

                Text(selectionSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if listMode == .ignored {
                    Button {
                        store.restoreAllIgnoredLargeFiles()
                    } label: {
                        Label("全部恢复", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.ignoredLargeFileIDs.isEmpty)
                } else {
                    Button {
                        store.setLargeFileSelection(filteredFiles.map(\.id), selected: !allVisibleSelected)
                    } label: {
                        Label(allVisibleSelected ? "取消全选" : "全选当前", systemImage: allVisibleSelected ? "square" : "checkmark.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(filteredFiles.isEmpty)

                    Button {
                        store.ignoreSelectedLargeFiles()
                    } label: {
                        Label("忽略所选", systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.selectedLargeFileIDs.isEmpty)
                }
            }

            if filteredFiles.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: listMode.symbolName,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredFiles) { file in
                        WeChatStorageLargeFileRow(
                            file: file,
                            conversationName: conversationNames[file.conversationID ?? ""],
                            isSelected: store.isLargeFileSelected(file.id),
                            isIgnored: store.ignoredLargeFileIDs.contains(file.id),
                            onSelectionChanged: { selected in
                                store.setLargeFileSelection(file.id, selected: selected)
                            },
                            onRestore: { store.restoreIgnoredLargeFile(file.id) }
                        )
                        if file.id != filteredFiles.last?.id { Divider() }
                    }
                }
            }
        }
        .wechatPanel()
    }

    private var filteredFiles: [WeChatLargeFile] {
        result.largeFiles.filter { file in
            let matchesListMode: Bool
            switch listMode {
            case .candidates:
                matchesListMode = !store.ignoredLargeFileIDs.contains(file.id)
            case .selected:
                matchesListMode = store.selectedLargeFileIDs.contains(file.id)
            case .ignored:
                matchesListMode = store.ignoredLargeFileIDs.contains(file.id)
            }
            let matchesName = !result.sensitiveNamesIncluded
                || fileNameQuery.isEmpty
                || file.fileName?.localizedCaseInsensitiveContains(fileNameQuery) == true
            return matchesListMode
                && file.sizeBytes >= threshold.bytes
                && kindFilter.includes(file.kind)
                && matchesName
        }
    }

    private var allVisibleSelected: Bool {
        !filteredFiles.isEmpty && filteredFiles.allSatisfy { store.selectedLargeFileIDs.contains($0.id) }
    }

    private var selectionSummary: String {
        let bytes = store.selectedLargeFileBytes(in: result)
        return "已选 \(store.selectedLargeFileIDs.count) 项 · \(Self.byteFormatter.string(fromByteCount: Int64(bytes)))"
    }

    private var emptyTitle: String {
        switch listMode {
        case .candidates: return "没有符合条件的大文件"
        case .selected: return "尚未选择候选文件"
        case .ignored: return "没有已忽略文件"
        }
    }

    private var emptyDescription: String {
        switch listMode {
        case .candidates: return "可降低大小门槛或切换文件类型。"
        case .selected: return "在待处理清单中勾选需要进一步确认的文件。"
        case .ignored: return "忽略的文件仅在当前扫描结果中隐藏，可随时恢复。"
        }
    }

    private var conversationNames: [String: String] {
        Dictionary(uniqueKeysWithValues: result.conversations.map {
            ($0.conversationID, store.conversationAliases[$0.conversationID] ?? $0.displayName)
        })
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct WeChatStorageLargeFileRow: View {
    let file: WeChatLargeFile
    let conversationName: String?
    let isSelected: Bool
    let isIgnored: Bool
    let onSelectionChanged: (Bool) -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            if isIgnored {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("恢复到待处理清单")
                .accessibilityLabel("恢复 \(file.fileName ?? file.displayName)")
            } else {
                Toggle(
                    "选择 \(file.fileName ?? file.displayName)",
                    isOn: Binding(
                        get: { isSelected },
                        set: { newValue in onSelectionChanged(newValue) }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            Image(systemName: file.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(file.kind.tint)
                .frame(width: 34, height: 34)
                .background(file.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName ?? file.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(file.kind.displayName)
                    if let conversationName { Text("· \(conversationName)") }
                    if let modifiedAt = file.modifiedAt {
                        Text("·")
                        Text(modifiedAt, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let fileURL = file.fileURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
                .accessibilityLabel("在 Finder 中显示 \(file.fileName ?? file.displayName)")
            }
            Text(Self.byteFormatter.string(fromByteCount: Int64(file.sizeBytes)))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private enum WeChatCleanupListMode: String, CaseIterable, Identifiable {
    case candidates
    case selected
    case ignored

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .candidates: return "待处理"
        case .selected: return "已选"
        case .ignored: return "已忽略"
        }
    }

    var symbolName: String {
        switch self {
        case .candidates: return "line.3.horizontal.decrease.circle"
        case .selected: return "checkmark.square"
        case .ignored: return "eye.slash"
        }
    }
}

private struct WeChatStorageConversationPanel: View {
    let result: WeChatStorageScanResult
    let aliases: [String: String]
    let sensitiveNamesEnabled: Bool
    let onSetAlias: (String, String) -> Void
    @State private var threshold: WeChatConversationThreshold = .oneMegabyte
    @State private var editingConversation: WeChatConversationUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                WeChatStorageSectionHeader(
                    title: "聊天占用",
                    subtitle: sensitiveNamesEnabled ? "真实名称由你在本机设置" : "匿名目录推断，不读取消息数据库",
                    symbol: "bubble.left.and.bubble.right"
                )
                Spacer(minLength: 12)
                Picker("最小占用", selection: $threshold) {
                    ForEach(WeChatConversationThreshold.allCases) { threshold in
                        Text(threshold.displayName).tag(threshold)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            HStack(spacing: 16) {
                Label {
                    Text("已归属 \(Self.byteFormatter.string(fromByteCount: Int64(attributedBytes)))")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                Label {
                    Text("未归属 \(Self.byteFormatter.string(fromByteCount: Int64(result.unattributedBytes)))")
                } icon: {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if sensitiveNamesEnabled {
                Label("微信 4.x 会话索引已加密；本地名称仅保留到退出应用。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if result.conversations.isEmpty {
                ContentUnavailableView(
                    "暂未识别到聊天目录",
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: Text("当前微信版本或目录结构无法可靠归属；空间仍计入总占用。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredConversations) { conversation in
                        WeChatStorageConversationRow(
                            conversation: conversation,
                            displayName: aliases[conversation.id] ?? conversation.displayName,
                            canEditName: sensitiveNamesEnabled,
                            onEditName: { editingConversation = conversation }
                        )
                        if conversation.id != filteredConversations.last?.id { Divider() }
                    }
                }
                if filteredConversations.isEmpty {
                    ContentUnavailableView(
                        "没有符合条件的聊天",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("可降低最小占用门槛。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .wechatPanel()
        .sheet(item: $editingConversation) { conversation in
            WeChatConversationNameEditor(
                initialName: aliases[conversation.id] ?? "",
                anonymousName: conversation.displayName,
                onSave: { name in onSetAlias(name, conversation.id) }
            )
        }
    }

    private var filteredConversations: [WeChatConversationUsage] {
        result.conversations.filter { $0.sizeBytes >= threshold.bytes }
    }

    private var attributedBytes: Int {
        result.conversations.reduce(0) { $0 + $1.sizeBytes }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct WeChatStorageConversationRow: View {
    let conversation: WeChatConversationUsage
    let displayName: String
    let canEditName: Bool
    let onEditName: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: conversation.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(conversation.kind.tint)
                .frame(width: 34, height: 34)
                .background(conversation.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(conversation.confidence.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(conversation.confidence == .high ? .green : .orange)
                }
                Text(assetBreakdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                WeChatConversationAssetBar(
                    assets: conversation.assets,
                    totalBytes: conversation.sizeBytes
                )
            }
            Spacer(minLength: 12)
            if canEditName {
                Button(action: onEditName) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("设置本地聊天名称")
                .accessibilityLabel("设置 \(displayName) 的本地名称")
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.byteFormatter.string(fromByteCount: Int64(conversation.sizeBytes)))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text("\(conversation.fileCount) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var assetBreakdown: String {
        conversation.assets
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(3)
            .map { summary in
                let percentage = conversation.sizeBytes > 0
                    ? Double(summary.sizeBytes) / Double(conversation.sizeBytes) * 100
                    : 0
                let percentageText = percentage > 0 && percentage < 1
                    ? "<1%"
                    : "\(Int(percentage.rounded()))%"
                return "\(summary.kind.displayName) \(percentageText)"
            }
            .joined(separator: " · ")
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct WeChatConversationAssetBar: View {
    let assets: [WeChatAssetSummary]
    let totalBytes: Int

    var body: some View {
        GeometryReader { proxy in
            let visibleAssets = assets.filter { $0.sizeBytes > 0 }
            let spacing = CGFloat(max(0, visibleAssets.count - 1)) * 2
            let availableWidth = max(0, proxy.size.width - spacing)

            HStack(spacing: 2) {
                ForEach(visibleAssets) { asset in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(asset.kind.tint)
                        .frame(width: availableWidth * fraction(for: asset))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private func fraction(for asset: WeChatAssetSummary) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(asset.sizeBytes) / Double(totalBytes))
    }
}

private struct WeChatConversationNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let anonymousName: String
    let onSave: (String) -> Void

    init(initialName: String, anonymousName: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: initialName)
        self.anonymousName = anonymousName
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("设置聊天名称")
                    .font(.title2.bold())
                Text("名称仅保留在当前运行中，对应 \(anonymousName)。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("联系人或群名称", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("清除名称") {
                    onSave("")
                    dismiss()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("保存") {
                    onSave(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct WeChatStorageIssuesPanel: View {
    let result: WeChatStorageScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WeChatStorageSectionHeader(
                title: "说明与限制",
                subtitle: "部分位置未纳入当前统计",
                symbol: "exclamationmark.triangle"
            )

            VStack(spacing: 0) {
                ForEach(result.issues) { issue in
                    WeChatStorageIssueRow(issue: issue)
                    if issue.id != result.issues.last?.id {
                        Divider()
                    }
                }
            }

            if needsFullDiskAccessGuidance {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .foregroundStyle(OmnipoTheme.infoCyan)
                    Text("完全磁盘访问仅作为受保护目录的补充授权，授权后请返回并刷新。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        WeChatStoragePermissionSettings.openFullDiskAccess()
                    } label: {
                        Label("完全磁盘访问", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .wechatPanel()
    }

    private var needsFullDiskAccessGuidance: Bool {
        result.issues.contains {
            $0.reason == .tccOrSandboxLimited || $0.reason == .permissionLimited
        }
    }
}

private struct WeChatStorageIssueRow: View {
    let issue: WeChatStorageIssue

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: issue.reason.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(issue.reason.tint)
                .frame(width: 30, height: 30)
                .background(
                    issue.reason.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(issue.reason.displayName)
                        .font(.callout.weight(.semibold))
                    if let display = issue.sanitizedDisplayName {
                        Text(display)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(issue.reason.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct WeChatStorageSectionHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OmnipoTheme.brandRed)
                .frame(width: 30, height: 30)
                .background(OmnipoTheme.redTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum WeChatStorageViewMode: String, CaseIterable, Identifiable {
    case overview
    case largeFiles
    case conversations

    var id: Self { self }

    var displayName: String {
        switch self {
        case .overview: return "概览"
        case .largeFiles: return "大文件"
        case .conversations: return "聊天占用"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .largeFiles: return "doc.badge.ellipsis"
        case .conversations: return "bubble.left.and.bubble.right"
        }
    }
}

private enum WeChatAssetFilter: String, CaseIterable, Identifiable {
    case all
    case video
    case image
    case audio
    case document
    case archive
    case database
    case other

    var id: Self { self }

    var displayName: String {
        guard self != .all, let kind = WeChatAssetKind(rawValue: rawValue) else { return "全部类型" }
        return kind.displayName
    }

    func includes(_ kind: WeChatAssetKind) -> Bool {
        self == .all || rawValue == kind.rawValue
    }
}

private enum WeChatLargeFileThreshold: Int, CaseIterable, Identifiable {
    case all = 0
    case tenMegabytes = 10_485_760
    case fiftyMegabytes = 52_428_800
    case hundredMegabytes = 104_857_600
    case fiveHundredMegabytes = 524_288_000
    case oneGigabyte = 1_073_741_824

    var id: Self { self }
    var bytes: Int { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部大小"
        case .tenMegabytes: return "≥ 10 MB"
        case .fiftyMegabytes: return "≥ 50 MB"
        case .hundredMegabytes: return "≥ 100 MB"
        case .fiveHundredMegabytes: return "≥ 500 MB"
        case .oneGigabyte: return "≥ 1 GB"
        }
    }
}

private enum WeChatConversationThreshold: Int, CaseIterable, Identifiable {
    case all = 0
    case oneMegabyte = 1_048_576
    case tenMegabytes = 10_485_760
    case fiftyMegabytes = 52_428_800

    var id: Self { self }
    var bytes: Int { rawValue }

    var displayName: String {
        switch self {
        case .all: return "全部占用"
        case .oneMegabyte: return "≥ 1 MB"
        case .tenMegabytes: return "≥ 10 MB"
        case .fiftyMegabytes: return "≥ 50 MB"
        }
    }
}

private extension WeChatAssetKind {
    var symbolName: String {
        switch self {
        case .video: return "film"
        case .image: return "photo"
        case .audio: return "waveform"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .database: return "cylinder"
        case .other: return "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .video: return OmnipoTheme.brandRed
        case .image: return OmnipoTheme.infoCyan
        case .audio: return .orange
        case .document: return .blue
        case .archive: return .green
        case .database: return .purple
        case .other: return .secondary
        }
    }
}

private extension WeChatConversationKind {
    var symbolName: String {
        switch self {
        case .directMessage: return "person.crop.circle"
        case .group: return "person.2.circle"
        case .unknown: return "bubble.left"
        }
    }

    var tint: Color {
        switch self {
        case .directMessage: return OmnipoTheme.infoCyan
        case .group: return OmnipoTheme.brandRed
        case .unknown: return .orange
        }
    }
}

private extension WeChatStorageCategory {
    var symbolName: String {
        switch self {
        case .cache: return "archivebox"
        case .mediaAndFiles: return "photo.on.rectangle"
        case .logs: return "doc.text"
        case .databasesAndState: return "cylinder"
        case .backups: return "clock.arrow.circlepath"
        case .configuration: return "slider.horizontal.3"
        case .other: return "square.grid.2x2"
        }
    }

    var tint: Color {
        switch self {
        case .cache: return OmnipoTheme.brandRed
        case .mediaAndFiles: return OmnipoTheme.infoCyan
        case .logs: return .orange
        case .databasesAndState: return .purple
        case .backups: return .green
        case .configuration: return .blue
        case .other: return .secondary
        }
    }
}

private extension WeChatStorageAvailabilityReason {
    var symbolName: String {
        switch self {
        case .rootMissing: return "folder.badge.questionmark"
        case .permissionLimited, .tccOrSandboxLimited: return "lock.trianglebadge.exclamationmark"
        case .externalLinkSkipped: return "link"
        case .resourceUnavailable: return "questionmark.folder"
        case .scanCancelled: return "stop.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .permissionLimited, .tccOrSandboxLimited: return .orange
        case .externalLinkSkipped: return OmnipoTheme.infoCyan
        case .scanCancelled: return .secondary
        case .rootMissing, .resourceUnavailable, .unknown: return OmnipoTheme.brandRed
        }
    }
}

private extension View {
    func wechatPanel(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OmnipoTheme.cardStroke, lineWidth: 1)
            }
    }
}

private enum WeChatStoragePermissionSettings {
    static func openFullDiskAccess() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    WeChatManagerView()
        .frame(width: 900, height: 720)
        .environment(DependencyContainer.production())
}
