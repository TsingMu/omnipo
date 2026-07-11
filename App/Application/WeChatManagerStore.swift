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
    private(set) var selectedLargeFileIDs: Set<UUID> = []
    private(set) var ignoredLargeFileIDs: Set<UUID> = []

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
                reconcileLargeFileCandidates(with: scanResult)
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

    func isLargeFileSelected(_ id: UUID) -> Bool {
        selectedLargeFileIDs.contains(id)
    }

    func setLargeFileSelection(_ id: UUID, selected: Bool) {
        guard !ignoredLargeFileIDs.contains(id) else { return }
        if selected {
            selectedLargeFileIDs.insert(id)
        } else {
            selectedLargeFileIDs.remove(id)
        }
    }

    func setLargeFileSelection(_ ids: some Sequence<UUID>, selected: Bool) {
        let selectableIDs = Set(ids).subtracting(ignoredLargeFileIDs)
        if selected {
            selectedLargeFileIDs.formUnion(selectableIDs)
        } else {
            selectedLargeFileIDs.subtract(selectableIDs)
        }
    }

    func ignoreSelectedLargeFiles() {
        ignoredLargeFileIDs.formUnion(selectedLargeFileIDs)
        selectedLargeFileIDs.removeAll()
    }

    func restoreIgnoredLargeFile(_ id: UUID) {
        ignoredLargeFileIDs.remove(id)
    }

    func restoreAllIgnoredLargeFiles() {
        ignoredLargeFileIDs.removeAll()
    }

    func selectedLargeFileBytes(in result: WeChatStorageScanResult) -> Int {
        result.largeFiles.reduce(0) { total, file in
            total + (selectedLargeFileIDs.contains(file.id) ? file.sizeBytes : 0)
        }
    }

    private func reconcileLargeFileCandidates(with result: WeChatStorageScanResult) {
        let currentIDs = Set(result.largeFiles.map(\.id))
        selectedLargeFileIDs.formIntersection(currentIDs)
        ignoredLargeFileIDs.formIntersection(currentIDs)
        selectedLargeFileIDs.subtract(ignoredLargeFileIDs)
    }
}
