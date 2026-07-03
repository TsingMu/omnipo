import Foundation

public enum ClipboardContentType: String, CaseIterable, Codable, Sendable, Hashable {
    case plainText
    case richText
    case html
    case image
    case fileURL

    public var displayName: String {
        switch self {
        case .plainText: return "文本"
        case .richText: return "富文本"
        case .html: return "HTML"
        case .image: return "图片"
        case .fileURL: return "文件"
        }
    }
}
