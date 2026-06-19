import AppKit
import Combine

/// Bundle Identifier 到应用 URL/图标的 MainActor 有界缓存。
///
/// `NSWorkspace` 与 `NSImage` 始终留在 AppKit 隔离域；搜索模型只传递稳定描述符。
@MainActor
public final class ApplicationResourceCache: NSObject, ObservableObject {
    public typealias URLResolver = @MainActor (String) -> URL?
    public typealias IconLoader = @MainActor (URL) -> NSImage
    public typealias WorkspaceChangeHandler = @MainActor () -> Void

    private final class Entry {
        var didResolveURL = false
        var url: URL?
        var didLoadIcon = false
        var icon: NSImage?
    }

    private let capacity: Int
    private let resolveURL: URLResolver
    private let loadIcon: IconLoader
    private let notificationCenter: NotificationCenter
    private let onWorkspaceChange: WorkspaceChangeHandler
    @Published public private(set) var generation: UInt64 = 0
    private var entries: [String: Entry] = [:]
    private var recency: [String] = []

    public init(
        capacity: Int = 128,
        workspace: NSWorkspace = .shared,
        onWorkspaceChange: @escaping WorkspaceChangeHandler = {}
    ) {
        self.capacity = max(1, capacity)
        self.resolveURL = { bundleIdentifier in
            workspace.urlsForApplications(withBundleIdentifier: bundleIdentifier).first
        }
        self.loadIcon = { url in
            workspace.icon(forFile: url.path)
        }
        self.notificationCenter = workspace.notificationCenter
        self.onWorkspaceChange = onWorkspaceChange
        super.init()
        observeWorkspaceChanges()
    }

    init(
        capacity: Int,
        notificationCenter: NotificationCenter,
        notificationNames: [Notification.Name],
        resolveURL: @escaping URLResolver,
        loadIcon: @escaping IconLoader,
        onWorkspaceChange: @escaping WorkspaceChangeHandler = {}
    ) {
        self.capacity = max(1, capacity)
        self.resolveURL = resolveURL
        self.loadIcon = loadIcon
        self.notificationCenter = notificationCenter
        self.onWorkspaceChange = onWorkspaceChange
        super.init()
        observeWorkspaceChanges(notificationNames)
    }

    public func applicationURL(for bundleIdentifier: String) -> URL? {
        let entry = cachedEntry(for: bundleIdentifier)
        if !entry.didResolveURL {
            entry.url = resolveURL(bundleIdentifier)
            entry.didResolveURL = true
        }
        return entry.url
    }

    public func icon(for bundleIdentifier: String) -> NSImage? {
        let entry = cachedEntry(for: bundleIdentifier)
        if !entry.didLoadIcon {
            entry.icon = applicationURL(for: bundleIdentifier).map(loadIcon)
            entry.didLoadIcon = true
        }
        return entry.icon
    }

    public func invalidateAll() {
        entries.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
        generation &+= 1
    }

    private func cachedEntry(for bundleIdentifier: String) -> Entry {
        if let entry = entries[bundleIdentifier] {
            touch(bundleIdentifier)
            return entry
        }

        let entry = Entry()
        entries[bundleIdentifier] = entry
        recency.append(bundleIdentifier)
        evictIfNeeded()
        return entry
    }

    private func touch(_ bundleIdentifier: String) {
        recency.removeAll { $0 == bundleIdentifier }
        recency.append(bundleIdentifier)
    }

    private func evictIfNeeded() {
        while entries.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    private func observeWorkspaceChanges(_ names: [Notification.Name] = [
        Notification.Name("NSWorkspaceDidPerformFileOperationNotification"),
        NSWorkspace.didMountNotification,
        NSWorkspace.didUnmountNotification
    ]) {
        for name in names {
            notificationCenter.addObserver(
                self,
                selector: #selector(workspaceDidChange(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func workspaceDidChange(_ notification: Notification) {
        invalidateAll()
        onWorkspaceChange()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
