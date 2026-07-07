import Foundation
import Observation

@Observable
@MainActor
final class PermissionAuditStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(PermissionAuditResult)
        case failed(AppError)
    }

    var query = PermissionAuditQuery()
    var state: LoadState = .idle
    var isPermissionRequestPresented = false

    private let service: any PermissionAuditService
    private var loadTask: Task<Void, Never>?
    private var loadTaskID: UUID?

    init(service: any PermissionAuditService) {
        self.service = service
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        loadTask?.cancel()
        let query = query
        state = .loading
        let taskID = UUID()
        let task = Task { @MainActor in
            let result = await service.auditPermissions(matching: query)
            guard Task.isCancelled == false else { return }
            switch result {
            case .success(let auditResult):
                state = .loaded(auditResult)
                isPermissionRequestPresented = auditResult.requiresFullDiskAccessRequest
            case .failure(let error):
                state = .failed(error)
                isPermissionRequestPresented = false
            }
        }
        loadTaskID = taskID
        loadTask = task
        await task.value
        if loadTaskID == taskID {
            loadTask = nil
            loadTaskID = nil
        }
    }

    func dismissPermissionRequest() {
        isPermissionRequestPresented = false
    }
}

extension PermissionAuditResult {
    var requiresFullDiskAccessRequest: Bool {
        unavailableCategories.values.contains(.databaseUnreadable)
    }
}
