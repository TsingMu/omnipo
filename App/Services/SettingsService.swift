import Foundation

public protocol SettingsService: AnyObject, Sendable {
    func readBool(forKey key: SettingsKey) -> Bool
    func readString(forKey key: SettingsKey) -> String?
    func readDouble(forKey key: SettingsKey) -> Double

    func write(_ value: Bool, forKey key: SettingsKey)
    func write(_ value: String?, forKey key: SettingsKey)
    func write(_ value: Double, forKey key: SettingsKey)

    func remove(forKey key: SettingsKey)
    func resetAll()
}

public struct SettingsKey: Sendable, Hashable {
    public let rawValue: String
    public let defaultValue: SettingsValue

    public init(_ rawValue: String, default defaultValue: SettingsValue) {
        self.rawValue = rawValue
        self.defaultValue = defaultValue
    }
}

public enum SettingsValue: Sendable, Hashable {
    case bool(Bool)
    case string(String)
    case double(Double)
}

public extension SettingsKey {
    static let launchDashboardAtStart = SettingsKey(
        "omnipo.settings.launchDashboardAtStart",
        default: .bool(true)
    )

    static let reopenLastDestination = SettingsKey(
        "omnipo.settings.reopenLastDestination",
        default: .bool(false)
    )

    static let preferredSidebarWidth = SettingsKey(
        "omnipo.settings.preferredSidebarWidth",
        default: .double(220)
    )

    static let lastOpenedDestinationKey = SettingsKey(
        "omnipo.settings.lastOpenedDestination",
        default: .string("dashboard")
    )
}

public extension SettingsService {
    func readValue(forKey key: SettingsKey) -> SettingsValue {
        switch key.defaultValue {
        case .bool:
            return .bool(readBool(forKey: key))
        case .string(let fallback):
            if let stored = readString(forKey: key) {
                return .string(stored)
            }
            return .string(fallback)
        case .double:
            return .double(readDouble(forKey: key))
        }
    }
}
