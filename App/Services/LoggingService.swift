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

/// 隐私脱敏的最后一道字符串防线。
///
/// 设计意图:OSLog 的 `.private` 隐私级别是主要边界(动态值在 Console.app 显示为 `<private>`)。
/// 这里的字符串扫描作为兜底,捕获显式标记为允许的键之外的潜在敏感模式。
public enum PrivacyRedaction {

    /// 任何包含这些值的字段都被视为可能携带用户路径。
    public static let forbiddenPathSubstrings: [String] = [
        "/Users/",
        "/private/var/",
        "/private/tmp/",
        "/Volumes/",
        "/tmp/",
        "/var/tmp/",
        "/dev/",
        "/.Trash/",
        "~/",
        "${HOME}",
        "file://"
    ]

    /// 即便 key 名不在白名单,以下值仍然不能原样输出。
    public static let forbiddenValueSubstrings: [String] = forbiddenPathSubstrings

    /// 已知的禁止键(语义上明确涉及隐私)。
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
        "searchQuery",
        "secret",
        "token",
        "password"
    ]

    /// Context 允许的键白名单。未列出的 key 一律脱敏。
    public static let allowedContextKeys: Set<String> = [
        "destination",
        "stage",
        "key",
        "code",
        "systemCode",
        "reason",
        "category",
        "level",
        "stateDetail",
        "argumentName",
        "resource",
        "corruptionDetail",
        "formatDetail",
        "unknownCode"
    ]

    /// 看起来像文件名的启发式(包含点号且末尾是常见扩展名)。
    public static let suspiciousFileExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "zip", "tar", "gz", "rar", "7z",
        "jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp",
        "mp4", "mov", "mp3", "m4a", "wav",
        "txt", "rtf", "csv", "json", "plist",
        "db", "sqlite", "key", "pem", "crt"
    ]

    /// 路径或文件名形态的正则(快速扫描)。
    public static func looksLikePath(_ value: String) -> Bool {
        if forbiddenPathSubstrings.contains(where: { value.contains($0) }) {
            return true
        }
        if value.hasPrefix("/") {
            return true
        }
        let trimmed = value.lowercased()
        let dotIndex = trimmed.lastIndex(of: ".")
        if let dotIndex, dotIndex < trimmed.endIndex {
            let ext = String(trimmed[trimmed.index(after: dotIndex)...])
            if suspiciousFileExtensions.contains(ext) {
                return true
            }
        }
        return false
    }

    public static func sanitize(context: [String: String]) -> [String: String] {
        var cleaned: [String: String] = [:]
        for (key, value) in context {
            if forbiddenKeys.contains(key) {
                cleaned[key] = "<redacted>"
                continue
            }
            if !allowedContextKeys.contains(key) {
                cleaned[key] = "<redacted>"
                continue
            }
            if value.contains(where: { $0.isWhitespace == false }) == false {
                cleaned[key] = value
                continue
            }
            if looksLikePath(value) || forbiddenValueSubstrings.contains(where: { value.contains($0) }) {
                cleaned[key] = "<redacted-path>"
                continue
            }
            cleaned[key] = value
        }
        return cleaned
    }

    public static func sanitize(message: String) -> String {
        if forbiddenPathSubstrings.contains(where: { message.contains($0) }) {
            return "<redacted>"
        }
        if looksLikePath(message) {
            return "<redacted>"
        }
        return message
    }
}
