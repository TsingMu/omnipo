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
            return PermissionApplicationIdentity(
                bundleIdentifier: trimmedClient,
                displayName: ApplicationDisplayNameResolver.displayName(forBundleIdentifier: trimmedClient),
                iconIdentifier: trimmedClient
            )
        }

        let applicationURL = URL(fileURLWithPath: trimmedClient)
        let bundle = Bundle(url: applicationURL)
        let displayName = bundle?.omnipoDisplayName ?? applicationURL.lastPathComponent
        return PermissionApplicationIdentity(
            bundleIdentifier: "local.path.client.\(fallbackIndex)",
            displayName: displayName.isEmpty ? "本地应用" : displayName,
            iconIdentifier: bundle?.bundleIdentifier?.nonEmptyValue
        )
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
