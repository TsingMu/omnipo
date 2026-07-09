import Foundation

public struct InstalledApplication: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let bundleIdentifier: String?
    public let displayName: String
    public let localizedDisplayName: String?
    public let bundleURL: URL
    public let executableURL: URL?
    public let iconIdentifier: String?
    public let bundleSizeBytes: Int64
    public let source: ApplicationInstallSource
    public let isSystemProtected: Bool
    public let isRunning: Bool

    public init(
        id: String? = nil,
        bundleIdentifier: String?,
        displayName: String,
        localizedDisplayName: String? = nil,
        bundleURL: URL,
        executableURL: URL? = nil,
        iconIdentifier: String? = nil,
        bundleSizeBytes: Int64 = 0,
        source: ApplicationInstallSource,
        isSystemProtected: Bool = false,
        isRunning: Bool = false
    ) {
        let normalizedBundleIdentifier = bundleIdentifier?.nonEmptyUninstallerValue
        let normalizedDisplayName = displayName.nonEmptyUninstallerValue
            ?? localizedDisplayName?.nonEmptyUninstallerValue
            ?? normalizedBundleIdentifier
            ?? bundleURL.deletingPathExtension().lastPathComponent
        self.bundleIdentifier = normalizedBundleIdentifier
        self.displayName = normalizedDisplayName
        self.localizedDisplayName = localizedDisplayName?.nonEmptyUninstallerValue
        self.bundleURL = bundleURL
        self.executableURL = executableURL
        self.iconIdentifier = iconIdentifier?.nonEmptyUninstallerValue
        self.bundleSizeBytes = max(0, bundleSizeBytes)
        self.source = source
        self.isSystemProtected = isSystemProtected
        self.isRunning = isRunning
        self.id = id?.nonEmptyUninstallerValue ?? normalizedBundleIdentifier ?? bundleURL.path
    }
}

public struct InstalledApplicationScanIssue: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let rootURL: URL
    public let reason: AssociatedFileUnavailableReason

    public init(
        id: String? = nil,
        rootURL: URL,
        reason: AssociatedFileUnavailableReason
    ) {
        self.id = id?.nonEmptyUninstallerValue ?? rootURL.path
        self.rootURL = rootURL
        self.reason = reason
    }
}

public struct InstalledApplicationScanResult: Codable, Sendable, Hashable {
    public let applications: [InstalledApplication]
    public let issues: [InstalledApplicationScanIssue]

    public init(
        applications: [InstalledApplication],
        issues: [InstalledApplicationScanIssue] = []
    ) {
        self.applications = applications.sortedForUninstallerList()
        self.issues = issues.sorted { lhs, rhs in
            lhs.rootURL.path.localizedStandardCompare(rhs.rootURL.path) == .orderedAscending
        }
    }

    public var hasPartialFailures: Bool {
        !issues.isEmpty && !applications.isEmpty
    }

    public var isUnavailable: Bool {
        applications.isEmpty && !issues.isEmpty
    }
}

public enum ApplicationInstallSource: String, CaseIterable, Codable, Sendable, Hashable {
    case applications
    case userApplications
    case systemApplications
    case coreServices
    case other

    public var displayName: String {
        switch self {
        case .applications: return "/Applications"
        case .userApplications: return "~/Applications"
        case .systemApplications: return "/System/Applications"
        case .coreServices: return "CoreServices"
        case .other: return "其他位置"
        }
    }
}

public enum UninstallMode: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case removeApplicationOnly
    case removeApplicationAndAssociatedFiles

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .removeApplicationOnly:
            return "仅卸载应用"
        case .removeApplicationAndAssociatedFiles:
            return "完全删除"
        }
    }

    public var userDescription: String {
        switch self {
        case .removeApplicationOnly:
            return "只将应用本体移到废纸篓,保留设置、缓存和本地数据。"
        case .removeApplicationAndAssociatedFiles:
            return "将应用本体和选中的关联文件移到废纸篓,相关数据可能无法由 Omnipo 恢复。"
        }
    }
}

public enum AssociatedFileCategory: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case applicationBundle
    case cache
    case applicationSupport
    case preferences
    case logs
    case savedApplicationState
    case container
    case groupContainer
    case launchAgent
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applicationBundle: return "应用本体"
        case .cache: return "缓存"
        case .applicationSupport: return "支持文件"
        case .preferences: return "偏好设置"
        case .logs: return "日志"
        case .savedApplicationState: return "保存状态"
        case .container: return "应用容器"
        case .groupContainer: return "共享容器"
        case .launchAgent: return "后台启动项"
        case .other: return "其他关联文件"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .applicationBundle: return 0
        case .cache: return 10
        case .applicationSupport: return 20
        case .preferences: return 30
        case .logs: return 40
        case .savedApplicationState: return 50
        case .container: return 60
        case .groupContainer: return 70
        case .launchAgent: return 80
        case .other: return 90
        }
    }

    public var deletionConsequence: String {
        switch self {
        case .applicationBundle:
            return "应用将无法继续启动;如需再次使用需要重新安装。"
        case .cache:
            return "释放缓存占用空间;应用重装后可能重新生成,首次启动可能变慢。"
        case .applicationSupport:
            return "可能删除本地数据库、下载内容、插件或离线数据;清空废纸篓后可能无法恢复。"
        case .preferences:
            return "应用设置、窗口布局、最近项目和登录状态可能被重置。"
        case .logs:
            return "诊断日志会被删除;通常不影响功能,但会影响问题追踪。"
        case .savedApplicationState:
            return "窗口恢复状态和上次打开状态会丢失。"
        case .container:
            return "沙盒容器内的本地数据、缓存和设置可能被删除。"
        case .groupContainer:
            return "可能影响同一开发者的相关应用;默认不选中。"
        case .launchAgent:
            return "相关后台任务或自动启动能力可能停止。"
        case .other:
            return "影响取决于具体文件;归属不明确时默认不选中。"
        }
    }
}

public enum AssociatedFileRiskLevel: String, CaseIterable, Codable, Sendable, Hashable {
    case low
    case medium
    case high

    public var displayName: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "高风险"
        }
    }
}

public enum OwnershipConfidence: String, CaseIterable, Codable, Sendable, Hashable {
    case high
    case medium
    case low
    case unavailable

    public var displayName: String {
        switch self {
        case .high: return "高置信度"
        case .medium: return "中置信度"
        case .low: return "低置信度"
        case .unavailable: return "不可判断"
        }
    }
}

public enum AssociatedFileUnavailableReason: String, CaseIterable, Codable, Sendable, Hashable, Error {
    case notScanned
    case permissionLimited
    case tccRestricted
    case sandboxRestricted
    case fileSystemDenied
    case systemProtected
    case runningApplication
    case highSensitivity
    case ownershipUnclear
    case resourceUnavailable
    case unknown

    public var stableCode: String {
        switch self {
        case .notScanned: return "UNINSTALL_FILE_NOT_SCANNED"
        case .permissionLimited: return "UNINSTALL_PERMISSION_LIMITED"
        case .tccRestricted: return "UNINSTALL_TCC_RESTRICTED"
        case .sandboxRestricted: return "UNINSTALL_SANDBOX_RESTRICTED"
        case .fileSystemDenied: return "UNINSTALL_FILE_SYSTEM_DENIED"
        case .systemProtected: return "UNINSTALL_SYSTEM_PROTECTED"
        case .runningApplication: return "UNINSTALL_RUNNING_APPLICATION"
        case .highSensitivity: return "UNINSTALL_HIGH_SENSITIVITY"
        case .ownershipUnclear: return "UNINSTALL_OWNERSHIP_UNCLEAR"
        case .resourceUnavailable: return "UNINSTALL_RESOURCE_UNAVAILABLE"
        case .unknown: return "UNINSTALL_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .notScanned:
            return "尚未扫描该位置。"
        case .permissionLimited:
            return "当前缺少读取或删除该位置所需的用户授权。"
        case .tccRestricted:
            return "该位置受 macOS 隐私权限保护。"
        case .sandboxRestricted:
            return "当前沙箱能力无法访问该位置。"
        case .fileSystemDenied:
            return "文件系统拒绝访问该项目。"
        case .systemProtected:
            return "该项目受系统保护,Omnipo 不会删除。"
        case .runningApplication:
            return "应用正在运行,请退出后重试。"
        case .highSensitivity:
            return "该项目可能包含高敏数据,默认不删除。"
        case .ownershipUnclear:
            return "无法确认该项目只属于当前应用。"
        case .resourceUnavailable:
            return "该项目当前不可用。"
        case .unknown:
            return "当前无法判断该项目状态。"
        }
    }
}

public struct AppAssociatedFile: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let category: AssociatedFileCategory
    public let displayName: String
    public let url: URL
    public let sizeBytes: Int64
    public let ownershipConfidence: OwnershipConfidence
    public let riskLevel: AssociatedFileRiskLevel
    public let isDefaultSelected: Bool
    public let isUserSelectable: Bool
    public let unavailableReason: AssociatedFileUnavailableReason?

    public init(
        id: String? = nil,
        category: AssociatedFileCategory,
        displayName: String,
        url: URL,
        sizeBytes: Int64 = 0,
        ownershipConfidence: OwnershipConfidence,
        riskLevel: AssociatedFileRiskLevel,
        isDefaultSelected: Bool? = nil,
        isUserSelectable: Bool? = nil,
        unavailableReason: AssociatedFileUnavailableReason? = nil
    ) {
        self.id = id?.nonEmptyUninstallerValue ?? url.path
        self.category = category
        self.displayName = displayName.nonEmptyUninstallerValue ?? url.lastPathComponent
        self.url = url
        self.sizeBytes = max(0, sizeBytes)
        self.ownershipConfidence = ownershipConfidence
        self.riskLevel = riskLevel
        self.unavailableReason = unavailableReason
        self.isUserSelectable = isUserSelectable ?? (unavailableReason == nil)
        self.isDefaultSelected = isDefaultSelected ?? AppAssociatedFile.defaultSelection(
            category: category,
            ownershipConfidence: ownershipConfidence,
            riskLevel: riskLevel,
            isUserSelectable: self.isUserSelectable
        )
    }

    public static func defaultSelection(
        category: AssociatedFileCategory,
        ownershipConfidence: OwnershipConfidence,
        riskLevel: AssociatedFileRiskLevel,
        isUserSelectable: Bool
    ) -> Bool {
        guard isUserSelectable else { return false }
        if category == .applicationBundle { return true }
        guard riskLevel != .high else { return false }
        guard category != .groupContainer, category != .other else { return false }
        return ownershipConfidence == .high
    }
}

public struct AssociatedFileScanIssue: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let rootURL: URL
    public let category: AssociatedFileCategory
    public let reason: AssociatedFileUnavailableReason

    public init(
        id: String? = nil,
        rootURL: URL,
        category: AssociatedFileCategory,
        reason: AssociatedFileUnavailableReason
    ) {
        self.id = id?.nonEmptyUninstallerValue ?? "\(category.rawValue)::\(rootURL.path)"
        self.rootURL = rootURL
        self.category = category
        self.reason = reason
    }
}

public struct AssociatedFileScanResult: Codable, Sendable, Hashable {
    public let files: [AppAssociatedFile]
    public let issues: [AssociatedFileScanIssue]

    public init(
        files: [AppAssociatedFile],
        issues: [AssociatedFileScanIssue] = []
    ) {
        self.files = files.sortedForUninstallPreview()
        self.issues = issues.sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            return lhs.rootURL.path.localizedStandardCompare(rhs.rootURL.path) == .orderedAscending
        }
    }

    public var hasPartialFailures: Bool {
        !issues.isEmpty && !files.isEmpty
    }

    public var isUnavailable: Bool {
        files.isEmpty && !issues.isEmpty
    }
}

public struct AppUninstallPlan: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let application: InstalledApplication
    public let mode: UninstallMode
    public let items: [AppAssociatedFile]
    public let selectedItemIDs: Set<String>
    public let unavailableItems: [AppAssociatedFile]

    public init(
        id: UUID = UUID(),
        application: InstalledApplication,
        mode: UninstallMode,
        items: [AppAssociatedFile],
        selectedItemIDs: Set<String>? = nil
    ) {
        let sortedItems = items.sortedForUninstallPreview()
        self.id = id
        self.application = application
        self.mode = mode
        self.items = sortedItems
        self.selectedItemIDs = selectedItemIDs ?? Set(sortedItems.filter(\.isDefaultSelected).map(\.id))
        self.unavailableItems = sortedItems.filter { $0.unavailableReason != nil }
    }

    public var selectedItems: [AppAssociatedFile] {
        items.filter { selectedItemIDs.contains($0.id) && $0.isUserSelectable }
    }

    public var selectedTotalSizeBytes: Int64 {
        selectedItems.reduce(into: Int64(0)) { total, item in
            total += item.sizeBytes
        }
    }

    public var riskSummary: UninstallRiskSummary {
        UninstallRiskSummary(items: selectedItems)
    }

    public var groupedItems: [AssociatedFileCategory: [AppAssociatedFile]] {
        Dictionary(grouping: items, by: \.category)
    }

    public func selecting(itemIDs: Set<String>) -> AppUninstallPlan {
        AppUninstallPlan(
            id: id,
            application: application,
            mode: mode,
            items: items,
            selectedItemIDs: itemIDs.intersection(Set(items.filter(\.isUserSelectable).map(\.id)))
        )
    }
}

public struct UninstallRiskSummary: Codable, Sendable, Hashable {
    public let lowRiskCount: Int
    public let mediumRiskCount: Int
    public let highRiskCount: Int

    public init(items: [AppAssociatedFile]) {
        lowRiskCount = items.filter { $0.riskLevel == .low }.count
        mediumRiskCount = items.filter { $0.riskLevel == .medium }.count
        highRiskCount = items.filter { $0.riskLevel == .high }.count
    }
}

public enum UninstallExecutionItemStatus: String, CaseIterable, Codable, Sendable, Hashable {
    case succeeded
    case failed
    case skipped
    case cancelled
    case insufficientPermission
    case systemProtected

    public var isTerminalSuccess: Bool {
        self == .succeeded || self == .skipped
    }
}

public struct UninstallExecutionItemResult: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let item: AppAssociatedFile
    public let status: UninstallExecutionItemStatus
    public let reasonCode: String?

    public init(
        id: String? = nil,
        item: AppAssociatedFile,
        status: UninstallExecutionItemStatus,
        reasonCode: String? = nil
    ) {
        self.id = id?.nonEmptyUninstallerValue ?? item.id
        self.item = item
        self.status = status
        self.reasonCode = reasonCode?.nonEmptyUninstallerValue
    }
}

public struct UninstallExecutionResult: Codable, Sendable, Hashable {
    public let planID: UUID
    public let itemResults: [UninstallExecutionItemResult]
    public let completedAt: Date

    public init(
        planID: UUID,
        itemResults: [UninstallExecutionItemResult],
        completedAt: Date = Date()
    ) {
        self.planID = planID
        self.itemResults = itemResults
        self.completedAt = completedAt
    }

    public var succeededCount: Int {
        itemResults.filter { $0.status == .succeeded }.count
    }

    public var failedCount: Int {
        itemResults.filter {
            $0.status == .failed
                || $0.status == .insufficientPermission
                || $0.status == .systemProtected
        }.count
    }

    public var skippedCount: Int {
        itemResults.filter { $0.status == .skipped }.count
    }

    public var isPartialFailure: Bool {
        succeededCount > 0 && failedCount > 0
    }
}

private extension Array where Element == AppAssociatedFile {
    func sortedForUninstallPreview() -> [AppAssociatedFile] {
        sorted { lhs, rhs in
            if lhs.category.sortOrder != rhs.category.sortOrder {
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
            let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
        }
    }
}

private extension Array where Element == InstalledApplication {
    func sortedForUninstallerList() -> [InstalledApplication] {
        sorted { lhs, rhs in
            let nameOrder = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.bundleURL.path.localizedStandardCompare(rhs.bundleURL.path) == .orderedAscending
        }
    }
}

private extension String {
    var nonEmptyUninstallerValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
