import Foundation

/// 大文件枚举器(纯函数)。
///
/// 不持有状态、不读文件内容,只调用 `FileManager.enumerator` 收集 `fileSize`
/// 与 `contentModificationDate` 等元数据。失败根目录被跳过,聚合所有可读根的结果。
/// 完全不可读时返回 `.permissionLimited`,与 design 中"不绕过 Sandbox"原则一致。
public enum LargeFileScanner {

    /// 默认扫描根的相对路径;空串代表用户主目录本身。
    /// 子目录单独列出,允许在 home 不可读时仍尝试常见大占用目录。
    public static let defaultRootRelativePaths: [String] = [
        "",
        "Downloads",
        "Documents",
        "Desktop",
        "Movies",
        "Pictures",
        "Music"
    ]

    /// 扫描时跳过的子树名;命中即 `skipDescendants`。
    /// 这些目录要么是系统缓存(对"大文件"语义无意义),要么是隐私敏感,
    /// 要么是大量小文件拖慢扫描。具体跳过策略可在 design 中追溯。
    public static let skippedSubtreeNames: Set<String> = [
        "Library",          // ~/Library:系统配置、缓存、容器
        ".Trash",           // 废纸篓
        ".cache",
        "Caches",
        "Containers",       // App Sandbox 容器
        "Application Scripts",
        "Group Containers", // App Group 共享容器
        ".DocumentRevisions-V100",  // 系统版本快照
        ".PKInstallSandboxManager",
        ".MobileDocuments", // iCloud Drive 同步目录(由系统单独索引)
        "node_modules",     // 开发依赖,通常不是用户关心的大文件
        ".git"
    ]

    /// 为指定 home 目录推导默认扫描根集合。
    public static func defaultRoots(
        forHomeDirectory home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        defaultRootRelativePaths.map { relative in
            relative.isEmpty ? home : home.appendingPathComponent(relative)
        }
    }

    /// 扫描给定根集合,按大小降序返回前 `limit` 条记录。
    ///
    /// - 单根失败(沙盒、不存在、无权限)被跳过,不影响其他根。
    /// - 全部根都失败时返回 `.unavailable(reason: .permissionLimited)`。
    /// - 同一路径在不同根下重复出现时只保留一条。
    /// - `limit <= 0` 视为无效请求,返回 `.unavailable(reason: .scanNotStarted)`。
    public static func scan(
        roots: [URL],
        fileManager: FileManager = .default,
        limit: Int,
        volumeIdentifier: String,
        now: Date = .now
    ) -> LargeFileAvailability {
        _ = now  // 预留给后续"刷新时间戳"使用,目前不影响排序
        guard limit > 0 else {
            return .unavailable(reason: .scanNotStarted)
        }
        guard !roots.isEmpty else {
            return .unavailable(reason: .scanNotStarted)
        }

        var records: [LargeFileRecord] = []
        var seenPaths = Set<String>()
        var anyRootReadable = false

        let resourceKeys: [URLResourceKey] = [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey
        ]

        for root in roots {
            // fileManager.enumerator 对某些不存在路径可能返回非 nil 空 enumerator;
            // 用 fileExists 显式预检,确保只把真正可读的根算作 anyRootReadable。
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            guard let enumerator = try? fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            anyRootReadable = true

            let keySet = Set(resourceKeys)
            let skipped = Self.skippedSubtreeNames
            for case let url as URL in enumerator {
                // 跳过系统/缓存子树;命中后 skipDescendants 避免继续递归。
                let lastComponent = url.lastPathComponent
                let isSkippedSubtree = skipped.contains(lastComponent)
                if isSkippedSubtree {
                    enumerator.skipDescendants()
                    continue
                }

                // 兜底:某些 enumerator 顺序下 skipDescendants 可能漏网,
                // 显式检查路径任意一段是否命中跳过集合。
                if url.pathComponents.contains(where: { skipped.contains($0) }) {
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: keySet) else {
                    continue
                }
                guard values.isRegularFile == true else { continue }
                guard let size = values.fileSize else { continue }
                let path = url.path(percentEncoded: false)
                guard seenPaths.insert(path).inserted else { continue }
                records.append(
                    LargeFileRecord(
                        name: url.lastPathComponent,
                        displayPath: path,
                        sizeBytes: Int64(size),
                        lastModifiedAt: values.contentModificationDate,
                        sourceVolumeIdentifier: volumeIdentifier
                    )
                )
            }
        }

        guard anyRootReadable else {
            return .unavailable(reason: .permissionLimited)
        }

        return LargeFileAvailability.available(records)
            .sortedBySizeDescending()
            .limited(to: limit)
    }
}
