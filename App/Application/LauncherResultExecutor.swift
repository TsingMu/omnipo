import Foundation

/// 统一执行 `SearchResult`。
///
/// 根据 executionPayload 分派到命令执行器、应用启动器或文件打开器。
/// 所有执行失败映射为 `AppError`,不向日志写文件名或路径。
@MainActor
public protocol LauncherResultExecutor: AnyObject {
    func execute(_ result: SearchResult) async -> Result<Void, AppError>
}

@MainActor
public final class DefaultLauncherResultExecutor: LauncherResultExecutor {
    private let commandExecutor: LauncherCommandExecutor
    private let applicationLauncher: ApplicationLauncher
    private let fileLauncher: FileLauncher
    private let logger: any LoggingService

    public init(
        commandExecutor: LauncherCommandExecutor,
        applicationLauncher: ApplicationLauncher,
        fileLauncher: FileLauncher,
        logger: any LoggingService
    ) {
        self.commandExecutor = commandExecutor
        self.applicationLauncher = applicationLauncher
        self.fileLauncher = fileLauncher
        self.logger = logger
    }

    public func execute(_ result: SearchResult) async -> Result<Void, AppError> {
        switch result.executionPayload {
        case .launcherCommand(let id):
            if let command = LauncherCommand(rawValue: id) {
                commandExecutor.execute(command)
                return .success(())
            }
            logger.log(Self.logUnknownCommand())
            return .failure(.invalidArgument(name: "command"))
        case .applicationBundleIdentifier(let bundleId):
            return await applicationLauncher.launch(bundleIdentifier: bundleId)
        case .fileBookmark(let bookmark):
            return await fileLauncher.open(bookmark: bookmark)
        }
    }

    private static func logUnknownCommand() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "launcher.command.unknown",
            stableCode: "W_CMD_UNKNOWN",
            sanitizedContext: ["code": "W_CMD_UNKNOWN", "reason": "unknown-command"]
        )
    }
}
