import AppKit
import Foundation

enum ApplicationDisplayNameResolver {
    static func displayName(forBundleIdentifier bundleIdentifier: String) -> String {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return bundleIdentifier
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
            .flatMap { Bundle(url: $0)?.omnipoDisplayName }
            ?? trimmed
    }
}

extension Bundle {
    var omnipoDisplayName: String? {
        preferredChineseDisplayName
        ?? (localizedInfoDictionary?["CFBundleDisplayName"] as? String)?.omnipoNonEmptyValue
        ?? (localizedInfoDictionary?["CFBundleName"] as? String)?.omnipoNonEmptyValue
        ?? (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.omnipoNonEmptyValue
        ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)?.omnipoNonEmptyValue
    }

    private var preferredChineseDisplayName: String? {
        guard let resourceURL else { return nil }
        for localization in ["zh-Hans", "zh-Hant", "zh_CN", "zh_TW", "zh"] {
            let stringsURL = resourceURL
                .appendingPathComponent("\(localization).lproj", isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            guard let dictionary = NSDictionary(contentsOf: stringsURL) as? [String: Any] else {
                continue
            }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = (dictionary[key] as? String)?.omnipoNonEmptyValue {
                    return value
                }
            }
        }
        return nil
    }
}

extension String {
    var omnipoNonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
