import Foundation
import Observation

@Observable
@MainActor
final class WeChatManagerStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(WeChatStorageScanResult)
        case failed(AppError)
    }

    private(set) var state: LoadState = .idle
    private(set) var conversationAliases: [String: String] = [:]

    private let service: any WeChatStorageService
    private let authorizationManager: WeChatStorageAuthorizationManager?
    private var loadTask: Task<Void, Never>?
    private var loadTaskID: UUID?

    init(
        service: any WeChatStorageService,
        authorizationManager: WeChatStorageAuthorizationManager? = nil
    ) {
        self.service = service
        self.authorizationManager = authorizationManager
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await refresh()
    }

    func refresh() async {
        loadTask?.cancel()
        state = .loading
        let taskID = UUID()
        let task = Task { @MainActor in
            let result = await service.refresh()
            guard Task.isCancelled == false else { return }
            switch result {
            case .success(let scanResult):
                state = .loaded(scanResult)
            case .failure(let error):
                state = .failed(error)
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

    func cancel() async {
        await service.cancel()
        await loadTask?.value
    }

    func selectUserRoots() async {
        guard let authorizationManager,
              await authorizationManager.selectNewRoots() else { return }
        await refresh()
    }

    var sensitiveNamesEnabled: Bool {
        authorizationManager?.sensitiveNamesEnabled ?? false
    }

    func enableSensitiveNames() async {
        guard let authorizationManager,
              authorizationManager.requestSensitiveNamesAccess() else { return }
        await refresh()
    }

    func disableSensitiveNames() async {
        authorizationManager?.revokeSensitiveNamesAccess()
        conversationAliases.removeAll()
        await refresh()
    }

    func setConversationAlias(_ name: String, for conversationID: String) {
        guard sensitiveNamesEnabled else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            conversationAliases.removeValue(forKey: conversationID)
        } else {
            conversationAliases[conversationID] = String(trimmed.prefix(80))
        }
    }
}
