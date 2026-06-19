import Foundation

public protocol LoggingService: AnyObject, Sendable {
    func log(_ event: LogEvent)
}

public struct LogEvent: Sendable, Equatable {
    public let level: LogLevel
    public let category: LogCategory
    public let subsystem: String
    public let message: String
    public let stableCode: String?
    public let sanitizedContext: [String: String]

    public init(
        level: LogLevel,
        category: LogCategory,
        subsystem: String = LoggingSubsystem.omnipo,
        message: String,
        stableCode: String? = nil,
        sanitizedContext: [String: String] = [:]
    ) {
        self.level = level
        self.category = category
        self.subsystem = subsystem
        self.message = message
        self.stableCode = stableCode
        self.sanitizedContext = sanitizedContext
    }
}

public enum LogLevel: String, Sendable, Equatable, CaseIterable {
    case debug
    case info
    case notice
    case warning
    case error
}

public enum LogCategory: String, Sendable, Equatable, CaseIterable {
    case application
    case navigation
    case settings
    case logging
    case lifecycle
}

public enum LoggingSubsystem {
    public static let omnipo = "com.omnipo.app"
}

public enum PrivacyRedaction {
    public static let forbiddenKeys: Set<String> = [
        "clipboardContent",
        "clipboardRaw",
        "fileName",
        "userPath",
        "absolutePath",
        "wechatAccount",
        "wechatMessage",
        "wechatContact",
        "tccBundleId",
        "tccService",
        "url",
        "searchQuery"
    ]

    public static let forbiddenSubstrings: [String] = [
        "/Users/",
        "/private/var/",
        "file://"
    ]

    public static func sanitize(context: [String: String]) -> [String: String] {
        var cleaned: [String: String] = [:]
        for (key, value) in context {
            if forbiddenKeys.contains(key) {
                cleaned[key] = "<redacted>"
                continue
            }
            if forbiddenSubstrings.contains(where: { value.contains($0) }) {
                cleaned[key] = "<redacted-path>"
                continue
            }
            cleaned[key] = value
        }
        return cleaned
    }

    public static func sanitize(message: String) -> String {
        var sanitized = message
        for substring in forbiddenSubstrings {
            if sanitized.contains(substring) {
                sanitized = "<redacted>"
                break
            }
        }
        return sanitized
    }
}
