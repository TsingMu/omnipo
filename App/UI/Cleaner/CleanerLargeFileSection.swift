import SwiftUI

/// 磁盘分析页的"大文件"只读区块。
///
/// 消费 `LargeFileAvailability` 的四态;不可用时不伪造文件结果,
/// 只展示原因与安全说明。所有展示的路径仅留在 UI,不进入 OSLog。
struct CleanerLargeFileSection: View {
    let availability: LargeFileAvailability
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(OmnipoTheme.brandRed)
                Text("大文件")
                    .font(.headline)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Label("刷新大文件", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("刷新大文件列表")
            }

            switch availability {
            case .idle:
                idlePlaceholder
            case .loading:
                loadingPlaceholder
            case .available(let records):
                if records.isEmpty {
                    emptyResult
                } else {
                    recordsList(records)
                }
            case .unavailable(let reason):
                unavailableMessage(reason)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Subviews

    private var idlePlaceholder: some View {
        Text("尚未开始扫描,点击右上角刷新以读取大文件列表。")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在扫描大文件…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyResult: some View {
        Text("当前范围内没有可读取的大文件。")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordsList(_ records: [LargeFileRecord]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(records) { record in
                    CleanerLargeFileRow(record: record)
                    if record.id != records.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private func unavailableMessage(_ reason: LargeFileUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("大文件列表暂不可用")
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
            }
            Text(reason.userDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("系统不会伪造文件结果;清理建议与删除动作将在后续 change 中提供。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CleanerLargeFileRow: View {
    let record: LargeFileRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(record.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(Self.format(bytes: record.sizeBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.name),\(Self.format(bytes: record.sizeBytes))")
    }

    private static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview("Available") {
    CleanerLargeFileSection(
        availability: .available([
            LargeFileRecord(
                name: "video.mp4",
                displayPath: "/Users/demo/Movies/video.mp4",
                sizeBytes: 1_200_000_000,
                sourceVolumeIdentifier: "fs-1"
            ),
            LargeFileRecord(
                name: "archive.zip",
                displayPath: "/Users/demo/Downloads/archive.zip",
                sizeBytes: 540_000_000,
                sourceVolumeIdentifier: "fs-1"
            )
        ]),
        onRefresh: {}
    )
    .frame(width: 560)
    .padding()
}

#Preview("Unavailable") {
    CleanerLargeFileSection(
        availability: .unavailable(reason: .permissionLimited),
        onRefresh: {}
    )
    .frame(width: 560)
    .padding()
}
