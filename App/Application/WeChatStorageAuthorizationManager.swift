import AppKit
import Foundation

/// 管理用户明确选择的微信存储目录，并持有对应 security scope。
@MainActor
public final class WeChatStorageAuthorizationManager {
    private let settings: any SettingsService
    private let maximumRootCount: Int
    private let sensitiveNamesConsentPrompt: @MainActor () -> Bool
    private var bookmarkData: [Data]
    private var activeRoots: [URL] = []

    public convenience init(
        settings: any SettingsService,
        maximumRootCount: Int = 8
    ) {
        self.init(
            settings: settings,
            maximumRootCount: maximumRootCount,
            sensitiveNamesConsentPrompt: Self.defaultSensitiveNamesConsentPrompt
        )
    }

    init(
        settings: any SettingsService,
        maximumRootCount: Int = 8,
        sensitiveNamesConsentPrompt: @escaping @MainActor () -> Bool
    ) {
        self.settings = settings
        self.maximumRootCount = max(1, maximumRootCount)
        self.sensitiveNamesConsentPrompt = sensitiveNamesConsentPrompt
        self.bookmarkData = settings.readWeChatStorageRootBookmarks()
    }

    public var sensitiveNamesEnabled: Bool {
        settings.readBool(forKey: .weChatSensitiveNamesEnabled)
    }

    @discardableResult
    public func requestSensitiveNamesAccess() -> Bool {
        if sensitiveNamesEnabled { return true }
        guard sensitiveNamesConsentPrompt() else { return false }
        settings.write(true, forKey: .weChatSensitiveNamesEnabled)
        return true
    }

    public func revokeSensitiveNamesAccess() {
        settings.write(false, forKey: .weChatSensitiveNamesEnabled)
    }

    /// 解析并激活所有仍有效的授权目录。返回值只供扫描使用，不用于 UI 展示原始路径。
    public func currentRoots() -> [URL] {
        if !activeRoots.isEmpty { return activeRoots }

        var validBookmarks: [Data] = []
        var roots: [URL] = []
        var seen = Set<String>()

        for bookmark in bookmarkData {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), url.startAccessingSecurityScopedResource() else {
                continue
            }

            let normalizedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seen.insert(normalizedPath).inserted else {
                url.stopAccessingSecurityScopedResource()
                continue
            }

            roots.append(url)
            if stale, let refreshed = makeBookmark(for: url) {
                validBookmarks.append(refreshed)
            } else {
                validBookmarks.append(bookmark)
            }
        }

        activeRoots = roots
        if validBookmarks != bookmarkData {
            bookmarkData = validBookmarks
            settings.writeWeChatStorageRootBookmarks(validBookmarks)
        }
        return roots
    }

    /// 让用户选择一个或多个目录；成功后持久化授权并供后续刷新使用。
    @discardableResult
    public func selectNewRoots() async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
        panel.prompt = "授权并扫描"
        panel.message = "请选择微信数据目录。Omnipo 只读取文件大小、类型和修改时间。"

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return false }
        let newBookmarks = panel.urls.compactMap { makeBookmark(for: $0) }
        guard !newBookmarks.isEmpty else { return false }

        releaseActiveRoots()
        bookmarkData = deduplicatedBookmarks(newBookmarks + bookmarkData)
        settings.writeWeChatStorageRootBookmarks(bookmarkData)
        return !currentRoots().isEmpty
    }

    public func clearRoots() {
        releaseActiveRoots()
        bookmarkData = []
        settings.writeWeChatStorageRootBookmarks([])
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func deduplicatedBookmarks(_ bookmarks: [Data]) -> [Data] {
        var seen = Set<String>()
        var result: [Data] = []

        for bookmark in bookmarks {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(bookmark)
            if result.count == maximumRootCount { break }
        }
        return result
    }

    private func releaseActiveRoots() {
        for root in activeRoots {
            root.stopAccessingSecurityScopedResource()
        }
        activeRoots = []
    }

    private static func defaultSensitiveNamesConsentPrompt() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "显示微信敏感名称"
        alert.informativeText = "Omnipo 将在当前设备上显示真实文件名，并允许你为匿名会话设置本地名称。不会读取消息正文；微信 4.x 的加密会话数据库不会被解密。文件名仅保留在本次扫描结果中，聊天名称仅保留到退出应用。"
        alert.addButton(withTitle: "允许显示")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
