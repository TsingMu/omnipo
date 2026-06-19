import Foundation
import AppKit

/// 文件打开执行器。
///
/// 通过 `NSWorkspace.shared.open` 打开文件;失败映射为 `AppError.resourceUnavailable`,
/// 日志只记录稳定代码,不含文件路径。
@MainActor
public final class FileLauncher {
    private let logger: any LoggingService

    public init(logger: any LoggingService) {
        self.logger = logger
    }

    public func open(bookmark: Data) async -> Result<Void, AppError> {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                logger.log(Self.logStale())
                return .failure(.resourceUnavailable(reason: "stale-bookmark"))
            }
            let opened = NSWorkspace.shared.open(url)
            if !opened {
                logger.log(Self.logOpenFailed())
                return .failure(.resourceUnavailable(reason: "system-refused"))
            }
            return .success(())
        } catch {
            logger.log(Self.logResolveFailed())
            return .failure(.resourceUnavailable(reason: "bookmark-unresolvable"))
        }
    }

    private static func logStale() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.file.stale",
            stableCode: "W_FILE_STALE",
            sanitizedContext: ["code": "W_FILE_STALE", "reason": "stale-bookmark"]
        )
    }

    private static func logOpenFailed() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.file.openFailed",
            stableCode: "W_FILE_OPEN",
            sanitizedContext: ["code": "W_FILE_OPEN", "reason": "system-refused"]
        )
    }

    private static func logResolveFailed() -> LogEvent {
        LogEvent(
            level: .error,
            category: .application,
            message: "launcher.file.resolveFailed",
            stableCode: "E_FILE_RESOLVE",
            sanitizedContext: ["code": "E_FILE_RESOLVE", "reason": "bookmark-unresolvable"]
        )
    }
}
