import Foundation

public extension Notification.Name {
    static let clipboardHistoryDidChange = Notification.Name("com.qing.omnipo.clipboard.historyDidChange")
}

public enum ClipboardServiceAvailability: Sendable, Equatable {
    case available
    case unavailable(AppError)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public protocol ClipboardService: AnyObject, Sendable {
    var availability: ClipboardServiceAvailability { get async }
    var isEnabled: Bool { get async }
    var hasAcknowledgedLocalStorageNotice: Bool { get async }

    func setEnabled(_ isEnabled: Bool) async -> Result<Void, AppError>
    func acknowledgeLocalStorageNotice() async -> Result<Void, AppError>
    func records(matching query: ClipboardQuery) async -> Result<[ClipboardItem], AppError>
    func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async -> Result<Void, AppError>
    func delete(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError>
    func copyToPasteboard(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError>
    func copyAndPaste(_ itemID: ClipboardItem.ID) async -> Result<ClipboardPasteOutcome, AppError>
    func copyAndPaste(_ itemID: ClipboardItem.ID, targetProcessIdentifier: pid_t?) async -> Result<ClipboardPasteOutcome, AppError>
}

public extension ClipboardService {
    var availability: ClipboardServiceAvailability {
        get async { .available }
    }

    func copyAndPaste(_ itemID: ClipboardItem.ID) async -> Result<ClipboardPasteOutcome, AppError> {
        await copyAndPaste(itemID, targetProcessIdentifier: nil)
    }
}
