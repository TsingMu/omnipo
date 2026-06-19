import Foundation
import AppKit

/// 应用启动执行器。
///
/// 通过 `NSWorkspace.shared.openApplication` 启动应用;失败映射为安全 `AppError`,
/// 不向日志写入应用路径。
@MainActor
public final class ApplicationLauncher {
    private let logger: any LoggingService
    private let resourceCache: ApplicationResourceCache

    public init(
        logger: any LoggingService,
        resourceCache: ApplicationResourceCache
    ) {
        self.logger = logger
        self.resourceCache = resourceCache
    }

    public func launch(bundleIdentifier: String) async -> Result<Void, AppError> {
        guard let url = resourceCache.applicationURL(for: bundleIdentifier) else {
            logger.log(Self.logMissing())
            return .failure(.resourceUnavailable(reason: "application-missing"))
        }
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .success(())
        } catch {
            logger.log(Self.logLaunchFailed())
            return .failure(.systemFailure(code: "E_LAUNCH"))
        }
    }

    private static func logMissing() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.application.missing",
            stableCode: "W_APP_MISSING",
            sanitizedContext: ["code": "W_APP_MISSING", "reason": "application-missing"]
        )
    }

    private static func logLaunchFailed() -> LogEvent {
        LogEvent(
            level: .error,
            category: .application,
            message: "launcher.application.failed",
            stableCode: "E_LAUNCH",
            sanitizedContext: ["code": "E_LAUNCH", "reason": "launch-failed"]
        )
    }
}
