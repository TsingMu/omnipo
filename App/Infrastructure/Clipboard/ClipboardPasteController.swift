import ApplicationServices
import Foundation

public protocol AccessibilityPermissionChecking: Sendable {
    var isTrustedForSyntheticPaste: Bool { get }
}

public protocol SyntheticPastePerforming: Sendable {
    func performPaste() -> Bool
}

public struct SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    public init() {}

    public var isTrustedForSyntheticPaste: Bool {
        AXIsProcessTrusted()
    }
}

public struct CGEventSyntheticPastePerformer: SyntheticPastePerforming {
    public init() {}

    public func performPaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

public final class ClipboardPasteController: @unchecked Sendable {
    private let repository: ClipboardRepository
    private let binaryStore: BinaryContentStore
    private let writer: any ClipboardContentWriting
    private let accessibility: any AccessibilityPermissionChecking
    private let pastePerformer: any SyntheticPastePerforming

    public init(
        repository: ClipboardRepository,
        binaryStore: BinaryContentStore,
        writer: any ClipboardContentWriting,
        accessibility: any AccessibilityPermissionChecking = SystemAccessibilityPermissionChecker(),
        pastePerformer: any SyntheticPastePerforming = CGEventSyntheticPastePerformer()
    ) {
        self.repository = repository
        self.binaryStore = binaryStore
        self.writer = writer
        self.accessibility = accessibility
        self.pastePerformer = pastePerformer
    }

    public func copyToPasteboard(_ itemID: ClipboardItem.ID) -> Result<Void, AppError> {
        do {
            let (item, payloads) = try storedPayloads(for: itemID)
            try writer.write(payloads, as: item.contentType)
            return .success(())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.systemFailure(code: "clipboard_copy_failed"))
        }
    }

    public func copyAndPaste(_ itemID: ClipboardItem.ID) -> Result<ClipboardPasteOutcome, AppError> {
        switch copyToPasteboard(itemID) {
        case .failure(let error):
            return .failure(error)
        case .success:
            guard accessibility.isTrustedForSyntheticPaste else {
                return .success(.copiedOnly(reason: "accessibility-permission-missing"))
            }
            guard pastePerformer.performPaste() else {
                return .success(.copiedOnly(reason: "synthetic-paste-failed"))
            }
            return .success(.pasted)
        }
    }

    private func storedPayloads(for itemID: ClipboardItem.ID) throws -> (ClipboardItem, [ClipboardCapturedPayload]) {
        guard let item = try repository.item(withID: itemID) else {
            throw AppError.resourceUnavailable(reason: "clipboard-item-missing")
        }
        let payloads = try repository.payloads(for: item.id).map { payload in
            ClipboardCapturedPayload(
                format: payload.format,
                data: try binaryStore.read(payload.storagePath)
            )
        }
        guard !payloads.isEmpty else {
            throw AppError.dataCorrupted(detail: "clipboard-payloads-missing")
        }
        return (item, payloads)
    }
}
