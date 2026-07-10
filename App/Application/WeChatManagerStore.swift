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

    private let service: any WeChatStorageService
    private var loadTask: Task<Void, Never>?
    private var loadTaskID: UUID?

    init(service: any WeChatStorageService) {
        self.service = service
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
}
