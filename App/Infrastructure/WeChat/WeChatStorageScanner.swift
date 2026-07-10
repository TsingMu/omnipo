import Foundation

/// 遍历可读 root 的元数据,聚合并分类;处理 symlink 去重与越界;支持取消。
///
/// 只读取资源元数据(大小/修改时间/类型),不打开或解析文件内容。
public final class WeChatStorageScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let topGroupCap: Int

    public init(fileManager: FileManager = .default, topGroupCap: Int = 20) {
        self.fileManager = fileManager
        self.topGroupCap = max(1, topGroupCap)
    }

    public func scan(
        roots: [WeChatStorageRoot],
        isCancelled: () -> Bool = { false }
    ) -> WeChatStorageScanResult {
        var categoryBytes: [WeChatStorageCategory: Int] = [:]
        var categoryFiles: [WeChatStorageCategory: Int] = [:]
        var groups: [WeChatStorageGroup] = []
        var issues: [WeChatStorageIssue] = []
        var visited = Set<String>()
        var groupSerial = 0

        let readableRoots = roots.filter {
            if case .readable = $0.availability { return true }
            return false
        }
        let rootPaths = readableRoots.map { $0.url.path }

        // 跨 root 去重(第一道):去掉被其他 root 路径包含的 root —— 祖先扫描会聚合其整棵子树,
        // 后代 root 再单独扫一次会重复计入 totalVisibleBytes。
        let independentRoots = readableRoots.filter { root in
            !readableRoots.contains { other in
                other.id != root.id && root.url.path.hasPrefix(other.url.path + "/")
            }
        }

        for root in independentRoots {
            if isCancelled() {
                issues.append(.init(rootID: root.id, rootKind: root.kind, reason: .scanCancelled, sanitizedDisplayName: root.displayName))
                break
            }
            // 跨 root 去重(第二道):相同真实路径或 symlink 指向已扫 root 时跳过。
            if !visited.insert(root.url.path).inserted { continue }

            guard let children = try? fileManager.contentsOfDirectory(
                at: root.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ) else {
                issues.append(.init(rootID: root.id, rootKind: root.kind, reason: .resourceUnavailable, sanitizedDisplayName: root.displayName))
                continue
            }

            for child in children {
                if isCancelled() { break }
                let realChild = child.resolvingSymlinksInPath()
                let realPath = realChild.path

                // 第一层 child 越界:symlink 真实路径不在任何可读 root 之下,拒绝跟随。
                if !isWithinRoots(realPath, rootPaths: rootPaths) {
                    issues.append(.init(rootID: root.id, rootKind: root.kind, reason: .permissionLimited, sanitizedDisplayName: root.displayName))
                    continue
                }
                // 同一真实路径只计一次。
                if !visited.insert(realPath).inserted {
                    continue
                }

                let aggregate = self.aggregate(url: realChild, root: root, rootPaths: rootPaths, isCancelled: isCancelled)
                let category = Self.inferCategory(path: realChild.path)
                categoryBytes[category, default: 0] += aggregate.size
                categoryFiles[category, default: 0] += aggregate.fileCount
                issues.append(contentsOf: aggregate.issues)

                groupSerial += 1
                groups.append(WeChatStorageGroup(
                    category: category,
                    displayName: "\(category.displayName)组 \(groupSerial)",
                    sizeBytes: aggregate.size,
                    fileCount: aggregate.fileCount,
                    lastModified: aggregate.lastModified,
                    riskNote: nil
                ))
            }
        }

        // 不可读 root 产生 issue(含其原因)。
        for root in roots {
            if case .unavailable(let reason) = root.availability {
                issues.append(.init(rootID: root.id, rootKind: root.kind, reason: reason, sanitizedDisplayName: root.displayName))
            }
        }

        // 取消兜底:取消若发生在 child 循环或 aggregate 枚举内部(只 break,不在 root 入口记录),
        // 返回前确保有 scanCancelled issue,让 UI 能区分"部分完成"与"被用户取消"。
        if isCancelled() && !issues.contains(where: { $0.reason == .scanCancelled }) {
            issues.append(.init(rootID: nil, rootKind: nil, reason: .scanCancelled, sanitizedDisplayName: nil))
        }

        let categories: [WeChatStorageCategorySummary] = WeChatStorageCategory.allCases.compactMap { category in
            let bytes = categoryBytes[category] ?? 0
            let files = categoryFiles[category] ?? 0
            guard bytes > 0 || files > 0 else { return nil }
            return WeChatStorageCategorySummary(category: category, sizeBytes: bytes, fileCount: files)
        }

        let topGroups = groups
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(topGroupCap)
            .map { $0 }

        return WeChatStorageScanResult(
            totalVisibleBytes: categories.reduce(0) { $0 + $1.sizeBytes },
            categories: categories,
            topGroups: topGroups,
            roots: roots,
            issues: issues,
            completedAt: Date()
        )
    }

    // MARK: - Aggregation

    private func aggregate(
        url: URL,
        root: WeChatStorageRoot,
        rootPaths: [String],
        isCancelled: () -> Bool
    ) -> (size: Int, fileCount: Int, lastModified: Date?, issues: [WeChatStorageIssue]) {
        var size = 0
        var fileCount = 0
        var lastModified: Date?
        var symlinkIssues: [WeChatStorageIssue] = []

        func accumulate(_ attrs: URLResourceValues?) {
            guard attrs?.isRegularFile == true else { return }
            size += attrs?.fileSize ?? 0
            fileCount += 1
            if let modified = attrs?.contentModificationDate, modified > (lastModified ?? .distantPast) {
                lastModified = modified
            }
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (0, 0, nil, [])
        }
        if !isDir.boolValue {
            accumulate(try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]))
            return (size, fileCount, lastModified, symlinkIssues)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, nil, [])
        }

        for case let itemURL as URL in enumerator {
            if isCancelled() { break }
            let attrs = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
            if attrs?.isSymbolicLink == true {
                // 嵌套 symlink:不跟随;若真实路径越界(在候选 root 并集外),按 spec 报 issue,
                // 让 UI 能解释这部分为何被跳过,而不是静默丢弃。
                let realPath = itemURL.resolvingSymlinksInPath().path
                if !isWithinRoots(realPath, rootPaths: rootPaths) {
                    symlinkIssues.append(.init(rootID: root.id, rootKind: root.kind, reason: .permissionLimited, sanitizedDisplayName: root.displayName))
                }
                continue
            }
            accumulate(attrs)
        }
        return (size, fileCount, lastModified, symlinkIssues)
    }

    // MARK: - Category inference

    public static func inferCategory(path: String) -> WeChatStorageCategory {
        let components = path.lowercased().split(separator: "/").map(String.init)
        func any(_ needle: String) -> Bool { components.contains { $0.contains(needle) } }

        if any("cache") { return .cache }
        if any("log") { return .logs }
        if any("db") || any("database") || any("sqlite") || any("mmkv") { return .databasesAndState }
        if any("backup") { return .backups }
        if any("config") || any("preference") || any("setting") { return .configuration }
        if any("media") || any("file") || any("image") || any("video") || any("audio") || any("attachment") { return .mediaAndFiles }
        return .other
    }

    private func isWithinRoots(_ path: String, rootPaths: [String]) -> Bool {
        for rootPath in rootPaths {
            if path == rootPath || path.hasPrefix(rootPath + "/") { return true }
        }
        return false
    }
}
