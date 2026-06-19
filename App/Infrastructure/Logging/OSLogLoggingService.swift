import Foundation
import OSLog

/// OSLog 实现的 LoggingService。
///
/// 隐私边界:`message` 与 `stableCode` 视为稳定字符串,以 `.public` 输出;
/// `context` 的值视为动态,以 `.private` 输出(Console.app 显示为 `<private>`)。
/// 即便字符串脱敏漏过,OSLog 隐私级别仍保证动态值不会原样落盘到统一日志。
public final class OSLogLoggingService: LoggingService {
    private let subsystem: String
    private let loggers: OSLogLoggerStore

    public init(subsystem: String = LoggingSubsystem.omnipo) {
        self.subsystem = subsystem
        self.loggers = OSLogLoggerStore(subsystem: subsystem)
    }

    public func log(_ event: LogEvent) {
        let cleanedMessage = PrivacyRedaction.sanitize(message: event.message)
        let cleanedContext = PrivacyRedaction.sanitize(context: event.sanitizedContext)
        let logger = loggers.logger(for: event.category)
        let contextString = Self.render(context: cleanedContext)
        let osLogType = Self.osLogType(for: event.level)

        if let code = event.stableCode {
            logger.log(
                level: osLogType,
                "\(code, privacy: .public) \(cleanedMessage, privacy: .public) \(contextString, privacy: .private)"
            )
        } else {
            logger.log(
                level: osLogType,
                "\(cleanedMessage, privacy: .public) \(contextString, privacy: .private)"
            )
        }
    }

    private static func render(context: [String: String]) -> String {
        guard !context.isEmpty else { return "" }
        let pairs = context
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "{\(pairs)}"
    }

    private static func osLogType(for level: LogLevel) -> OSLogType {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .default
        case .error: return .error
        }
    }
}

private final class OSLogLoggerStore: @unchecked Sendable {
    private let subsystem: String
    private let lock = NSLock()
    private var cache: [String: Logger] = [:]

    init(subsystem: String) {
        self.subsystem = subsystem
    }

    func logger(for category: LogCategory) -> Logger {
        let key = category.rawValue
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            return cached
        }
        let logger = Logger(subsystem: subsystem, category: key)
        cache[key] = logger
        return logger
    }
}
