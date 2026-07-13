import SwiftUI

/// 授权目录当前、最多 50 条扫描结果的只读分析工作台。
struct CleanerLargeFileSection: View {
    let availability: LargeFileAvailability
    let authorizedRootPath: String?
    let onRefresh: () -> Void
    let onReveal: (LargeFileRecord) -> LargeFileRevealResult

    @State private var store = LargeFileWorkbenchStore()

    init(
        availability: LargeFileAvailability,
        authorizedRootPath: String? = nil,
        onRefresh: @escaping () -> Void,
        onReveal: @escaping (LargeFileRecord) -> LargeFileRevealResult = { _ in .success }
    ) {
        self.availability = availability
        self.authorizedRootPath = authorizedRootPath
        self.onRefresh = onRefresh
        self.onReveal = onReveal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            boundaryNote
            if let revealMessage = store.revealMessage {
                Label(revealMessage, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch availability {
            case .idle:
                placeholder("尚未开始扫描。请先选择目录，再刷新目录分析。")
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取授权目录中的文件元数据…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .available:
                workbench
            case .unavailable(let reason):
                unavailableMessage(reason)
            }

            Label("只读分析：这里没有删除、移动、重命名或自动清理操作。", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("当前工作台仅提供只读分析")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: availability, initial: true) { _, newValue in
            if case .available(let records) = newValue {
                store.replaceSource(records, authorizedRootPath: authorizedRootPath)
            }
        }
        .onChange(of: authorizedRootPath) { _, newValue in
            if case .available(let records) = availability {
                store.replaceSource(records, authorizedRootPath: newValue)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(OmnipoTheme.brandRed)
            Text("大文件分析")
                .font(.headline)
            Spacer()
            Button(action: onRefresh) {
                Label("刷新目录分析", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityHint("只重新扫描当前授权目录，不刷新启动卷容量")
        }
    }

    private var boundaryNote: some View {
        Text("结果仅来自当前授权目录，最多显示 50 个文件；类型按扩展名近似分类，不验证文件内容。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var workbench: some View {
        summary
        filterControls

        switch store.emptyState {
        case .noSourceRecords:
            placeholder("当前授权范围内没有可读取的大文件。")
        case .noFilterMatches:
            VStack(alignment: .leading, spacing: 6) {
                placeholder("当前筛选条件没有匹配结果。")
                Button("清除筛选") { store.clearFilters() }
                    .controlSize(.small)
            }
        case .allCandidatesIgnored:
            VStack(alignment: .leading, spacing: 6) {
                placeholder("当前结果中的候选项已全部忽略。")
                Button("恢复全部忽略项") { store.restoreAllIgnored() }
                    .controlSize(.small)
            }
        case .hasResults:
            HStack {
                Button("选择当前可见项") { store.selectAllVisible() }
                    .controlSize(.small)
                if !store.selectedIDs.isEmpty {
                    Button("清除选择") { store.clearSelection() }
                        .controlSize(.small)
                }
                Spacer()
            }
            recordsList(store.visibleRecords)
        }

        reviewArea
    }

    private var summary: some View {
        let values = [
            ("可见文件", "\(store.summary.visibleCount)"),
            ("可见大小", format(bytes: store.summary.visibleBytes)),
            ("已选文件", "\(store.summary.selectedCount)"),
            ("已选大小", format(bytes: store.summary.selectedBytes))
        ]
        return HStack(spacing: 8) {
            ForEach(values, id: \.0) { value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.0).font(.caption2).foregroundStyle(.secondary)
                    Text(value.1).font(.callout.monospacedDigit()).lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("搜索当前结果", text: Binding(
                get: { store.query.text },
                set: { store.query.text = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("搜索当前大文件结果")

            HStack(spacing: 8) {
                optionalPicker("类型", selection: Binding(
                    get: { store.query.kind }, set: { store.query.kind = $0 }
                ), values: LargeFileKind.allCases, label: \.displayName)
                optionalPicker("大小", selection: Binding(
                    get: { store.query.sizeBucket }, set: { store.query.sizeBucket = $0 }
                ), values: LargeFileSizeBucket.allCases, label: \.displayName)
                optionalPicker("修改时间", selection: Binding(
                    get: { store.query.ageBucket }, set: { store.query.ageBucket = $0 }
                ), values: LargeFileAgeBucket.allCases, label: \.displayName)
            }

            HStack(spacing: 8) {
                optionalPicker("目录", selection: Binding(
                    get: { store.query.directory }, set: { store.query.directory = $0 }
                ), values: store.directories, label: \.displayName)
                Picker("排序", selection: Binding(
                    get: { store.query.sortOrder }, set: { store.query.sortOrder = $0 }
                )) {
                    ForEach(LargeFileSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("排序方式")
                Spacer()
                if store.query.hasFilters {
                    Button("清除筛选") { store.clearFilters() }
                        .controlSize(.small)
                }
            }
        }
    }

    private func optionalPicker<Value: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<Value?>,
        values: [Value],
        label: KeyPath<Value, String>
    ) -> some View {
        Picker(title, selection: selection) {
            Text("全部\(title)").tag(nil as Value?)
            ForEach(values) { value in
                Text(value[keyPath: label]).tag(Optional(value))
            }
        }
        .labelsHidden()
        .accessibilityLabel(title)
    }

    private func recordsList(_ records: [LargeFileFacetRecord]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(records) { item in
                    CleanerLargeFileRow(
                        item: item,
                        isSelected: store.selectedIDs.contains(item.id),
                        onToggleSelection: { store.toggleSelection(for: item.id) },
                        onIgnore: { store.ignore(item.id) },
                        onReveal: {
                            store.setRevealMessage(onReveal(item.record).userDescription)
                        }
                    )
                    if item.id != records.last?.id { Divider().padding(.leading, 38) }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    @ViewBuilder
    private var reviewArea: some View {
        if !store.selectedRecords.isEmpty || !store.ignoredRecords.isEmpty {
            Divider()
            DisclosureGroup("当前结果 Review") {
                VStack(alignment: .leading, spacing: 8) {
                    if !store.selectedRecords.isEmpty {
                        Text("已选 \(store.selectedRecords.count) 项")
                            .font(.caption.bold())
                        ForEach(store.selectedRecords) { Text($0.record.name).font(.caption).lineLimit(1) }
                    }
                    if !store.ignoredRecords.isEmpty {
                        Text("已忽略 \(store.ignoredRecords.count) 项")
                            .font(.caption.bold())
                        ForEach(store.ignoredRecords) { item in
                            HStack {
                                Text(item.record.name).font(.caption).lineLimit(1)
                                Spacer()
                                Button("恢复") { store.restore(item.id) }
                                    .controlSize(.mini)
                                    .accessibilityLabel("恢复忽略项")
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func unavailableMessage(_ reason: LargeFileUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("大文件分析暂不可用", systemImage: "exclamationmark.triangle")
                .font(.callout.bold())
                .foregroundStyle(.orange)
            Text(reason.userDescription).font(.caption).foregroundStyle(.secondary)
            Text("请检查目录授权后重试；系统不会伪造文件结果。")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct CleanerLargeFileRow: View {
    let item: LargeFileFacetRecord
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onIgnore: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? OmnipoTheme.brandRed : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "取消选择" : "选择文件")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.record.name).font(.callout).lineLimit(1)
                    Text(item.kind.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(item.record.displayPath)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(modifiedText)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.record.name)，\(item.kind.displayName)，\(ByteCountFormatter.string(fromByteCount: item.record.sizeBytes, countStyle: .file))，\(modifiedText)，\(isSelected ? "已选择" : "未选择")")
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: item.record.sizeBytes, countStyle: .file))
                .font(.callout.monospacedDigit())
            Menu {
                Button("在 Finder 中显示", action: onReveal)
                Button("忽略当前候选", action: onIgnore)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("文件只读操作")
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("在 Finder 中显示", action: onReveal)
            Button("忽略当前候选", action: onIgnore)
        }
    }

    private var modifiedText: String {
        guard let date = item.record.lastModifiedAt else { return "修改时间未知" }
        return "修改于 \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

#Preview("Available") {
    CleanerLargeFileSection(
        availability: .available([
            LargeFileRecord(name: "video.mp4", displayPath: "/Demo/Movies/video.mp4", sizeBytes: 1_200_000_000, sourceVolumeIdentifier: "fs-1"),
            LargeFileRecord(name: "archive.zip", displayPath: "/Demo/Downloads/archive.zip", sizeBytes: 540_000_000, sourceVolumeIdentifier: "fs-1")
        ]),
        authorizedRootPath: "/Demo",
        onRefresh: {}
    )
    .frame(width: 700)
    .padding()
}
