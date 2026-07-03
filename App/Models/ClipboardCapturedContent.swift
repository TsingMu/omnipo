import Foundation

public struct ClipboardCapturedPayload: Sendable, Hashable {
    public let format: ClipboardPayloadFormat
    public let data: Data

    public init(format: ClipboardPayloadFormat, data: Data) {
        self.format = format
        self.data = data
    }
}

public struct ClipboardCapturedContent: Sendable, Hashable {
    public let contentHash: String
    public let contentType: ClipboardContentType
    public let textPreview: String?
    public let sourceApplicationID: String?
    public let payloads: [ClipboardCapturedPayload]

    public init(
        contentHash: String,
        contentType: ClipboardContentType,
        textPreview: String?,
        sourceApplicationID: String? = nil,
        payloads: [ClipboardCapturedPayload]
    ) {
        self.contentHash = contentHash
        self.contentType = contentType
        self.textPreview = textPreview
        self.sourceApplicationID = sourceApplicationID
        self.payloads = payloads
    }

    public func withSourceApplicationID(_ sourceApplicationID: String?) -> ClipboardCapturedContent {
        ClipboardCapturedContent(
            contentHash: contentHash,
            contentType: contentType,
            textPreview: textPreview,
            sourceApplicationID: self.sourceApplicationID ?? sourceApplicationID,
            payloads: payloads
        )
    }
}
