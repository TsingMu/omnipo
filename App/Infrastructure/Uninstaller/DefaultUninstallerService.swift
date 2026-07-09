import Foundation

public final class DefaultUninstallerService: UninstallerService, @unchecked Sendable {
    private let applicationScanner: InstalledApplicationScanner
    private let associatedFileScanner: AssociatedFileScanner
    private let deletionExecutor: any DeletionExecutor
    private let applicationRoots: [URL]
    private let associatedFileRoots: [AssociatedFileScanRoot]
    private let cancellation = UninstallerCancellationFlag()

    public init(
        applicationScanner: InstalledApplicationScanner = InstalledApplicationScanner(),
        associatedFileScanner: AssociatedFileScanner = AssociatedFileScanner(),
        deletionExecutor: any DeletionExecutor = FinderAutomationDeletionExecutor(),
        applicationRoots: [URL] = InstalledApplicationScanner.defaultSearchRoots,
        associatedFileRoots: [AssociatedFileScanRoot] = AssociatedFileScanner.defaultRoots()
    ) {
        self.applicationScanner = applicationScanner
        self.associatedFileScanner = associatedFileScanner
        self.deletionExecutor = deletionExecutor
        self.applicationRoots = applicationRoots
        self.associatedFileRoots = associatedFileRoots
    }

    public func installedApplications(matching query: UninstallerQuery) async -> Result<[InstalledApplication], AppError> {
        guard !cancelled else { return .failure(.cancelled) }

        let result = await applicationScanner.scan(roots: applicationRoots)
        let filtered = result.applications.filter { application in
            if !query.includeSystemApplications && application.isSystemProtected {
                return false
            }
            let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !searchText.isEmpty else { return true }
            return application.displayName.localizedCaseInsensitiveContains(searchText)
                || application.localizedDisplayName?.localizedCaseInsensitiveContains(searchText) == true
                || application.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) == true
        }
        return .success(filtered)
    }

    public func buildPlan(
        for application: InstalledApplication,
        mode: UninstallMode
    ) async -> Result<AppUninstallPlan, AppError> {
        guard !cancelled else { return .failure(.cancelled) }

        let applicationItem = Self.applicationBundleItem(for: application)
        switch mode {
        case .removeApplicationOnly:
            return .success(AppUninstallPlan(
                application: application,
                mode: mode,
                items: [applicationItem]
            ))
        case .removeApplicationAndAssociatedFiles:
            let scan = associatedFileScanner.scan(for: application, roots: associatedFileRoots)
            let safeAssociatedFiles = scan.files.filter { file in
                file.unavailableReason == nil || file.isUserSelectable == false
            }
            return .success(AppUninstallPlan(
                application: application,
                mode: mode,
                items: [applicationItem] + safeAssociatedFiles
            ))
        }
    }

    public func execute(plan: AppUninstallPlan) async -> Result<UninstallExecutionResult, AppError> {
        guard !cancelled else { return .failure(.cancelled) }

        var immediateResults: [UninstallExecutionItemResult] = []
        var deletableItems: [AppAssociatedFile] = []

        for item in plan.selectedItems {
            if let reason = item.unavailableReason {
                immediateResults.append(Self.result(for: item, reason: reason))
            } else {
                deletableItems.append(item)
            }
        }

        guard !cancelled else { return .failure(.cancelled) }
        let deletionResults = await deletionExecutor.delete(deletableItems)
        return .success(UninstallExecutionResult(
            planID: plan.id,
            itemResults: immediateResults + deletionResults
        ))
    }

    public func cancel() async {
        cancellation.set()
        await deletionExecutor.cancel()
    }

    public func resetCancellation() {
        cancellation.reset()
    }

    private var cancelled: Bool {
        cancellation.isSet
    }

    public static func applicationBundleItem(for application: InstalledApplication) -> AppAssociatedFile {
        let reason: AssociatedFileUnavailableReason?
        if application.isSystemProtected {
            reason = .systemProtected
        } else if application.isRunning {
            reason = .runningApplication
        } else {
            reason = nil
        }

        return AppAssociatedFile(
            id: "application::\(application.bundleURL.path)",
            category: .applicationBundle,
            displayName: application.displayName,
            url: application.bundleURL,
            sizeBytes: application.bundleSizeBytes,
            ownershipConfidence: .high,
            riskLevel: reason == nil ? .low : .high,
            unavailableReason: reason
        )
    }

    private static func result(
        for item: AppAssociatedFile,
        reason: AssociatedFileUnavailableReason
    ) -> UninstallExecutionItemResult {
        switch reason {
        case .systemProtected:
            return UninstallExecutionItemResult(
                item: item,
                status: .systemProtected,
                reasonCode: reason.stableCode
            )
        case .runningApplication:
            return UninstallExecutionItemResult(
                item: item,
                status: .skipped,
                reasonCode: reason.stableCode
            )
        default:
            return UninstallExecutionItemResult(
                item: item,
                status: .insufficientPermission,
                reasonCode: reason.stableCode
            )
        }
    }
}

final class UninstallerCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }
}
