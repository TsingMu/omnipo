import Foundation

public final class FinderAutomationDeletionExecutor: DeletionExecutor, @unchecked Sendable {
    public typealias AutomationDeleteHandler = @Sendable ([URL]) async throws -> Set<URL>

    public let kind: DeletionExecutorKind = .finderAutomation
    private let automationDeleteHandler: AutomationDeleteHandler?
    private let cancellation = UninstallerCancellationFlag()

    public init(automationDeleteHandler: AutomationDeleteHandler? = nil) {
        self.automationDeleteHandler = automationDeleteHandler
    }

    public func canDelete(_ item: AppAssociatedFile) async -> Bool {
        automationDeleteHandler != nil && item.unavailableReason == nil
    }

    public func delete(_ items: [AppAssociatedFile]) async -> [UninstallExecutionItemResult] {
        guard !items.isEmpty else { return [] }
        guard !cancelled else {
            return items.map {
                UninstallExecutionItemResult(
                    item: $0,
                    status: .cancelled,
                    reasonCode: AppError.cancelled.stableCode
                )
            }
        }
        guard let automationDeleteHandler else {
            return items.map {
                UninstallExecutionItemResult(
                    item: $0,
                    status: .insufficientPermission,
                    reasonCode: AssociatedFileUnavailableReason.permissionLimited.stableCode
                )
            }
        }

        let eligibleItems = items.filter { $0.unavailableReason == nil }
        let ineligibleResults = items.filter { $0.unavailableReason != nil }.map {
            UninstallExecutionItemResult(
                item: $0,
                status: .insufficientPermission,
                reasonCode: $0.unavailableReason?.stableCode
            )
        }

        do {
            let succeededURLs = try await automationDeleteHandler(eligibleItems.map(\.url))
            let deletionResults = eligibleItems.map { item in
                if succeededURLs.contains(item.url) || succeededURLs.contains(item.url.standardizedFileURL) {
                    return UninstallExecutionItemResult(item: item, status: .succeeded)
                }
                return UninstallExecutionItemResult(
                    item: item,
                    status: .failed,
                    reasonCode: AppError.systemFailure(code: "FINDER_DELETE_FAILED").stableCode
                )
            }
            return ineligibleResults + deletionResults
        } catch {
            return items.map {
                UninstallExecutionItemResult(
                    item: $0,
                    status: .failed,
                    reasonCode: AppError.systemFailure(code: "FINDER_AUTOMATION_FAILED").stableCode
                )
            }
        }
    }

    public func cancel() async {
        cancellation.set()
    }

    private var cancelled: Bool {
        cancellation.isSet
    }
}
