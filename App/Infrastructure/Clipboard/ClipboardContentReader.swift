import AppKit
import CryptoKit
import Foundation

public struct ClipboardPasteboardSnapshot: Sendable, Hashable {
    public let plainText: String?
    public let rtf: Data?
    public let html: Data?
    public let image: Data?
    public let fileURLs: [URL]

    public init(
        plainText: String? = nil,
        rtf: Data? = nil,
        html: Data? = nil,
        image: Data? = nil,
        fileURLs: [URL] = []
    ) {
        self.plainText = plainText
        self.rtf = rtf
        self.html = html
        self.image = image
        self.fileURLs = fileURLs
    }
}

public protocol ClipboardContentReading: AnyObject, Sendable {
    func readCurrentContent() throws -> ClipboardCapturedContent?
}

public final class SystemClipboardContentReader: ClipboardContentReading, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func readCurrentContent() throws -> ClipboardCapturedContent? {
        ClipboardContentClassifier.capturedContent(
            from: ClipboardPasteboardSnapshot(
                plainText: pasteboard.string(forType: .string),
                rtf: pasteboard.data(forType: .rtf),
                html: pasteboard.data(forType: .html),
                image: readImageData(),
                fileURLs: readFileURLs()
            )
        )
    }

    private func readImageData() -> Data? {
        if let tiff = pasteboard.data(forType: .tiff) {
            return tiff
        }
        return NSImage(pasteboard: pasteboard)?.tiffRepresentation
    }

    private func readFileURLs() -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { object in
            if let url = object as? URL {
                return url
            }
            if let nsURL = object as? NSURL {
                return nsURL as URL
            }
            return nil
        }
    }
}

public enum ClipboardContentClassifier {
    public static func capturedContent(from snapshot: ClipboardPasteboardSnapshot) -> ClipboardCapturedContent? {
        if !snapshot.fileURLs.isEmpty {
            return fileURLContent(from: snapshot)
        }
        if let image = snapshot.image, !image.isEmpty {
            return content(
                type: .image,
                preview: nil,
                payloads: [ClipboardCapturedPayload(format: .image, data: image)]
            )
        }
        if let html = snapshot.html, !html.isEmpty {
            var payloads = [ClipboardCapturedPayload(format: .html, data: html)]
            appendPlainText(snapshot.plainText, to: &payloads)
            return content(
                type: .html,
                preview: preview(snapshot.plainText ?? String(data: html, encoding: .utf8)),
                payloads: payloads
            )
        }
        if let rtf = snapshot.rtf, !rtf.isEmpty {
            var payloads = [ClipboardCapturedPayload(format: .rtf, data: rtf)]
            appendPlainText(snapshot.plainText, to: &payloads)
            return content(
                type: .richText,
                preview: preview(snapshot.plainText),
                payloads: payloads
            )
        }
        guard let text = snapshot.plainText,
              !text.isEmpty,
              let data = text.data(using: .utf8) else {
            return nil
        }
        return content(
            type: .plainText,
            preview: preview(text),
            payloads: [ClipboardCapturedPayload(format: .plainText, data: data)]
        )
    }

    private static func fileURLContent(from snapshot: ClipboardPasteboardSnapshot) -> ClipboardCapturedContent? {
        let paths = snapshot.fileURLs.map(\.path)
        guard let data = try? JSONEncoder().encode(paths) else {
            return nil
        }
        var payloads = [ClipboardCapturedPayload(format: .fileURLs, data: data)]
        appendPlainText(snapshot.plainText, to: &payloads)
        return content(
            type: .fileURL,
            preview: preview(snapshot.fileURLs.map(\.lastPathComponent).joined(separator: ", ")),
            payloads: payloads
        )
    }

    private static func content(
        type: ClipboardContentType,
        preview: String?,
        payloads: [ClipboardCapturedPayload]
    ) -> ClipboardCapturedContent {
        ClipboardCapturedContent(
            contentHash: ClipboardContentHasher.hash(payloads: payloads),
            contentType: type,
            textPreview: preview,
            payloads: payloads
        )
    }

    private static func appendPlainText(_ text: String?, to payloads: inout [ClipboardCapturedPayload]) {
        guard let text, !text.isEmpty, let data = text.data(using: .utf8) else { return }
        payloads.append(ClipboardCapturedPayload(format: .plainText, data: data))
    }

    private static func preview(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= 240 {
            return collapsed
        }
        return String(collapsed.prefix(240))
    }
}

public enum ClipboardContentHasher {
    public static func hash(payloads: [ClipboardCapturedPayload]) -> String {
        var hasher = SHA256()
        for payload in payloads.sorted(by: { $0.format.rawValue < $1.format.rawValue }) {
            hasher.update(data: Data(payload.format.rawValue.utf8))
            hasher.update(data: [0])
            hasher.update(data: payload.data)
            hasher.update(data: [0])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
