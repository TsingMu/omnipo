import Foundation

struct TCCPermissionCategoryProvider: PermissionCategoryProvider {
    let category: PermissionCategory
    let snapshotProvider: any TCCSnapshotProviding
    let applicationResolver: any PermissionApplicationResolving

    func loadGrants() async -> PermissionProviderResult {
        let service = category.tccServiceName
        guard service.isEmpty == false else {
            return PermissionProviderResult(
                category: category,
                unavailableReason: .unsupportedOnCurrentSystem
            )
        }

        switch snapshotProvider.snapshot(for: service) {
        case .success(let entries):
            let grants = entries.enumerated().map { index, entry in
                let identity = applicationResolver.identity(
                    forClient: entry.client,
                    clientType: entry.clientType,
                    fallbackIndex: index
                )
                return AppPermissionGrant(
                    id: "\(category.rawValue)::\(identity.bundleIdentifier)::\(index)",
                    bundleIdentifier: identity.bundleIdentifier,
                    displayName: identity.displayName,
                    category: category,
                    status: entry.status,
                    source: "tcc",
                    lastUpdatedAt: entry.lastUpdatedAt,
                    iconIdentifier: identity.iconIdentifier
                )
            }
            return PermissionProviderResult(category: category, grants: grants)
        case .failure(let reason):
            return PermissionProviderResult(
                category: category,
                unavailableReason: reason
            )
        }
    }
}

private extension PermissionCategory {
    var tccServiceName: String {
        switch self {
        case .camera: return "kTCCServiceCamera"
        case .microphone: return "kTCCServiceMicrophone"
        case .photos: return "kTCCServicePhotos"
        case .contacts: return "kTCCServiceAddressBook"
        case .calendar: return "kTCCServiceCalendar"
        case .reminders: return "kTCCServiceReminders"
        case .accessibility: return "kTCCServiceAccessibility"
        case .fullDiskAccess: return "kTCCServiceSystemPolicyAllFiles"
        }
    }
}
