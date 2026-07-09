import Foundation

public struct UninstallerQuery: Sendable, Hashable {
    public var searchText: String
    public var includeSystemApplications: Bool

    public init(searchText: String = "", includeSystemApplications: Bool = true) {
        self.searchText = searchText
        self.includeSystemApplications = includeSystemApplications
    }
}

public protocol UninstallerService: AnyObject, Sendable {
    func installedApplications(matching query: UninstallerQuery) async -> Result<[InstalledApplication], AppError>
    func buildPlan(for application: InstalledApplication, mode: UninstallMode) async -> Result<AppUninstallPlan, AppError>
    func execute(plan: AppUninstallPlan) async -> Result<UninstallExecutionResult, AppError>
    func cancel() async
}

public enum DeletionExecutorKind: String, CaseIterable, Codable, Sendable, Hashable {
    case finderAutomation
    case sandboxTrash

    public var displayName: String {
        switch self {
        case .finderAutomation: return "Finder 自动化"
        case .sandboxTrash: return "授权目录废纸篓"
        }
    }
}

public protocol DeletionExecutor: AnyObject, Sendable {
    var kind: DeletionExecutorKind { get }
    func canDelete(_ item: AppAssociatedFile) async -> Bool
    func delete(_ items: [AppAssociatedFile]) async -> [UninstallExecutionItemResult]
    func cancel() async
}
