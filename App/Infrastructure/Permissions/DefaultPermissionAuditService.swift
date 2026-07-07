import Foundation

public final class DefaultPermissionAuditService: PermissionAuditService, @unchecked Sendable {
    private let aggregator: PermissionAuditAggregator
    private let logger: any LoggingService

    init(
        aggregator: PermissionAuditAggregator,
        logger: any LoggingService
    ) {
        self.aggregator = aggregator
        self.logger = logger
    }

    public convenience init(logger: any LoggingService) {
        let snapshotProvider = TCCReadOnlySnapshotProvider()
        self.init(
            aggregator: PermissionAuditAggregator(
                providers: PermissionCategory.allCases.map { category in
                    TCCPermissionCategoryProvider(
                        category: category,
                        snapshotProvider: snapshotProvider,
                        applicationResolver: SystemPermissionApplicationResolver()
                    )
                }
            ),
            logger: logger
        )
    }

    public func auditPermissions(matching query: PermissionAuditQuery) async -> Result<PermissionAuditResult, AppError> {
        logger.log(.permissionAuditStarted(category: query.category))
        let result = await aggregator.audit(matching: query)
        logger.log(.permissionAuditFinished(result: result, category: query.category))
        return .success(result)
    }
}

private extension LogEvent {
    static func permissionAuditStarted(category: PermissionCategory?) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "permission_audit.started",
            stableCode: "I_PERMISSION_AUDIT_STARTED",
            sanitizedContext: [
                "category": category?.rawValue ?? "all"
            ]
        )
    }

    static func permissionAuditFinished(
        result: PermissionAuditResult,
        category: PermissionCategory?
    ) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "permission_audit.finished",
            stableCode: "I_PERMISSION_AUDIT_FINISHED",
            sanitizedContext: [
                "category": category?.rawValue ?? "all",
                "stage": result.isEmpty ? "empty" : "loaded",
                "reason": result.unavailableCategories.isEmpty ? "none" : "partial_unavailable"
            ]
        )
    }
}
