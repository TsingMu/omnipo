import Foundation

/// 二进制内容的原始格式标识。一条 `ClipboardItem` 可关联多个不同格式的 payload。
public enum ClipboardPayloadFormat: String, CaseIterable, Codable, Sendable, Hashable {
    case plainText
    case rtf
    case html
    case image
    case fileURLs
}

/// 剪切板二进制内容的元数据:对应 `clipboard_binary_payloads` 表一行。
///
/// `storagePath` 为相对 `BinaryContentStore` 根目录的文件名,文件读写交由 `BinaryContentStore` 负责。
public struct ClipboardBinaryPayload: Sendable, Hashable {
    public let recordID: ClipboardItem.ID
    public let format: ClipboardPayloadFormat
    public let storagePath: String
    public let fileSize: Int
    public let createdAt: Date

    public init(
        recordID: ClipboardItem.ID,
        format: ClipboardPayloadFormat,
        storagePath: String,
        fileSize: Int,
        createdAt: Date = Date()
    ) {
        self.recordID = recordID
        self.format = format
        self.storagePath = storagePath
        self.fileSize = max(0, fileSize)
        self.createdAt = createdAt
    }
}
