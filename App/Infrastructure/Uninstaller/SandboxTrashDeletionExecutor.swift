import Foundation

public final class SandboxTrashDeletionExecutor: DeletionExecutor, @unchecked Sendable {
    public typealias TrashHandler = @Sendable (URL) throws -> URL?

    public let kind: DeletionExecutorKind = .sandboxTrash
    private let authorizedRoots: [URL]
    private let trashHandler: TrashHandler
    private let cancellation = UninstallerCancellationFlag()

    public init(
        authorizedRoots: [URL],
        trashHandler: TrashHandler? = nil
    ) {
        self.authorizedRoots = authorizedRoots.map(\.standardizedFileURL)
        self.trashHandler = trashHandler ?? { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL as URL?
        }
    }

    public func canDelete(_ item: AppAssociatedFile) async -> Bool {
        item.unavailableReason == nil && isInsideAuthorizedRoot(item.url)
    }

    public func delete(_ items: [AppAssociatedFile]) async -> [UninstallExecutionItemResult] {
        var results: [UninstallExecutionItemResult] = []
        for item in items {
            if cancelled {
                results.append(UninstallExecutionItemResult(
                    item: item,
                    status: .cancelled,
                    reasonCode: AppError.cancelled.stableCode
                ))
                continue
            }

            guard await canDelete(item) else {
                results.append(UninstallExecutionItemResult(
                    item: item,
                    status: .insufficientPermission,
                    reasonCode: AssociatedFileUnavailableReason.permissionLimited.stableCode
                ))
                continue
            }

            guard FileManager.default.fileExists(atPath: item.url.path) else {
                results.append(UninstallExecutionItemResult(
                    item: item,
                    status: .skipped,
                    reasonCode: AssociatedFileUnavailableReason.resourceUnavailable.stableCode
                ))
                continue
            }

            do {
                _ = try trashHandler(item.url)
                results.append(UninstallExecutionItemResult(item: item, status: .succeeded))
            } catch {
                results.append(UninstallExecutionItemResult(
                    item: item,
                    status: .failed,
                    reasonCode: AppError.systemFailure(code: "TRASH_FAILED").stableCode
                ))
            }
        }
        return results
    }

    public func cancel() async {
        cancellation.set()
    }

    private var cancelled: Bool {
        cancellation.isSet
    }

    private func isInsideAuthorizedRoot(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return authorizedRoots.contains { root in
            let rootPath = root.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }
}
