import SwiftUI

struct ClipboardPanelView: View {
    let clipboardService: any ClipboardService
    let settings: any SettingsService
    let pasteTargetProcessIdentifier: () -> pid_t?
    let onHide: () -> Void

    @State private var hasAcknowledgedNotice = false
    @State private var isEnabled = false
    @State private var records: [ClipboardItem] = []
    @State private var searchText = ""
    @State private var selectedContentType: ClipboardContentType?
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var message: String?
    @State private var isLoading = false
    @State private var isPerformingAction = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            if hasAcknowledgedNotice {
                queryBar
                Divider()
                historyList
                Divider()
                actionBar
            } else {
                firstRunNotice
            }
        }
        .frame(width: 460, height: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .task {
            await refreshState()
            isSearchFocused = true
        }
        .onChange(of: searchText) { _, _ in
            Task { await loadRecords() }
        }
        .onChange(of: selectedContentType) { _, _ in
            Task { await loadRecords() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardHistoryDidChange)) { _ in
            guard hasAcknowledgedNotice, isEnabled else { return }
            Task { await loadRecords() }
        }
        .onExitCommand(perform: onHide)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OmnipoTheme.brandRed)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard")
                    .font(.headline)
                Text(isEnabled ? "最近记录" : "记录已关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onHide) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭")
            .accessibilityLabel("关闭 Clipboard 面板")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var queryBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索剪切板记录", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)

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
            .frame(height: 34)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Picker("类型", selection: $selectedContentType) {
                Text("全部").tag(Optional<ClipboardContentType>.none)
                ForEach(ClipboardContentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var historyList: some View {
        Group {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(emptyTitle, systemImage: isEnabled ? "tray" : "pause.circle")
                        .font(.headline)
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(records) { item in
                            ClipboardPanelRow(
                                item: item,
                                isSelected: selectedItemID == item.id,
                                onSelect: { selectedItemID = item.id },
                                onDoubleClick: {
                                    selectedItemID = item.id
                                    Task { await activateItem(item.id) }
                                },
                                onToggleFavorite: {
                                    Task { await setFavorite(!item.isFavorite, for: item.id) }
                                },
                                onDelete: {
                                    Task { await delete(item.id) }
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let selectedItem {
                Label(selectedItem.contentType.displayName, systemImage: selectedItem.contentType.symbolName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("选择一条记录后复制或粘贴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await copySelectedItem() }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(selectedItemID == nil || isPerformingAction)
            .help("复制到剪切板")
            .accessibilityLabel("复制到剪切板")

            Button {
                Task { await pasteSelectedItem() }
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .disabled(selectedItemID == nil || isPerformingAction)
            .help("复制并粘贴")
            .accessibilityLabel("复制并粘贴")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var firstRunNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("首次启用前请确认", systemImage: "lock.shield")
                .font(.headline)
            Text("剪切板内容只保存在本机。确认前不会启动监听,也不会写入历史。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                Task { await acknowledgeAndEnable() }
            } label: {
                Label("确认并启用", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return records.first { $0.id == selectedItemID }
    }

    private var emptyTitle: String {
        isEnabled ? "还没有剪切板记录" : "剪切板记录已关闭"
    }

    private var emptyMessage: String {
        isEnabled ? "复制文本、图片或文件后会出现在这里。" : "可在主窗口 Clipboard 页面重新启用记录。"
    }

    private func acknowledgeAndEnable() async {
        switch await clipboardService.acknowledgeLocalStorageNotice() {
        case .success:
            await refreshState()
            isSearchFocused = true
        case .failure(let error):
            message = error.userDescription
        }
    }

    private func refreshState() async {
        hasAcknowledgedNotice = await clipboardService.hasAcknowledgedLocalStorageNotice
        isEnabled = await clipboardService.isEnabled
        if hasAcknowledgedNotice {
            await loadRecords()
        }
    }

    private func loadRecords() async {
        isLoading = true
        defer { isLoading = false }
        let query = ClipboardQuery(
            searchText: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            contentType: selectedContentType,
            limit: 30
        )
        switch await clipboardService.records(matching: query) {
        case .success(let items):
            records = items
            if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
                self.selectedItemID = nil
            }
        case .failure(let error):
            message = error.userDescription
            records = []
        }
    }

    private func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async {
        message = nil
        switch await clipboardService.setFavorite(isFavorite, for: itemID) {
        case .success:
            await loadRecords()
        case .failure(let error):
            message = error.userDescription
        }
    }

    private func delete(_ itemID: ClipboardItem.ID) async {
        message = nil
        switch await clipboardService.delete(itemID) {
        case .success:
            if selectedItemID == itemID {
                selectedItemID = nil
            }
            await loadRecords()
        case .failure(let error):
            message = error.userDescription
        }
    }

    private func copySelectedItem() async {
        guard let selectedItemID else { return }
        await copyItem(selectedItemID, hidesAfterCopy: false)
    }

    private func pasteSelectedItem() async {
        guard let selectedItemID else { return }
        await pasteItem(selectedItemID, hidesAfterCopiedOnly: false, hidesBeforePaste: true)
    }

    private func activateItem(_ itemID: ClipboardItem.ID) async {
        if settings.readBool(forKey: .clipboardAutoPaste) {
            await pasteItem(itemID, hidesAfterCopiedOnly: true, hidesBeforePaste: true)
        } else {
            await copyItem(itemID, hidesAfterCopy: true)
        }
    }

    private func copyItem(_ itemID: ClipboardItem.ID, hidesAfterCopy: Bool) async {
        message = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        switch await clipboardService.copyToPasteboard(itemID) {
        case .success:
            message = "已复制"
            if hidesAfterCopy {
                onHide()
            }
        case .failure(let error):
            message = error.userDescription
        }
    }

    private func pasteItem(
        _ itemID: ClipboardItem.ID,
        hidesAfterCopiedOnly: Bool,
        hidesBeforePaste: Bool
    ) async {
        message = nil
        isPerformingAction = true
        defer { isPerformingAction = false }
        let targetProcessIdentifier = pasteTargetProcessIdentifier()
        if hidesBeforePaste {
            onHide()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        switch await clipboardService.copyAndPaste(
            itemID,
            targetProcessIdentifier: targetProcessIdentifier
        ) {
        case .success(.pasted):
            message = "已粘贴"
            if !hidesBeforePaste {
                onHide()
            }
        case .success(.copiedOnly(let reason)):
            message = pasteFallbackMessage(for: reason)
            if hidesAfterCopiedOnly {
                onHide()
            }
        case .failure(let error):
            message = error.userDescription
        }
    }

    private func pasteFallbackMessage(for reason: String) -> String {
        switch reason {
        case "accessibility-permission-missing":
            return "已复制,缺少辅助功能权限"
        case "synthetic-paste-failed":
            return "已复制,系统粘贴事件未成功"
        default:
            return "已复制,\(reason)"
        }
    }
}

private struct ClipboardPanelRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.contentType.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OmnipoTheme.brandRed)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(previewText)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.contentType.displayName)
                    Text(item.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onToggleFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            .help(item.isFavorite ? "取消收藏" : "收藏")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("删除")
        }
        .padding(8)
        .background(
            isSelected ? OmnipoTheme.redTint : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onDoubleClick)
    }

    private var previewText: String {
        guard let textPreview = item.textPreview, !textPreview.isEmpty else {
            return item.contentType.displayName
        }
        return textPreview
    }
}
