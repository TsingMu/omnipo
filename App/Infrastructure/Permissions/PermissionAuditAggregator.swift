import Foundation

struct PermissionProviderResult: Sendable, Equatable {
    var category: PermissionCategory
    var grants: [AppPermissionGrant]
    var unavailableReason: PermissionUnavailableReason?

    init(
        category: PermissionCategory,
        grants: [AppPermissionGrant] = [],
        unavailableReason: PermissionUnavailableReason? = nil
    ) {
        self.category = category
        self.grants = grants
        self.unavailableReason = unavailableReason
    }
}

protocol PermissionCategoryProvider: Sendable {
    var category: PermissionCategory { get }
    func loadGrants() async -> PermissionProviderResult
}

struct PermissionAuditAggregator: Sendable {
    let providers: [any PermissionCategoryProvider]

    init(providers: [any PermissionCategoryProvider]) {
        self.providers = providers.sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    func audit(matching query: PermissionAuditQuery) async -> PermissionAuditResult {
        var grants: [AppPermissionGrant] = []
        var unavailableCategories: [PermissionCategory: PermissionUnavailableReason] = [:]

        for provider in providers {
            let result = await provider.loadGrants()
            grants.append(contentsOf: result.grants)
            if let reason = result.unavailableReason {
                unavailableCategories[result.category] = reason
            }
        }

        let normalizedSearchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredGrants = grants.filter { grant in
            if let category = query.category, grant.category != category {
                return false
            }
            guard normalizedSearchText.isEmpty == false else {
                return true
            }
            return grant.displayName.localizedCaseInsensitiveContains(normalizedSearchText)
                || grant.bundleIdentifier.localizedCaseInsensitiveContains(normalizedSearchText)
        }
        let filteredUnavailableCategories = unavailableCategories.filter { category, _ in
            query.category == nil || query.category == category
        }

        return PermissionAuditResult(
            grants: filteredGrants,
            unavailableCategories: filteredUnavailableCategories
        )
    }
}
