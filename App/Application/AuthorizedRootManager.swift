import Foundation
import AppKit

public enum DirectoryAuthorizationRecoveryReason: String, Sendable, Equatable, CaseIterable {
    case bookmarkInvalid = "bookmark-invalid"
    case accessDenied = "security-scope-denied"

    public var stableCode: String {
        switch self {
        case .bookmarkInvalid: "W_AUTH_BOOKMARK_INVALID"
        case .accessDenied: "W_AUTH_SCOPE_DENIED"
        }
    }

    public var userDescription: String {
        switch self {
        case .bookmarkInvalid:
            "已保存的目录授权无法恢复,目录可能已移动或授权数据已失效。"
        case .accessDenied:
            "macOS 不再允许访问已保存的目录授权。"
        }
    }
}

public enum PersistedDirectoryAuthorizationAvailability: Sendable, Equatable {
    case notConfigured
    case available(validRootCount: Int)
    case reauthorizationRequired(
        validRootCount: Int,
        invalidRootCount: Int,
        reason: DirectoryAuthorizationRecoveryReason
    )

    public var requiresReauthorization: Bool {
        if case .reauthorizationRequired = self { return true }
        return false
    }
}

struct ResolvedDirectoryBookmark {
    let url: URL
    let isStale: Bool
}

/// 用户通过 NSOpenPanel 授权的"大文件扫描根"管理器。
///
/// - 通过 security-scoped bookmark 持久化授权,重启后仍可访问同一目录。
/// - 调用方拿到 URL 后,在扫描期间必须保持 security scope 激活;
///   `releaseRoot()` 释放 scope。
/// - 不读文件内容,只读元数据;UI 文案已说明。
@MainActor
public final class AuthorizedRootManager {
    private let settings: any SettingsService
    private let logger: (any LoggingService)?
    private let bookmarkResolver: (Data) throws -> ResolvedDirectoryBookmark
    private let scopeStarter: (URL) -> Bool
    private let scopeStopper: (URL) -> Void
    private let bookmarkCreator: (URL) throws -> Data
    private var bookmarkData: Data?
    private var resolvedURL: URL?
    private var resolvedDisplayName: String?
    private var hasValidatedAuthorization: Bool
    private var authorizationState: PersistedDirectoryAuthorizationAvailability
    private var lastLoggedRecoveryState: PersistedDirectoryAuthorizationAvailability?

    public convenience init(
        settings: any SettingsService,
        logger: (any LoggingService)? = nil
    ) {
        self.init(
            settings: settings,
            bookmarkResolver: Self.resolveBookmark,
            scopeStarter: { $0.startAccessingSecurityScopedResource() },
            scopeStopper: { $0.stopAccessingSecurityScopedResource() },
            bookmarkCreator: Self.createBookmark,
            logger: logger
        )
    }

    init(
        settings: any SettingsService,
        bookmarkResolver: @escaping (Data) throws -> ResolvedDirectoryBookmark,
        scopeStarter: @escaping (URL) -> Bool,
        scopeStopper: @escaping (URL) -> Void,
        bookmarkCreator: @escaping (URL) throws -> Data,
        logger: (any LoggingService)? = nil
    ) {
        self.settings = settings
        self.logger = logger
        self.bookmarkResolver = bookmarkResolver
        self.scopeStarter = scopeStarter
        self.scopeStopper = scopeStopper
        self.bookmarkCreator = bookmarkCreator
        self.bookmarkData = settings.readLargeFileRootBookmark()
        self.resolvedDisplayName = nil
        self.hasValidatedAuthorization = self.bookmarkData == nil
        self.authorizationState = self.bookmarkData == nil
            ? .notConfigured
            : .reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 1,
                reason: .bookmarkInvalid
            )
    }

    public var authorizationAvailability: PersistedDirectoryAuthorizationAvailability {
        if !hasValidatedAuthorization {
            _ = currentRoot()
            releaseScope()
        }
        return authorizationState
    }

    /// 当前授权根;首次访问时解析 bookmark 并 `startAccessingSecurityScopedResource`。
    /// 未授权、bookmark 损坏或权限失效时返回 nil。
    public func currentRoot() -> URL? {
        if let resolvedURL {
            return resolvedURL
        }
        guard let data = bookmarkData else {
            hasValidatedAuthorization = true
            resolvedDisplayName = nil
            authorizationState = .notConfigured
            return nil
        }
        let resolved: ResolvedDirectoryBookmark
        do {
            resolved = try bookmarkResolver(data)
        } catch {
            hasValidatedAuthorization = true
            resolvedDisplayName = nil
            updateAuthorizationState(.reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 1,
                reason: .bookmarkInvalid
            ))
            return nil
        }
        guard scopeStarter(resolved.url) else {
            hasValidatedAuthorization = true
            resolvedDisplayName = nil
            updateAuthorizationState(.reauthorizationRequired(
                validRootCount: 0,
                invalidRootCount: 1,
                reason: .accessDenied
            ))
            return nil
        }
        resolvedURL = resolved.url
        resolvedDisplayName = resolved.url.lastPathComponent
        hasValidatedAuthorization = true
        updateAuthorizationState(.available(validRootCount: 1))
        if resolved.isStale {
            refreshBookmark(for: resolved.url)
        }
        return resolved.url
    }

    /// 当前授权根的显示名;未授权时返回 nil。
    public func currentRootDisplayName() -> String? {
        _ = authorizationAvailability
        return resolvedDisplayName
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
        resolvedDisplayName = nil
        hasValidatedAuthorization = true
        authorizationState = .notConfigured
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
            scopeStopper(resolvedURL)
            self.resolvedURL = nil
        }
    }

    @discardableResult
    private func persist(url: URL) -> URL? {
        guard let data = try? bookmarkCreator(url) else {
            return nil
        }
        releaseScope()
        bookmarkData = data
        hasValidatedAuthorization = false
        settings.writeLargeFileRootBookmark(data)
        return currentRoot()
    }

    private func refreshBookmark(for url: URL) {
        if let data = try? bookmarkCreator(url) {
            bookmarkData = data
            settings.writeLargeFileRootBookmark(data)
        }
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
            message: "disk.authorization.reauthorizationRequired",
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
}
