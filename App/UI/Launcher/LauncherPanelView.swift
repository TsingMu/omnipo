import SwiftUI
import AppKit

/// Launcher 搜索面板的 SwiftUI 内容。
///
/// 不直接持有 NSPanel;由 `LauncherPanelController` 用 `NSHostingView` 加载。
/// 唯一事实来源是 `LauncherStore`,执行通过 closure 委托给协调层。
struct LauncherPanelView: View {
    @Bindable var store: LauncherStore
    let onExecute: (SearchResult) -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                LauncherSearchField(
                    inputState: store.inputState,
                    onInputStateChange: store.updateInput,
                    onMoveSelection: store.moveSelection,
                    onSubmit: executeSelection,
                    onCancel: onHide
                )
                .frame(height: 24)
                if !store.query.isEmpty {
                    Button {
                        store.updateQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.thinMaterial)

            Divider()

            if store.results.isEmpty {
                emptyState
            } else {
                resultList
            }

            if case .partialFailure(let msg) = store.state {
                Text("部分结果不可用:\(msg)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4))
            }

            if let error = store.transientError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error.userDescription)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("重试") {
                        store.clearTransientError()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12))
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.tertiary.opacity(0.3), lineWidth: 1)
        )
        .frame(width: 560, height: 420)
    }

    private func executeSelection() {
        if let result = store.currentResult() {
            onExecute(result)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            if store.state == .empty && !store.query.isEmpty {
                Text("未找到匹配结果")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("输入以开始搜索")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.results) { result in
                    LauncherResultRow(
                        result: result,
                        isSelected: result.id == store.selection
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onExecute(result)
                    }
                    .accessibilityAddTraits(result.id == store.selection ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct LauncherResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            kindBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var iconView: some View {
        switch result.iconDescriptor {
        case .systemSymbol(let name):
            Image(systemName: name)
                .foregroundStyle(.tint)
        case .appBundleIdentifier(let id):
            AppIconView(bundleIdentifier: id)
        case .fileType(let ext):
            Image(systemName: fileTypeSymbol(for: ext))
                .foregroundStyle(.secondary)
        case .genericFile:
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
        case .none:
            Color.clear
        }
    }

    private var kindBadge: some View {
        Text(label(for: result.kind))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func label(for kind: SearchResult.Kind) -> String {
        switch kind {
        case .command: return "功能"
        case .application: return "应用"
        case .file: return "文件"
        }
    }

    private func fileTypeSymbol(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "heic", "tiff", "gif": return "photo"
        case "mp4", "mov", "m4v": return "film"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "txt": return "doc.plaintext"
        default: return "doc"
        }
    }

    private var accessibilityLabel: String {
        var parts = [result.title, label(for: result.kind)]
        if let subtitle = result.subtitle {
            parts.append(subtitle)
        }
        return parts.joined(separator: ", ")
    }
}

/// 根据 Bundle ID 现取应用图标的轻量包装。
struct AppIconView: View {
    let bundleIdentifier: String

    var body: some View {
        let path = pathForApp
        let image: NSImage? = path.isEmpty ? nil : NSWorkspace.shared.icon(forFile: path)
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }

    private var pathForApp: String {
        let urls = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier)
        return urls.first?.path ?? ""
    }
}
