import AppKit
import Foundation

protocol PermissionApplicationResolving: Sendable {
    func identity(forClient client: String, clientType: Int, fallbackIndex: Int) -> PermissionApplicationIdentity
}

struct PermissionApplicationIdentity: Sendable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let iconIdentifier: String?
}

struct SystemPermissionApplicationResolver: PermissionApplicationResolving {
    func identity(forClient client: String, clientType: Int, fallbackIndex: Int) -> PermissionApplicationIdentity {
        let trimmedClient = client.trimmingCharacters(in: .whitespacesAndNewlines)
        if clientType == 0, trimmedClient.contains("/") == false {
            let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmedClient)
            let displayName = applicationURL
                .flatMap { Bundle(url: $0)?.displayName }
                ?? trimmedClient
            return PermissionApplicationIdentity(
                bundleIdentifier: trimmedClient,
                displayName: displayName,
                iconIdentifier: trimmedClient
            )
        }

        let applicationURL = URL(fileURLWithPath: trimmedClient)
        let bundle = Bundle(url: applicationURL)
        let displayName = bundle?.displayName ?? applicationURL.lastPathComponent
        return PermissionApplicationIdentity(
            bundleIdentifier: "local.path.client.\(fallbackIndex)",
            displayName: displayName.isEmpty ? "本地应用" : displayName,
            iconIdentifier: bundle?.bundleIdentifier?.nonEmptyValue
        )
    }
}

private extension Bundle {
    var displayName: String? {
        preferredChineseDisplayName
        ?? (localizedInfoDictionary?["CFBundleDisplayName"] as? String)?.nonEmptyValue
        ?? (localizedInfoDictionary?["CFBundleName"] as? String)?.nonEmptyValue
        ?? (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.nonEmptyValue
        ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)?.nonEmptyValue
    }

    var preferredChineseDisplayName: String? {
        guard let resourceURL else { return nil }
        for localization in ["zh-Hans", "zh-Hant", "zh_CN", "zh_TW", "zh"] {
            let stringsURL = resourceURL
                .appendingPathComponent("\(localization).lproj", isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            guard let dictionary = NSDictionary(contentsOf: stringsURL) as? [String: Any] else {
                continue
            }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = (dictionary[key] as? String)?.nonEmptyValue {
                    return value
                }
            }
        }
        return nil
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
