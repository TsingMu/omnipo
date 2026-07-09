import Foundation

public final class FinderAutomationDeletionExecutor: DeletionExecutor, @unchecked Sendable {
    public typealias AutomationDeleteHandler = @Sendable ([URL]) async throws -> Set<URL>

    public let kind: DeletionExecutorKind = .finderAutomation
    private let automationDeleteHandler: AutomationDeleteHandler
    private let cancellation = UninstallerCancellationFlag()

    public init(automationDeleteHandler: AutomationDeleteHandler? = nil) {
        self.automationDeleteHandler = automationDeleteHandler ?? Self.deleteWithFinderAutomation(urls:)
    }

    public func canDelete(_ item: AppAssociatedFile) async -> Bool {
        item.unavailableReason == nil
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
        } catch FinderAutomationError.authorizationDenied {
            return items.map {
                UninstallExecutionItemResult(
                    item: $0,
                    status: .insufficientPermission,
                    reasonCode: AssociatedFileUnavailableReason.permissionLimited.stableCode
                )
            }
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

    private static func deleteWithFinderAutomation(urls: [URL]) async throws -> Set<URL> {
        let standardizedURLs = Set(urls.map(\.standardizedFileURL))
        guard !standardizedURLs.isEmpty else { return [] }

        let source = finderDeleteScript(for: Array(standardizedURLs))
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw FinderAutomationError.scriptCreationFailed
        }

        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                throw FinderAutomationError.authorizationDenied
            }
            throw FinderAutomationError.appleScriptFailed
        }
        if result.descriptorType == typeNull {
            return standardizedURLs
        }
        return standardizedURLs
    }

    static func finderDeleteScript(for urls: [URL]) -> String {
        let fileReferences = urls
            .map(\.standardizedFileURL)
            .map { "POSIX file \(appleScriptStringLiteral($0.path))" }
            .joined(separator: ", ")
        return """
        tell application id "com.apple.finder"
            delete {\(fileReferences)}
        end tell
        """
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private enum FinderAutomationError: Error {
    case authorizationDenied
    case scriptCreationFailed
    case appleScriptFailed
}
