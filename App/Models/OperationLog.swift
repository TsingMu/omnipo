import Foundation

public struct OperationLog: Sendable, Equatable, Identifiable {
    public enum Level: String, Sendable, Equatable {
        case debug
        case info
        case notice
        case warning
        case error
    }

    public enum Category: String, Sendable, Equatable {
        case application
        case navigation
        case settings
        case logging
        case lifecycle
    }

    public let id: UUID
    public let timestamp: Date
    public let level: Level
    public let category: Category
    public let message: String
    public let stableCode: String?
    public let sanitizedContext: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: Level,
        category: Category,
        message: String,
        stableCode: String? = nil,
        sanitizedContext: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.stableCode = stableCode
        self.sanitizedContext = sanitizedContext
    }
}
