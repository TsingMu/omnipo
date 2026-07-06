import Foundation

extension ClipboardContentType {
    var symbolName: String {
        switch self {
        case .plainText: return "text.alignleft"
        case .richText: return "doc.richtext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .fileURL: return "doc"
        }
    }
}
