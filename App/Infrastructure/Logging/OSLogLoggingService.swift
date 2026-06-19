import Foundation
import OSLog

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
        let formatted = Self.format(message: cleanedMessage, context: cleanedContext, code: event.stableCode)
        switch event.level {
        case .debug:
            logger.debug("\(formatted, privacy: .public)")
        case .info:
            logger.info("\(formatted, privacy: .public)")
        case .notice:
            logger.notice("\(formatted, privacy: .public)")
        case .warning:
            logger.warning("\(formatted, privacy: .public)")
        case .error:
            logger.error("\(formatted, privacy: .public)")
        }
    }

    private static func format(
        message: String,
        context: [String: String],
        code: String?
    ) -> String {
        var parts: [String] = []
        if let code {
            parts.append("[\(code)]")
        }
        parts.append(message)
        if !context.isEmpty {
            let rendered = context
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ",")
            parts.append("{\(rendered)}")
        }
        return parts.joined(separator: " ")
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
