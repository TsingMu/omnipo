import SwiftUI

struct ClipboardView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var hasAcknowledgedNotice = false
    @State private var isEnabled = false
    @State private var errorMessage: String?
    @State private var records: [ClipboardItem] = []
    @State private var isLoadingRecords = false
    @State private var searchText = ""
    @State private var selectedContentType: ClipboardContentType?
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var actionMessage: String?
    @State private var isPerformingClipboardAction = false

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
                    header

                    if hasAcknowledgedNotice {
                        enabledControls
                        historySection
                    } else {
                        firstUseNotice
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                            .accessibilityLabel("剪切板错误:\(errorMessage)")
                    }

                    if let actionMessage {
                        Label(actionMessage, systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .accessibilityLabel("剪切板操作结果:\(actionMessage)")
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            await refreshState()
        }
        .onChange(of: searchText) { _, _ in
            Task {
                await loadRecords()
            }
        }
        .onChange(of: selectedContentType) { _, _ in
            Task {
                await loadRecords()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardHistoryDidChange)) { _ in
            guard hasAcknowledgedNotice, isEnabled else { return }
            Task {
                await loadRecords()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OmnipoTheme.brandGradient)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Clipboard")
                    .font(.largeTitle.bold())
                Text("记录最近复制内容,稍后可搜索、收藏或再次粘贴。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var firstUseNotice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("首次启用前请确认", systemImage: "lock.shield")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label("剪切板内容只保存在这台 Mac 的本地数据库和本地文件目录中。", systemImage: "internaldrive")
                Label("复制的密码、验证码、私钥、证件号等敏感内容也可能被记录。", systemImage: "exclamationmark.triangle")
                Label("确认前不会启动监听,也不会持久化任何剪切板内容。", systemImage: "pause.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button {
                Task {
                    await acknowledgeAndEnable()
                }
            } label: {
                Label("确认并启用", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var enabledControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isEnabled ? "record.circle" : "pause.circle")
                    .font(.title2)
                    .foregroundStyle(isEnabled ? OmnipoTheme.brandRed : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isEnabled ? "正在记录剪切板" : "剪切板记录已关闭")
                        .font(.headline)
                    Text(isEnabled ? "新复制的受支持内容会保存在本地。" : "不会监听或保存新内容,已有记录保留供后续管理。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("记录", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        Task {
                            await setEnabled(newValue)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("记录剪切板")
            }

            if !isEnabled {
                Button {
                    Task {
                        await setEnabled(true)
                    }
                } label: {
                    Label("重新启用记录", systemImage: "play.circle")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(historyTitle, systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Spacer()

                if isLoadingRecords {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在加载剪切板记录")
                }
            }

            queryControls
            selectionActions

            if records.isEmpty {
                ClipboardEmptyStateView(
                    symbolName: emptyState.symbolName,
                    title: emptyState.title,
                    message: emptyState.message
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { item in
                        ClipboardHistoryRow(
                            item: item,
                            isSelected: selectedItemID == item.id,
                            onSelect: {
                                selectedItemID = item.id
                            },
                            onToggleFavorite: {
                                Task {
                                    await setFavorite(!item.isFavorite, for: item.id)
                                }
                            },
                            onDelete: {
                                Task {
                                    await delete(item.id)
                                }
                            }
                        )
                        if item.id != records.last?.id {
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var selectionActions: some View {
        HStack(spacing: 8) {
            if let selectedItem {
                Label(selectedItem.contentType.displayName, systemImage: selectedItem.contentType.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("已选择\(selectedItem.contentType.displayName)记录")
            } else {
                Text("选择一条记录后可以复制或粘贴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isPerformingClipboardAction {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在执行剪切板操作")
            }

            Button {
                Task {
                    await copySelectedItem()
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(selectedItemID == nil || isPerformingClipboardAction)
            .help("复制到剪切板")
            .accessibilityLabel("复制到剪切板")

            Button {
                Task {
                    await pasteSelectedItem()
                }
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .disabled(selectedItemID == nil || isPerformingClipboardAction)
            .help("复制并粘贴")
            .accessibilityLabel("复制并粘贴")
        }
        .frame(minHeight: 28)
    }

    private var queryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索剪切板记录", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Picker("类型", selection: $selectedContentType) {
                Text("全部").tag(Optional<ClipboardContentType>.none)
                ForEach(ClipboardContentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("剪切板类型过滤")
        }
    }

    private var historyTitle: String {
        hasActiveQuery ? "筛选结果" : "最近记录"
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return records.first { $0.id == selectedItemID }
    }

    private var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedContentType != nil
    }

    private var emptyState: (symbolName: String, title: String, message: String) {
        if hasActiveQuery {
            return (
                "line.3.horizontal.decrease.circle",
                "没有匹配的记录",
                "换一个关键词或类型过滤后再试。"
            )
        }
        if isEnabled {
            return (
                "tray",
                "还没有剪切板记录",
                "复制一段文本、图片或文件后会出现在这里。"
            )
        }
        return (
            "pause.circle",
            "剪切板记录已关闭",
            "重新启用记录后,新复制的内容会出现在这里。"
        )
    }

    private func acknowledgeAndEnable() async {
        errorMessage = nil
        switch await container.clipboardService.acknowledgeLocalStorageNotice() {
        case .success:
            await refreshState()
        case .failure(let error):
            errorMessage = error.userDescription
        }
    }

    private func setEnabled(_ newValue: Bool) async {
        errorMessage = nil
        switch await container.clipboardService.setEnabled(newValue) {
        case .success:
            await refreshState()
        case .failure(let error):
            errorMessage = error.userDescription
            await refreshState()
        }
    }

    private func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async {
        errorMessage = nil
        actionMessage = nil
        switch await container.clipboardService.setFavorite(isFavorite, for: itemID) {
        case .success:
            await loadRecords()
        case .failure(let error):
            errorMessage = error.userDescription
        }
    }

    private func delete(_ itemID: ClipboardItem.ID) async {
        errorMessage = nil
        actionMessage = nil
        switch await container.clipboardService.delete(itemID) {
        case .success:
            if selectedItemID == itemID {
                selectedItemID = nil
            }
            await loadRecords()
        case .failure(let error):
            errorMessage = error.userDescription
        }
    }

    private func copySelectedItem() async {
        guard let selectedItemID else { return }
        errorMessage = nil
        actionMessage = nil
        isPerformingClipboardAction = true
        defer { isPerformingClipboardAction = false }

        switch await container.clipboardService.copyToPasteboard(selectedItemID) {
        case .success:
            actionMessage = "已复制到剪切板。"
        case .failure(let error):
            errorMessage = error.userDescription
        }
    }

    private func pasteSelectedItem() async {
        guard let selectedItemID else { return }
        errorMessage = nil
        actionMessage = nil
        isPerformingClipboardAction = true
        defer { isPerformingClipboardAction = false }

        switch await container.clipboardService.copyAndPaste(selectedItemID) {
        case .success(.pasted):
            actionMessage = "已复制并粘贴。"
        case .success(.copiedOnly(let reason)):
            actionMessage = "已复制到剪切板,自动粘贴未执行:\(pasteFallbackMessage(for: reason))。"
        case .failure(let error):
            errorMessage = error.userDescription
        }
    }

    private func refreshState() async {
        hasAcknowledgedNotice = await container.clipboardService.hasAcknowledgedLocalStorageNotice
        isEnabled = await container.clipboardService.isEnabled
        if hasAcknowledgedNotice {
            await loadRecords()
        }
    }

    private func loadRecords() async {
        isLoadingRecords = true
        defer { isLoadingRecords = false }

        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = ClipboardQuery(
            searchText: search,
            contentType: selectedContentType,
            limit: 50
        )
        switch await container.clipboardService.records(matching: query) {
        case .success(let items):
            records = items
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
        case .failure(let error):
            errorMessage = error.userDescription
            records = []
        }
    }

    private func pasteFallbackMessage(for reason: String) -> String {
        switch reason {
        case "accessibility-permission-missing":
            return "缺少辅助功能权限"
        case "synthetic-paste-failed":
            return "系统粘贴事件未成功"
        default:
            return reason
        }
    }
}

private struct ClipboardEmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbolName)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.contentType.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OmnipoTheme.brandRed)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(previewText)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(item.contentType.displayName)
                    Text(item.updatedAt, style: .relative)
                    if let source = item.sourceApplicationID, !source.isEmpty {
                        Text(source)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                .help(item.isFavorite ? "取消收藏" : "收藏")
                .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除")
                .accessibilityLabel("删除")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            isSelected ? OmnipoTheme.redTint : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .focusable()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("选择此剪切板记录")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "选择", onSelect)
        .accessibilityAction(named: item.isFavorite ? "取消收藏" : "收藏", onToggleFavorite)
        .accessibilityAction(named: "删除", onDelete)
    }

    private var previewText: String {
        guard let textPreview = item.textPreview, !textPreview.isEmpty else {
            return item.contentType.displayName
        }
        return textPreview
    }

    private var accessibilitySummary: String {
        var components = [
            previewText,
            item.contentType.displayName,
            isSelected ? "已选择" : "未选择"
        ]
        if item.isFavorite {
            components.append("已收藏")
        }
        if let source = item.sourceApplicationID, !source.isEmpty {
            components.append(source)
        }
        return components.joined(separator: ",")
    }
}

#Preview {
    ClipboardView()
        .environment(DependencyContainer.production())
        .frame(width: 720, height: 540)
}
