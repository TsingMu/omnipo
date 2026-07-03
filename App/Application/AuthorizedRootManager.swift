import Foundation
import AppKit

/// 用户通过 NSOpenPanel 授权的"大文件扫描根"管理器。
///
/// - 通过 security-scoped bookmark 持久化授权,重启后仍可访问同一目录。
/// - 调用方拿到 URL 后,在扫描期间必须保持 security scope 激活;
///   `releaseRoot()` 释放 scope。
/// - 不读文件内容,只读元数据;UI 文案已说明。
@MainActor
public final class AuthorizedRootManager {
    private let settings: any SettingsService
    private var bookmarkData: Data?
    private var resolvedURL: URL?

    public init(settings: any SettingsService) {
        self.settings = settings
        self.bookmarkData = settings.readLargeFileRootBookmark()
    }

    /// 当前授权根;首次访问时解析 bookmark 并 `startAccessingSecurityScopedResource`。
    /// 未授权、bookmark 损坏或权限失效时返回 nil。
    public func currentRoot() -> URL? {
        if let resolvedURL {
            return resolvedURL
        }
        guard let data = bookmarkData else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        resolvedURL = url
        if stale {
            refreshBookmark(for: url)
        }
        return url
    }

    /// 当前授权根的显示名;未授权时返回 nil。
    public func currentRootDisplayName() -> String? {
        currentRoot()?.lastPathComponent
    }

    /// 弹出 NSOpenPanel 让用户选择新目录,持久化 bookmark,激活 security scope。
    /// 用户取消返回 nil。
    @discardableResult
    public func selectNewRoot() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择扫描目录"
        panel.message = "Omnipo 将只读取该目录内的文件大小元数据,不读取文件内容。"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        return persist(url: url)
    }

    /// 清除已授权的根,释放 security scope 与持久化 bookmark。
    public func clearRoot() {
        releaseScope()
        bookmarkData = nil
        settings.writeLargeFileRootBookmark(nil)
    }

    /// 扫描完成后调用,释放 security scope。
    public func releaseRoot() {
        releaseScope()
    }

    /// 复用其他功能通过 NSOpenPanel 获得的目录授权,保持磁盘扫描与文件操作授权一致。
    @discardableResult
    public func adoptRoot(url: URL) -> URL? {
        persist(url: url)
    }

    private func releaseScope() {
        if let resolvedURL {
            resolvedURL.stopAccessingSecurityScopedResource()
            self.resolvedURL = nil
        }
    }

    @discardableResult
    private func persist(url: URL) -> URL? {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }
        releaseScope()
        bookmarkData = data
        settings.writeLargeFileRootBookmark(data)
        return currentRoot()
    }

    private func refreshBookmark(for url: URL) {
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarkData = data
            settings.writeLargeFileRootBookmark(data)
        }
    }
}
