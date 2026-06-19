import Foundation

public final class UserDefaultsSettingsService: SettingsService, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public static func testing(suiteName: String) -> UserDefaultsSettingsService {
        UserDefaults().removePersistentDomain(forName: suiteName)
        let suite = UserDefaults(suiteName: suiteName) ?? .standard
        return UserDefaultsSettingsService(defaults: suite)
    }

    public func readBool(forKey key: SettingsKey) -> Bool {
        if defaults.object(forKey: key.rawValue) == nil {
            if case .bool(let fallback) = key.defaultValue {
                return fallback
            }
            return false
        }
        return defaults.bool(forKey: key.rawValue)
    }

    public func readString(forKey key: SettingsKey) -> String? {
        if let value = defaults.string(forKey: key.rawValue) {
            return value
        }
        if case .string(let fallback) = key.defaultValue {
            return fallback
        }
        return nil
    }

    public func readDouble(forKey key: SettingsKey) -> Double {
        if defaults.object(forKey: key.rawValue) == nil {
            if case .double(let fallback) = key.defaultValue {
                return fallback
            }
            return 0
        }
        return defaults.double(forKey: key.rawValue)
    }

    public func write(_ value: Bool, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    public func write(_ value: String?, forKey key: SettingsKey) {
        guard let value else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(value, forKey: key.rawValue)
    }

    public func write(_ value: Double, forKey key: SettingsKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    public func remove(forKey key: SettingsKey) {
        defaults.removeObject(forKey: key.rawValue)
    }

    public func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("omnipo.settings.") {
            defaults.removeObject(forKey: key)
        }
    }
}
