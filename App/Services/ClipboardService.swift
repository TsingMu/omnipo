import Foundation

public protocol ClipboardService: AnyObject, Sendable {
    var isEnabled: Bool { get async }
    var hasAcknowledgedLocalStorageNotice: Bool { get async }

    func setEnabled(_ isEnabled: Bool) async -> Result<Void, AppError>
    func acknowledgeLocalStorageNotice() async -> Result<Void, AppError>
    func records(matching query: ClipboardQuery) async -> Result<[ClipboardItem], AppError>
    func setFavorite(_ isFavorite: Bool, for itemID: ClipboardItem.ID) async -> Result<Void, AppError>
    func delete(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError>
    func copyToPasteboard(_ itemID: ClipboardItem.ID) async -> Result<Void, AppError>
    func copyAndPaste(_ itemID: ClipboardItem.ID) async -> Result<ClipboardPasteOutcome, AppError>
}
