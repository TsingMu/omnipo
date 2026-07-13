import AppKit
import Foundation

/// 管理用户明确选择的微信存储目录，并持有对应 security scope。
@MainActor
public final class WeChatStorageAuthorizationManager {
    private let settings: any SettingsService
    private let logger: (any LoggingService)?
    private let maximumRootCount: Int
    private let sensitiveNamesConsentPrompt: @MainActor () -> Bool
    private let bookmarkResolver: (Data) throws -> ResolvedDirectoryBookmark
    private let scopeStarter: (URL) -> Bool
    private let scopeStopper: (URL) -> Void
    private let bookmarkCreator: (URL) throws -> Data
    private var bookmarkData: [Data]
    private var activeRoots: [URL] = []
    private var hasValidatedAuthorization: Bool
    private var failedBookmarks = Set<Data>()
    private var authorizationState: PersistedDirectoryAuthorizationAvailability
    private var lastLoggedRecoveryState: PersistedDirectoryAuthorizationAvailability?

    public convenience init(
        settings: any SettingsService,
        maximumRootCount: Int = 8,
        logger: (any LoggingService)? = nil
    ) {
        self.init(
            settings: settings,
            maximumRootCount: maximumRootCount,
            sensitiveNamesConsentPrompt: Self.defaultSensitiveNamesConsentPrompt,
            bookmarkResolver: Self.resolveBookmark,
            scopeStarter: { $0.startAccessingSecurityScopedResource() },
            scopeStopper: { $0.stopAccessingSecurityScopedResource() },
            bookmarkCreator: Self.createBookmark,
            logger: logger
        )
    }

    convenience init(
        settings: any SettingsService,
        maximumRootCount: Int = 8,
        sensitiveNamesConsentPrompt: @escaping @MainActor () -> Bool
    ) {
        self.init(
            settings: settings,
            maximumRootCount: maximumRootCount,
            sensitiveNamesConsentPrompt: sensitiveNamesConsentPrompt,
            bookmarkResolver: Self.resolveBookmark,
            scopeStarter: { $0.startAccessingSecurityScopedResource() },
            scopeStopper: { $0.stopAccessingSecurityScopedResource() },
            bookmarkCreator: Self.createBookmark,
            logger: nil
        )
    }

    init(
        settings: any SettingsService,
        maximumRootCount: Int,
        sensitiveNamesConsentPrompt: @escaping @MainActor () -> Bool,
        bookmarkResolver: @escaping (Data) throws -> ResolvedDirectoryBookmark,
        scopeStarter: @escaping (URL) -> Bool,
        scopeStopper: @escaping (URL) -> Void,
        bookmarkCreator: @escaping (URL) throws -> Data,
        logger: (any LoggingService)? = nil
    ) {
        self.settings = settings
        self.logger = logger
        self.maximumRootCount = max(1, maximumRootCount)
        self.sensitiveNamesConsentPrompt = sensitiveNamesConsentPrompt
        self.bookmarkResolver = bookmarkResolver
        self.scopeStarter = scopeStarter
        self.scopeStopper = scopeStopper
        self.bookmarkCreator = bookmarkCreator
        self.bookmarkData = settings.readWeChatStorageRootBookmarks()
        self.hasValidatedAuthorization = self.bookmarkData.isEmpty
        self.authorizationState = self.bookmarkData.isEmpty
            ? .notConfigured
            : .reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: self.bookmarkData.count,
                reason: .bookmarkInvalid
            )
    }

    public var authorizationAvailability: PersistedDirectoryAuthorizationAvailability {
        if !hasValidatedAuthorization {
            _ = currentRoots()
            releaseActiveRoots()
        }
        return authorizationState
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

        guard !bookmarkData.isEmpty else {
            hasValidatedAuthorization = true
            authorizationState = .notConfigured
            failedBookmarks = []
            return []
        }

        var retainedBookmarks: [Data] = []
        var roots: [URL] = []
        var seen = Set<String>()
        var failures = Set<Data>()
        var recoveryReason: DirectoryAuthorizationRecoveryReason?

        for bookmark in bookmarkData {
            let resolved: ResolvedDirectoryBookmark
            do {
                resolved = try bookmarkResolver(bookmark)
            } catch {
                retainedBookmarks.append(bookmark)
                failures.insert(bookmark)
                recoveryReason = recoveryReason ?? .bookmarkInvalid
                continue
            }
            guard scopeStarter(resolved.url) else {
                retainedBookmarks.append(bookmark)
                failures.insert(bookmark)
                recoveryReason = recoveryReason ?? .accessDenied
                continue
            }

            let normalizedPath = resolved.url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seen.insert(normalizedPath).inserted else {
                scopeStopper(resolved.url)
                continue
            }

            roots.append(resolved.url)
            if resolved.isStale, let refreshed = makeBookmark(for: resolved.url) {
                retainedBookmarks.append(refreshed)
            } else {
                retainedBookmarks.append(bookmark)
            }
        }

        activeRoots = roots
        hasValidatedAuthorization = true
        failedBookmarks = failures
        if let recoveryReason, !failures.isEmpty {
            updateAuthorizationState(.reauthorizationRequired(
                validRootCount: roots.count,
                invalidRootCount: failures.count,
                reason: recoveryReason
            ))
        } else {
            updateAuthorizationState(.available(validRootCount: roots.count))
        }
        if retainedBookmarks != bookmarkData {
            bookmarkData = retainedBookmarks
            settings.writeWeChatStorageRootBookmarks(retainedBookmarks)
        }
        return roots
    }

    /// 让用户选择一个或多个目录；成功后持久化授权并供后续刷新使用。
    @discardableResult
    public func selectNewRoots() async -> Bool {
        _ = currentRoots()
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
        let retainedValidBookmarks = bookmarkData.filter { !failedBookmarks.contains($0) }
        bookmarkData = deduplicatedBookmarks(newBookmarks + retainedValidBookmarks)
        hasValidatedAuthorization = false
        failedBookmarks = []
        settings.writeWeChatStorageRootBookmarks(bookmarkData)
        return !currentRoots().isEmpty
    }

    public func clearRoots() {
        releaseActiveRoots()
        bookmarkData = []
        hasValidatedAuthorization = true
        failedBookmarks = []
        authorizationState = .notConfigured
        settings.writeWeChatStorageRootBookmarks([])
    }

    /// 一轮扫描结束后释放所有由 `currentRoots()` 激活的 security scope。
    public func releaseRoots() {
        releaseActiveRoots()
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? bookmarkCreator(url)
    }

    private func deduplicatedBookmarks(_ bookmarks: [Data]) -> [Data] {
        var seen = Set<String>()
        var result: [Data] = []

        for bookmark in bookmarks {
            guard let resolved = try? bookmarkResolver(bookmark) else { continue }
            let path = resolved.url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(bookmark)
            if result.count == maximumRootCount { break }
        }
        return result
    }

    private func releaseActiveRoots() {
        for root in activeRoots {
            scopeStopper(root)
        }
        activeRoots = []
    }

    private func updateAuthorizationState(
        _ state: PersistedDirectoryAuthorizationAvailability
    ) {
        authorizationState = state
        guard case .reauthorizationRequired(let validCount, let invalidCount, let reason) = state else {
            lastLoggedRecoveryState = nil
            return
        }
        guard lastLoggedRecoveryState != state else { return }
        lastLoggedRecoveryState = state
        logger?.log(LogEvent(
            level: .warning,
            category: .application,
            message: "wechat.authorization.reauthorizationRequired",
            stableCode: reason.stableCode,
            sanitizedContext: [
                "reason": reason.rawValue,
                "validCount": "\(validCount)",
                "invalidCount": "\(invalidCount)"
            ]
        ))
    }

    private static func resolveBookmark(_ data: Data) throws -> ResolvedDirectoryBookmark {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return ResolvedDirectoryBookmark(url: url, isStale: stale)
    }

    private static func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
