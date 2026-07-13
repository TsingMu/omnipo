import Foundation

/// 基于文件扩展名推断的展示类型，不代表内容验证结果。
public enum LargeFileKind: String, CaseIterable, Sendable, Equatable, Hashable, Identifiable {
    case video
    case image
    case audio
    case document
    case archive
    case diskImage
    case developerArtifact
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .audio: return "音频"
        case .document: return "文档"
        case .archive: return "归档"
        case .diskImage: return "磁盘映像"
        case .developerArtifact: return "开发文件"
        case .other: return "其他"
        }
    }
}

public enum LargeFileSizeBucket: String, CaseIterable, Sendable, Equatable, Hashable, Identifiable {
    case under100MiB
    case from100MiBTo1GiB
    case from1GiBTo10GiB
    case atLeast10GiB

    public static let mebibyte: Int64 = 1_048_576
    public static let gibibyte: Int64 = 1_073_741_824

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .under100MiB: return "小于 100 MB"
        case .from100MiBTo1GiB: return "100 MB–1 GB"
        case .from1GiBTo10GiB: return "1–10 GB"
        case .atLeast10GiB: return "10 GB 及以上"
        }
    }

    public static func classify(sizeBytes: Int64) -> LargeFileSizeBucket {
        let size = max(0, sizeBytes)
        if size < 100 * mebibyte { return .under100MiB }
        if size < gibibyte { return .from100MiBTo1GiB }
        if size < 10 * gibibyte { return .from1GiBTo10GiB }
        return .atLeast10GiB
    }
}

public enum LargeFileAgeBucket: String, CaseIterable, Sendable, Equatable, Hashable, Identifiable {
    case within30Days
    case withinOneYear
    case olderThanOneYear
    case unknown

    private static let day: TimeInterval = 86_400

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .within30Days: return "最近 30 天"
        case .withinOneYear: return "31 天–1 年"
        case .olderThanOneYear: return "超过 1 年"
        case .unknown: return "修改时间未知"
        }
    }

    public static func classify(lastModifiedAt: Date?, now: Date) -> LargeFileAgeBucket {
        guard let lastModifiedAt else { return .unknown }
        let age = max(0, now.timeIntervalSince(lastModifiedAt))
        if age <= 30 * day { return .within30Days }
        if age <= 365 * day { return .withinOneYear }
        return .olderThanOneYear
    }
}

/// 当前授权结果中的展示目录。`key` 只驻留内存，不得进入日志或设置。
public struct LargeFileDirectoryFacet: Sendable, Equatable, Hashable, Identifiable {
    public static let authorizedRoot = LargeFileDirectoryFacet(key: "__authorized_root__", displayName: "授权目录根部")
    public static let unavailable = LargeFileDirectoryFacet(key: "__unavailable__", displayName: "其他目录")

    public let key: String
    public let displayName: String

    public var id: String { key }

    public init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
    }
}

public struct LargeFileFacetRecord: Sendable, Equatable, Identifiable {
    public let record: LargeFileRecord
    public let kind: LargeFileKind
    public let sizeBucket: LargeFileSizeBucket
    public let ageBucket: LargeFileAgeBucket
    public let directory: LargeFileDirectoryFacet

    public var id: UUID { record.id }
}

public enum LargeFileSortOrder: String, CaseIterable, Sendable, Equatable, Hashable, Identifiable {
    case sizeDescending
    case sizeAscending
    case nameAscending
    case modifiedNewest
    case modifiedOldest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sizeDescending: return "大小：从大到小"
        case .sizeAscending: return "大小：从小到大"
        case .nameAscending: return "名称"
        case .modifiedNewest: return "修改时间：最新"
        case .modifiedOldest: return "修改时间：最早"
        }
    }
}

public struct LargeFileWorkbenchQuery: Sendable, Equatable {
    public var text: String
    public var kind: LargeFileKind?
    public var sizeBucket: LargeFileSizeBucket?
    public var ageBucket: LargeFileAgeBucket?
    public var directory: LargeFileDirectoryFacet?
    public var sortOrder: LargeFileSortOrder

    public init(
        text: String = "",
        kind: LargeFileKind? = nil,
        sizeBucket: LargeFileSizeBucket? = nil,
        ageBucket: LargeFileAgeBucket? = nil,
        directory: LargeFileDirectoryFacet? = nil,
        sortOrder: LargeFileSortOrder = .sizeDescending
    ) {
        self.text = text
        self.kind = kind
        self.sizeBucket = sizeBucket
        self.ageBucket = ageBucket
        self.directory = directory
        self.sortOrder = sortOrder
    }

    public var hasFilters: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind != nil
            || sizeBucket != nil
            || ageBucket != nil
            || directory != nil
    }
}

/// 只使用扫描结果已有元数据的纯函数分类器。
public enum LargeFileFacetClassifier {
    private static let videoExtensions: Set<String> = ["avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"]
    private static let imageExtensions: Set<String> = ["avif", "bmp", "gif", "heic", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]
    private static let audioExtensions: Set<String> = ["aac", "aiff", "alac", "flac", "m4a", "mp3", "ogg", "wav"]
    private static let documentExtensions: Set<String> = ["csv", "doc", "docx", "key", "md", "numbers", "pages", "pdf", "ppt", "pptx", "rtf", "txt", "xls", "xlsx"]
    private static let archiveExtensions: Set<String> = ["7z", "bz2", "gz", "rar", "tar", "tgz", "xz", "zip"]
    private static let diskImageExtensions: Set<String> = ["dmg", "iso", "sparsebundle", "sparseimage"]
    private static let developerExtensions: Set<String> = ["app", "c", "cpp", "h", "js", "m", "mm", "playground", "py", "swift", "ts", "xcarchive", "xcodeproj", "xcworkspace"]

    public static func classify(
        _ record: LargeFileRecord,
        authorizedRootPath: String?,
        now: Date
    ) -> LargeFileFacetRecord {
        LargeFileFacetRecord(
            record: record,
            kind: kind(for: record.name),
            sizeBucket: LargeFileSizeBucket.classify(sizeBytes: record.sizeBytes),
            ageBucket: LargeFileAgeBucket.classify(lastModifiedAt: record.lastModifiedAt, now: now),
            directory: directory(for: record.displayPath, authorizedRootPath: authorizedRootPath)
        )
    }

    public static func kind(for fileName: String) -> LargeFileKind {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return .other }
        if videoExtensions.contains(fileExtension) { return .video }
        if imageExtensions.contains(fileExtension) { return .image }
        if audioExtensions.contains(fileExtension) { return .audio }
        if documentExtensions.contains(fileExtension) { return .document }
        if archiveExtensions.contains(fileExtension) { return .archive }
        if diskImageExtensions.contains(fileExtension) { return .diskImage }
        if developerExtensions.contains(fileExtension) { return .developerArtifact }
        return .other
    }

    public static func directory(
        for displayPath: String,
        authorizedRootPath: String?
    ) -> LargeFileDirectoryFacet {
        guard let authorizedRootPath, !authorizedRootPath.isEmpty, !displayPath.isEmpty else {
            return .unavailable
        }

        let rootComponents = URL(fileURLWithPath: authorizedRootPath, isDirectory: true)
            .standardizedFileURL.pathComponents
        let fileComponents = URL(fileURLWithPath: displayPath)
            .standardizedFileURL.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return .unavailable
        }

        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        guard relativeComponents.count > 1, let firstDirectory = relativeComponents.first else {
            return .authorizedRoot
        }
        return LargeFileDirectoryFacet(key: firstDirectory, displayName: firstDirectory)
    }
}

public enum LargeFileWorkbenchQueryEngine {
    public static func classify(
        records: [LargeFileRecord],
        authorizedRootPath: String?,
        now: Date
    ) -> [LargeFileFacetRecord] {
        records.map {
            LargeFileFacetClassifier.classify($0, authorizedRootPath: authorizedRootPath, now: now)
        }
    }

    public static func apply(
        _ query: LargeFileWorkbenchQuery,
        to records: [LargeFileFacetRecord]
    ) -> [LargeFileFacetRecord] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = records.filter { item in
            let matchesText = needle.isEmpty
                || item.record.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
                || item.record.displayPath.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
            return matchesText
                && (query.kind == nil || item.kind == query.kind)
                && (query.sizeBucket == nil || item.sizeBucket == query.sizeBucket)
                && (query.ageBucket == nil || item.ageBucket == query.ageBucket)
                && (query.directory == nil || item.directory == query.directory)
        }
        return filtered.sorted { orderedBefore($0, $1, order: query.sortOrder) }
    }

    public static func directories(in records: [LargeFileFacetRecord]) -> [LargeFileDirectoryFacet] {
        Array(Set(records.map(\.directory))).sorted {
            if $0.displayName != $1.displayName {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.key < $1.key
        }
    }

    private static func orderedBefore(
        _ lhs: LargeFileFacetRecord,
        _ rhs: LargeFileFacetRecord,
        order: LargeFileSortOrder
    ) -> Bool {
        switch order {
        case .sizeDescending where lhs.record.sizeBytes != rhs.record.sizeBytes:
            return lhs.record.sizeBytes > rhs.record.sizeBytes
        case .sizeAscending where lhs.record.sizeBytes != rhs.record.sizeBytes:
            return lhs.record.sizeBytes < rhs.record.sizeBytes
        case .modifiedNewest, .modifiedOldest:
            switch (lhs.record.lastModifiedAt, rhs.record.lastModifiedAt) {
            case let (left?, right?) where left != right:
                return order == .modifiedNewest ? left > right : left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
        default:
            break
        }
        return stableNameOrder(lhs.record, rhs.record)
    }

    private static func stableNameOrder(_ lhs: LargeFileRecord, _ rhs: LargeFileRecord) -> Bool {
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.displayPath != rhs.displayPath { return lhs.displayPath < rhs.displayPath }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public struct LargeFileWorkbenchSummary: Sendable, Equatable {
    public let visibleCount: Int
    public let visibleBytes: Int64
    public let selectedCount: Int
    public let selectedBytes: Int64

    public init(
        sourceRecords: [LargeFileFacetRecord],
        visibleRecords: [LargeFileFacetRecord],
        selectedIDs: Set<UUID>
    ) {
        let selectedRecords = sourceRecords.filter { selectedIDs.contains($0.id) }
        visibleCount = visibleRecords.count
        visibleBytes = Self.totalBytes(in: visibleRecords)
        selectedCount = selectedRecords.count
        selectedBytes = Self.totalBytes(in: selectedRecords)
    }

    private static func totalBytes(in records: [LargeFileFacetRecord]) -> Int64 {
        records.reduce(0) { total, item in
            let (sum, overflow) = total.addingReportingOverflow(item.record.sizeBytes)
            return overflow ? .max : sum
        }
    }
}
