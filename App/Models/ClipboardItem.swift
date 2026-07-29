import Foundation

public struct ClipboardItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var contentHash: String
    public var contentType: ClipboardContentType
    public var textPreview: String?
    public var sourceApplicationID: String?
    public var isFavorite: Bool
    public var isDeleted: Bool
    public var timesUsed: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        contentHash: String,
        contentType: ClipboardContentType,
        textPreview: String? = nil,
        sourceApplicationID: String? = nil,
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        timesUsed: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.contentHash = contentHash
        self.contentType = contentType
        self.textPreview = textPreview
        self.sourceApplicationID = sourceApplicationID
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.timesUsed = max(0, timesUsed)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ClipboardQuery: Sendable, Hashable {
    public var searchText: String
    public var contentType: ClipboardContentType?
    public var favoritesOnly: Bool
    public var includeDeleted: Bool
    public var limit: Int
    public var offset: Int

    public init(
        searchText: String = "",
        contentType: ClipboardContentType? = nil,
        favoritesOnly: Bool = false,
        includeDeleted: Bool = false,
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.searchText = searchText
        self.contentType = contentType
        self.favoritesOnly = favoritesOnly
        self.includeDeleted = includeDeleted
        self.limit = max(1, limit)
        self.offset = max(0, offset)
    }
}

public enum ClipboardPasteOutcome: Sendable, Hashable {
    case pasted
    case copiedOnly(reason: String)
}

/// 图片记录的有界缩略图数据。
///
/// 由 `ClipboardService` 从现有 image payload 异步生成,以 PNG 字节形式跨并发域传递,
/// 由 UI 转换为 `NSImage` 展示。`maxPixelSize` 覆盖最大预览尺寸(主页面 48pt @3x),保证清晰。
public struct ClipboardImageThumbnail: Sendable, Hashable {
    public static let maxPixelSize: Int = 160

    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}
