import Foundation
import UniformTypeIdentifiers

/// 遍历可读 root 的元数据并生成多维聚合；不打开或解析文件内容。
public final class WeChatStorageScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let topGroupCap: Int
    private let largeFileCap: Int
    private let conversationCap: Int
    private let conversationTopFileCap: Int

    public init(
        fileManager: FileManager = .default,
        topGroupCap: Int = 20,
        largeFileCap: Int = 500,
        conversationCap: Int = 100,
        conversationTopFileCap: Int = 5
    ) {
        self.fileManager = fileManager
        self.topGroupCap = max(1, topGroupCap)
        self.largeFileCap = max(1, largeFileCap)
        self.conversationCap = max(1, conversationCap)
        self.conversationTopFileCap = max(1, conversationTopFileCap)
    }

    public func scan(
        roots: [WeChatStorageRoot],
        options: WeChatStorageScanOptions,
        isCancelled: () -> Bool = { false }
    ) -> WeChatStorageScanResult {
        var categoryBytes: [WeChatStorageCategory: Int] = [:]
        var categoryFiles: [WeChatStorageCategory: Int] = [:]
        var assetBytes: [WeChatAssetKind: Int] = [:]
        var assetFiles: [WeChatAssetKind: Int] = [:]
        var conversations: [String: ConversationAccumulator] = [:]
        var largeFiles: [WeChatLargeFile] = []
        var unattributedBytes = 0
        var groups: [WeChatStorageGroup] = []
        var issues: [WeChatStorageIssue] = []
        var visitedDirectories = Set<String>()
        var visitedFiles = Set<String>()
        var fileSerials: [WeChatAssetKind: Int] = [:]
        var groupSerial = 0

        func appendExternalLinkIssue(for root: WeChatStorageRoot) {
            guard !issues.contains(where: {
                $0.rootID == root.id && $0.reason == .externalLinkSkipped
            }) else { return }
            issues.append(.init(
                rootID: root.id,
                rootKind: root.kind,
                reason: .externalLinkSkipped,
                sanitizedDisplayName: root.displayName
            ))
        }

        func recordFile(_ url: URL, values: URLResourceValues, root: WeChatStorageRoot) -> Bool {
            let fileIdentity = values.fileResourceIdentifier
                .map { String(describing: $0) }
                ?? url.resolvingSymlinksInPath().standardizedFileURL.path
            guard visitedFiles.insert(fileIdentity).inserted else { return false }

            let size = max(0, values.fileSize ?? 0)
            let kind = Self.inferAssetKind(url: url)
            assetBytes[kind, default: 0] += size
            assetFiles[kind, default: 0] += 1

            fileSerials[kind, default: 0] += 1
            let descriptor = Self.inferConversation(for: url, root: root)
            let file = WeChatLargeFile(
                kind: kind,
                displayName: "\(kind.displayName)文件 \(fileSerials[kind, default: 0])",
                fileName: options.includeSensitiveNames ? url.lastPathComponent : nil,
                sizeBytes: size,
                modifiedAt: values.contentModificationDate,
                conversationID: descriptor?.opaqueID
            )
            Self.insert(file, into: &largeFiles, cap: largeFileCap)

            if let descriptor {
                var accumulator = conversations[descriptor.opaqueID] ?? ConversationAccumulator(
                    conversationID: descriptor.opaqueID,
                    kind: descriptor.kind,
                    confidence: descriptor.confidence
                )
                accumulator.sizeBytes += size
                accumulator.fileCount += 1
                accumulator.assetBytes[kind, default: 0] += size
                accumulator.assetFiles[kind, default: 0] += 1
                Self.insert(file, into: &accumulator.topFiles, cap: conversationTopFileCap)
                conversations[descriptor.opaqueID] = accumulator
            } else {
                unattributedBytes += size
            }
            return true
        }

        let readableRoots = roots.filter {
            if case .readable = $0.availability { return true }
            return false
        }
        let rootPaths = readableRoots.map { $0.url.path }
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
            if !visitedDirectories.insert(root.url.path).inserted { continue }

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

                if !isWithinRoots(realPath, rootPaths: rootPaths) {
                    appendExternalLinkIssue(for: root)
                    continue
                }
                if !visitedDirectories.insert(realPath).inserted { continue }

                let aggregate = self.aggregate(
                    url: realChild,
                    root: root,
                    rootPaths: rootPaths,
                    isCancelled: isCancelled,
                    onFile: recordFile
                )
                let category = Self.inferCategory(path: realChild.path)
                categoryBytes[category, default: 0] += aggregate.size
                categoryFiles[category, default: 0] += aggregate.fileCount
                if aggregate.didSkipExternalLink {
                    appendExternalLinkIssue(for: root)
                }

                groupSerial += 1
                groups.append(WeChatStorageGroup(
                    category: category,
                    displayName: "\(category.displayName)组 \(groupSerial)",
                    sizeBytes: aggregate.size,
                    fileCount: aggregate.fileCount,
                    lastModified: aggregate.lastModified
                ))
            }
        }

        for root in roots {
            if case .unavailable(let reason) = root.availability {
                issues.append(.init(rootID: root.id, rootKind: root.kind, reason: reason, sanitizedDisplayName: root.displayName))
            }
        }
        if isCancelled() && !issues.contains(where: { $0.reason == .scanCancelled }) {
            issues.append(.init(reason: .scanCancelled))
        }

        let categories = WeChatStorageCategory.allCases.compactMap { category -> WeChatStorageCategorySummary? in
            let bytes = categoryBytes[category] ?? 0
            let files = categoryFiles[category] ?? 0
            guard bytes > 0 || files > 0 else { return nil }
            return .init(category: category, sizeBytes: bytes, fileCount: files)
        }
        let assets = WeChatAssetKind.allCases.compactMap { kind -> WeChatAssetSummary? in
            let bytes = assetBytes[kind] ?? 0
            let files = assetFiles[kind] ?? 0
            guard bytes > 0 || files > 0 else { return nil }
            return .init(kind: kind, sizeBytes: bytes, fileCount: files)
        }

        let conversationResults = conversations.values
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(conversationCap)
            .enumerated()
            .map { offset, accumulator in
                WeChatConversationUsage(
                    conversationID: accumulator.conversationID,
                    kind: accumulator.kind,
                    displayName: "\(accumulator.kind.displayName) \(offset + 1)",
                    sizeBytes: accumulator.sizeBytes,
                    fileCount: accumulator.fileCount,
                    assets: WeChatAssetKind.allCases.compactMap { kind in
                        let bytes = accumulator.assetBytes[kind] ?? 0
                        let files = accumulator.assetFiles[kind] ?? 0
                        guard bytes > 0 || files > 0 else { return nil }
                        return WeChatAssetSummary(kind: kind, sizeBytes: bytes, fileCount: files)
                    },
                    topFiles: accumulator.topFiles.sorted { $0.sizeBytes > $1.sizeBytes },
                    confidence: accumulator.confidence
                )
            }

        return WeChatStorageScanResult(
            totalVisibleBytes: categories.reduce(0) { $0 + $1.sizeBytes },
            categories: categories,
            assets: assets,
            largeFiles: largeFiles.sorted { $0.sizeBytes > $1.sizeBytes },
            conversations: conversationResults,
            unattributedBytes: unattributedBytes,
            sensitiveNamesIncluded: options.includeSensitiveNames,
            topGroups: groups.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(topGroupCap).map { $0 },
            roots: roots,
            issues: issues,
            completedAt: Date()
        )
    }

    public func scan(
        roots: [WeChatStorageRoot],
        isCancelled: () -> Bool = { false }
    ) -> WeChatStorageScanResult {
        scan(roots: roots, options: .anonymous, isCancelled: isCancelled)
    }

    private func aggregate(
        url: URL,
        root: WeChatStorageRoot,
        rootPaths: [String],
        isCancelled: () -> Bool,
        onFile: (URL, URLResourceValues, WeChatStorageRoot) -> Bool
    ) -> (size: Int, fileCount: Int, lastModified: Date?, didSkipExternalLink: Bool) {
        let resourceKeys: Set<URLResourceKey> = [
            .fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
            .isSymbolicLinkKey, .fileResourceIdentifierKey
        ]
        var size = 0
        var fileCount = 0
        var lastModified: Date?
        var didSkipExternalLink = false

        func accumulate(_ fileURL: URL, _ values: URLResourceValues?) {
            guard let values, values.isRegularFile == true, onFile(fileURL, values, root) else { return }
            size += max(0, values.fileSize ?? 0)
            fileCount += 1
            if let modified = values.contentModificationDate, modified > (lastModified ?? .distantPast) {
                lastModified = modified
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return (0, 0, nil, false)
        }
        if !isDirectory.boolValue {
            accumulate(url, try? url.resourceValues(forKeys: resourceKeys))
            return (size, fileCount, lastModified, false)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, nil, false)
        }

        for case let itemURL as URL in enumerator {
            if isCancelled() { break }
            let values = try? itemURL.resourceValues(forKeys: resourceKeys)
            if values?.isSymbolicLink == true {
                let realPath = itemURL.resolvingSymlinksInPath().path
                if !isWithinRoots(realPath, rootPaths: rootPaths) {
                    didSkipExternalLink = true
                }
                continue
            }
            accumulate(itemURL, values)
        }
        return (size, fileCount, lastModified, didSkipExternalLink)
    }

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

    public static func inferAssetKind(url: URL) -> WeChatAssetKind {
        let ext = url.pathExtension.lowercased()
        if databaseExtensions.contains(ext) { return .database }
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .audio) { return .audio }
        }

        let components = url.path.lowercased().split(separator: "/").map(String.init)
        if components.contains(where: { videoPathMarkers.contains($0) }) { return .video }
        if components.contains(where: { imagePathMarkers.contains($0) }) { return .image }
        if components.contains(where: { audioPathMarkers.contains($0) }) { return .audio }
        return .other
    }

    private static func inferConversation(for url: URL, root: WeChatStorageRoot) -> ConversationDescriptor? {
        let rootPath = root.url.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return nil }

        let relative = String(path.dropFirst(rootPath.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard components.count >= 3,
              let messageIndex = components.firstIndex(where: { messageMarkers.contains($0.lowercased()) }) else {
            return nil
        }

        var candidateIndex = messageIndex + 1
        while candidateIndex < components.count - 1 {
            let component = components[candidateIndex]
            let lower = component.lowercased()
            if structuralComponents.contains(lower) || isDateComponent(lower) {
                candidateIndex += 1
                continue
            }
            guard looksLikeConversationIdentifier(component) else { return nil }

            let kind: WeChatConversationKind
            let confidence: WeChatAttributionConfidence
            if lower.contains("chatroom") || lower.contains("group") {
                kind = .group
                confidence = .high
            } else if lower.hasPrefix("wxid_") || lower.contains("contact") || lower.contains("user") {
                kind = .directMessage
                confidence = .high
            } else {
                kind = .unknown
                confidence = .inferred
            }
            let opaqueID = stableOpaqueID("\(root.url.path)|\(component)")
            return ConversationDescriptor(opaqueID: opaqueID, kind: kind, confidence: confidence)
        }
        return nil
    }

    private static func looksLikeConversationIdentifier(_ component: String) -> Bool {
        guard component.count >= 4, component.count <= 128, !component.contains(".") else { return false }
        return component.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "_@-".unicodeScalars.contains($0)
        }
    }

    private static func isDateComponent(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count == value.count && [4, 6, 8].contains(value.count)
    }

    private static func stableOpaqueID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func insert(_ file: WeChatLargeFile, into files: inout [WeChatLargeFile], cap: Int) {
        if files.count < cap {
            files.append(file)
            return
        }
        guard let smallestIndex = files.indices.min(by: { files[$0].sizeBytes < files[$1].sizeBytes }),
              file.sizeBytes > files[smallestIndex].sizeBytes else { return }
        files[smallestIndex] = file
    }

    private func isWithinRoots(_ path: String, rootPaths: [String]) -> Bool {
        rootPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private struct ConversationDescriptor {
        let opaqueID: String
        let kind: WeChatConversationKind
        let confidence: WeChatAttributionConfidence
    }

    private struct ConversationAccumulator {
        let conversationID: String
        let kind: WeChatConversationKind
        let confidence: WeChatAttributionConfidence
        var sizeBytes = 0
        var fileCount = 0
        var assetBytes: [WeChatAssetKind: Int] = [:]
        var assetFiles: [WeChatAssetKind: Int] = [:]
        var topFiles: [WeChatLargeFile] = []
    }

    private static let messageMarkers: Set<String> = ["msg", "message", "messages"]
    private static let structuralComponents: Set<String> = [
        "attach", "attachment", "attachments", "media", "image", "images", "img",
        "video", "videos", "audio", "voice", "file", "files", "thumb", "thumbnail", "thumbnails"
    ]
    private static let databaseExtensions: Set<String> = ["db", "db3", "sqlite", "sqlite3", "mmkv"]
    private static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"]
    private static let documentExtensions: Set<String> = [
        "pdf", "txt", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "pages", "numbers", "key", "csv", "md", "html", "htm"
    ]
    private static let videoPathMarkers: Set<String> = ["video", "videos", "movie", "movies"]
    private static let imagePathMarkers: Set<String> = ["image", "images", "img", "photo", "photos", "picture", "pictures"]
    private static let audioPathMarkers: Set<String> = ["audio", "voice", "voices", "sound", "sounds"]
}
