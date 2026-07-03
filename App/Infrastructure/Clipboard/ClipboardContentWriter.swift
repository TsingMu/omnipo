import AppKit
import Foundation

public protocol ClipboardContentWriting: AnyObject, Sendable {
    func write(_ payloads: [ClipboardCapturedPayload], as contentType: ClipboardContentType) throws
}

public final class SystemClipboardContentWriter: ClipboardContentWriting, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func write(_ payloads: [ClipboardCapturedPayload], as contentType: ClipboardContentType) throws {
        pasteboard.clearContents()
        switch contentType {
        case .plainText:
            guard let text = stringPayload(.plainText, in: payloads) else {
                throw AppError.dataCorrupted(detail: "clipboard-plain-text-missing")
            }
            pasteboard.setString(text, forType: .string)
        case .richText:
            try writeRichText(payloads)
        case .html:
            try writeHTML(payloads)
        case .image:
            guard let data = dataPayload(.image, in: payloads), let image = NSImage(data: data) else {
                throw AppError.dataCorrupted(detail: "clipboard-image-missing")
            }
            pasteboard.writeObjects([image])
        case .fileURL:
            let urls = try fileURLPayload(in: payloads)
            guard pasteboard.writeObjects(urls.map { $0 as NSURL }) else {
                throw AppError.resourceUnavailable(reason: "pasteboard-file-url-write-failed")
            }
        }
    }

    private func writeRichText(_ payloads: [ClipboardCapturedPayload]) throws {
        var wrote = false
        if let rtf = dataPayload(.rtf, in: payloads) {
            pasteboard.setData(rtf, forType: .rtf)
            wrote = true
        }
        if let text = stringPayload(.plainText, in: payloads) {
            pasteboard.setString(text, forType: .string)
            wrote = true
        }
        guard wrote else {
            throw AppError.dataCorrupted(detail: "clipboard-rich-text-missing")
        }
    }

    private func writeHTML(_ payloads: [ClipboardCapturedPayload]) throws {
        guard let html = dataPayload(.html, in: payloads) else {
            throw AppError.dataCorrupted(detail: "clipboard-html-missing")
        }
        pasteboard.setData(html, forType: .html)
        if let text = stringPayload(.plainText, in: payloads) {
            pasteboard.setString(text, forType: .string)
        }
    }

    private func fileURLPayload(in payloads: [ClipboardCapturedPayload]) throws -> [URL] {
        guard let data = dataPayload(.fileURLs, in: payloads) else {
            throw AppError.dataCorrupted(detail: "clipboard-file-urls-missing")
        }
        let paths = try JSONDecoder().decode([String].self, from: data)
        return paths.map { URL(fileURLWithPath: $0) }
    }

    private func dataPayload(_ format: ClipboardPayloadFormat, in payloads: [ClipboardCapturedPayload]) -> Data? {
        payloads.first(where: { $0.format == format })?.data
    }

    private func stringPayload(_ format: ClipboardPayloadFormat, in payloads: [ClipboardCapturedPayload]) -> String? {
        guard let data = dataPayload(format, in: payloads) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
