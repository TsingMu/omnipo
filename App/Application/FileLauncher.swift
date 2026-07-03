import Foundation
import AppKit
import Quartz

/// 文件打开执行器。
///
/// 文件结果来自 Spotlight,初始 bookmark 可能不是 security-scoped bookmark。
/// 执行动作时先尝试已授权目录或现有 bookmark;若沙盒权限不足,通过 NSOpenPanel
/// 让用户授权包含目标文件的目录,再使用目录 security scope 继续原动作。
/// 日志只记录稳定代码,不含文件路径。
@MainActor
public final class FileLauncher {
    public enum Action: Sendable, Hashable {
        case open
        case preview
        case revealInFinder
        case copy
    }

    private let logger: any LoggingService
    private let workspace: NSWorkspace
    private let settings: (any SettingsService)?
    private let authorizedRootManager: AuthorizedRootManager?
    private let maxAuthorizedDirectories = 12

    public init(
        logger: any LoggingService,
        workspace: NSWorkspace = .shared,
        settings: (any SettingsService)? = nil,
        authorizedRootManager: AuthorizedRootManager? = nil
    ) {
        self.logger = logger
        self.workspace = workspace
        self.settings = settings
        self.authorizedRootManager = authorizedRootManager
    }

    public func open(bookmark: Data) async -> Result<Void, AppError> {
        await perform(.open, bookmark: bookmark)
    }

    public func perform(_ action: Action, bookmark: Data) async -> Result<Void, AppError> {
        do {
            let (url, stale) = try resolve(bookmark: bookmark)
            if stale {
                logger.log(Self.logStale())
                return .failure(.resourceUnavailable(reason: "stale-bookmark"))
            }

            if let directoryAccess = startAuthorizedDirectoryAccess(containing: url) {
                defer { directoryAccess.stop() }
                if run(action, url: url) {
                    return .success(())
                }
                logger.log(Self.logActionFailed(action: action))
            }

            if shouldRequestAccessBeforeAction(action, url: url) {
                guard let directoryAccess = requestDirectoryAccess(containing: url, action: action) else {
                    return .failure(.insufficientPermission(resource: "文件访问"))
                }
                defer { directoryAccess.stop() }
                guard run(action, url: url) else {
                    logger.log(Self.logActionFailed(action: action))
                    return .failure(.resourceUnavailable(reason: "system-refused"))
                }
                return .success(())
            }

            if runWithSecurityScope(url, action: action) {
                return .success(())
            }

            logger.log(Self.logAccessRequired(action: action))
            guard let directoryAccess = requestDirectoryAccess(containing: url, action: action) else {
                return .failure(.insufficientPermission(resource: "文件访问"))
            }
            defer { directoryAccess.stop() }
            guard run(action, url: url) else {
                logger.log(Self.logActionFailed(action: action))
                return .failure(.resourceUnavailable(reason: "system-refused"))
            }
            return .success(())
        } catch {
            logger.log(Self.logResolveFailed())
            return .failure(.resourceUnavailable(reason: "bookmark-unresolvable"))
        }
    }

    private func resolve(bookmark: Data) throws -> (url: URL, stale: Bool) {
        var scopedStale = false
        if let scopedURL = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &scopedStale
        ) {
            return (scopedURL, scopedStale)
        }

        var plainStale = false
        let plainURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &plainStale
        )
        return (plainURL, plainStale)
    }

    private func shouldRequestAccessBeforeAction(_ action: Action, url: URL) -> Bool {
        switch action {
        case .open, .preview:
            return !FileManager.default.isReadableFile(atPath: url.path)
        case .revealInFinder:
            return !FileManager.default.isReadableFile(atPath: url.deletingLastPathComponent().path)
        case .copy:
            return false
        }
    }

    private func runWithSecurityScope(_ scopeURL: URL, action: Action) -> Bool {
        let didAccess = scopeURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                scopeURL.stopAccessingSecurityScopedResource()
            }
        }
        return run(action, url: scopeURL)
    }

    private func run(_ action: Action, url: URL) -> Bool {
        switch action {
        case .open:
            return workspace.open(url)
        case .preview:
            return FilePreviewController.shared.preview(url: url)
        case .revealInFinder:
            workspace.activateFileViewerSelecting([url])
            return true
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.writeObjects([url as NSURL])
        }
    }

    private func startAuthorizedDirectoryAccess(containing url: URL) -> DirectoryAccess? {
        if let rootURL = authorizedRootManager?.currentRoot(), rootURL.contains(url) {
            return DirectoryAccess(url: rootURL, didAccess: false)
        }

        guard let settings else { return nil }
        let bookmarks = storedDirectoryBookmarks()
        var retained: [Data] = []
        var selectedAccess: DirectoryAccess?

        for bookmark in bookmarks {
            var stale = false
            guard let directoryURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale else {
                continue
            }

            retained.append(bookmark)
            guard selectedAccess == nil, directoryURL.contains(url) else { continue }
            let didAccess = directoryURL.startAccessingSecurityScopedResource()
            guard didAccess else { continue }
            selectedAccess = DirectoryAccess(url: directoryURL, didAccess: didAccess)
        }

        if retained.count != bookmarks.count {
            settings.writeLauncherFileDirectoryBookmarks(retained)
        }
        return selectedAccess
    }

    private func requestDirectoryAccess(containing url: URL, action: Action) -> DirectoryAccess? {
        let suggestedDirectory = suggestedAuthorizationDirectory(containing: url)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggestedDirectory.deletingLastPathComponent()
        panel.prompt = "授权"
        panel.message = message(
            for: action,
            suggestedName: url.lastPathComponent,
            directoryName: suggestedDirectory.lastPathComponent
        )

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            logger.log(Self.logAccessCancelled(action: action))
            return nil
        }
        guard directoryURL.contains(url) else {
            logger.log(Self.logAccessDirectoryMismatch(action: action))
            return nil
        }
        return persistDirectorySecurityScope(for: directoryURL)
    }

    private func persistDirectorySecurityScope(for directoryURL: URL) -> DirectoryAccess? {
        guard let data = try? directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }

        if let settings {
            settings.writeLargeFileRootBookmark(data)
            var bookmarks = settings.readLauncherFileDirectoryBookmarks()
            bookmarks = bookmarks.filter { existing in
                !resolves(existing, toSameDirectoryAs: directoryURL)
            }
            bookmarks.insert(data, at: 0)
            settings.writeLauncherFileDirectoryBookmarks(Array(bookmarks.prefix(maxAuthorizedDirectories)))
        }
        authorizedRootManager?.adoptRoot(url: directoryURL)

        var stale = false
        guard let scopedURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else {
            return nil
        }
        let didAccess = scopedURL.startAccessingSecurityScopedResource()
        guard didAccess else { return nil }
        return DirectoryAccess(url: scopedURL, didAccess: didAccess)
    }

    private func storedDirectoryBookmarks() -> [Data] {
        guard let settings else { return [] }
        var bookmarks: [Data] = []
        if let largeFileBookmark = settings.readLargeFileRootBookmark() {
            bookmarks.append(largeFileBookmark)
        }
        bookmarks.append(contentsOf: settings.readLauncherFileDirectoryBookmarks())
        return bookmarks
    }

    private func resolves(_ bookmark: Data, toSameDirectoryAs directoryURL: URL) -> Bool {
        var stale = false
        guard let existingURL = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else {
            return false
        }
        return existingURL.normalizedFilePath == directoryURL.normalizedFilePath
    }

    private func suggestedAuthorizationDirectory(containing url: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let commonDirectories = [
            "Documents",
            "Downloads",
            "Desktop",
            "Pictures",
            "Movies",
            "Music"
        ].map { home.appendingPathComponent($0, isDirectory: true) }

        if let directory = commonDirectories.first(where: { $0.contains(url) }) {
            return directory
        }
        return url.deletingLastPathComponent()
    }

    private struct DirectoryAccess {
        let url: URL
        let didAccess: Bool

        func stop() {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func message(for action: Action, suggestedName: String, directoryName: String) -> String {
        switch action {
        case .open:
            return "Omnipo 需要你授权包含「\(suggestedName)」的文件夹后才能打开。请选择「\(directoryName)」等上级目录。"
        case .preview:
            return "Omnipo 需要你授权包含「\(suggestedName)」的文件夹后才能预览。请选择「\(directoryName)」等上级目录。"
        case .revealInFinder:
            return "Omnipo 需要你授权包含「\(suggestedName)」的文件夹后才能在 Finder 中显示。请选择「\(directoryName)」等上级目录。"
        case .copy:
            return "Omnipo 需要你授权包含「\(suggestedName)」的文件夹后才能复制。请选择「\(directoryName)」等上级目录。"
        }
    }

    private static func logStale() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.file.stale",
            stableCode: "W_FILE_STALE",
            sanitizedContext: ["code": "W_FILE_STALE", "reason": "stale-bookmark"]
        )
    }

    private static func logActionFailed(action: Action) -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.file.actionFailed",
            stableCode: "W_FILE_OPEN",
            sanitizedContext: [
                "code": "W_FILE_OPEN",
                "reason": "system-refused",
                "action": action.logValue
            ]
        )
    }

    private static func logAccessRequired(action: Action) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "launcher.file.accessRequired",
            stableCode: "I_FILE_ACCESS_REQUIRED",
            sanitizedContext: [
                "code": "I_FILE_ACCESS_REQUIRED",
                "reason": "sandbox-access-required",
                "action": action.logValue
            ]
        )
    }

    private static func logAccessCancelled(action: Action) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "launcher.file.accessCancelled",
            stableCode: "I_FILE_ACCESS_CANCELLED",
            sanitizedContext: [
                "code": "I_FILE_ACCESS_CANCELLED",
                "reason": "user-cancelled",
                "action": action.logValue
            ]
        )
    }

    private static func logAccessDirectoryMismatch(action: Action) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "launcher.file.accessDirectoryMismatch",
            stableCode: "I_FILE_ACCESS_DIRECTORY_MISMATCH",
            sanitizedContext: [
                "code": "I_FILE_ACCESS_DIRECTORY_MISMATCH",
                "reason": "directory-does-not-contain-file",
                "action": action.logValue
            ]
        )
    }

    private static func logResolveFailed() -> LogEvent {
        LogEvent(
            level: .error,
            category: .application,
            message: "launcher.file.resolveFailed",
            stableCode: "E_FILE_RESOLVE",
            sanitizedContext: ["code": "E_FILE_RESOLVE", "reason": "bookmark-unresolvable"]
        )
    }
}

private extension URL {
    var normalizedFilePath: String {
        standardizedFileURL.path
    }

    func contains(_ child: URL) -> Bool {
        let rootPath = normalizedFilePath
        let childPath = child.normalizedFilePath
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }
}

private extension FileLauncher.Action {
    var logValue: String {
        switch self {
        case .open: return "open"
        case .preview: return "preview"
        case .revealInFinder: return "reveal"
        case .copy: return "copy"
        }
    }
}

@MainActor
private final class FilePreviewController: NSObject,
    @preconcurrency QLPreviewPanelDataSource {
    static let shared = FilePreviewController()

    private var previewURL: NSURL?

    func preview(url: URL) -> Bool {
        guard let panel = QLPreviewPanel.shared() else { return false }
        previewURL = url as NSURL
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL
    }
}
