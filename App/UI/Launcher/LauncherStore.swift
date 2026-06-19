import Foundation
import Observation

/// Launcher 面板查询、结果与选择的唯一事实来源。
///
/// 所有可变状态在 MainActor;查询任务在后台异步,但写入结果回到 MainActor。
/// 查询变化或面板关闭时取消旧 task,清理瞬态。
@MainActor
@Observable
public final class LauncherStore {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case showingResults
        case empty
        case partialFailure(String)
    }

    public private(set) var query: String = ""
    public private(set) var results: [SearchResult] = []
    public private(set) var selection: SearchResult.ID?
    public private(set) var state: State = .idle
    public private(set) var lastGeneration: UInt64 = 0
    /// 执行结果失败时填入,UI 在底部展示;下次输入或关闭时清空。
    public private(set) var transientError: AppError?

    private let service: any SearchService
    private var currentTask: Task<Void, Never>?
    private var inflightGeneration: UInt64 = 0

    public init(service: any SearchService) {
        self.service = service
    }

    public func updateQuery(_ newQuery: String) {
        currentTask?.cancel()
        query = newQuery
        state = .loading
        transientError = nil

        inflightGeneration &+= 1
        let capturedGeneration = inflightGeneration

        let task = Task { [weak self] in
            guard let self else { return }
            let batch = await self.service.search(query: newQuery)
            if Task.isCancelled { return }
            await MainActor.run {
                self.applyBatch(batch, expectedGeneration: capturedGeneration)
            }
        }
        currentTask = task
    }

    public func setTransientError(_ error: AppError) {
        transientError = error
    }

    public func clearTransientError() {
        transientError = nil
    }

    public func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        inflightGeneration &+= 1
        query = ""
        results = []
        selection = nil
        state = .idle
        transientError = nil
    }

    public func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let currentIndex = results.firstIndex { $0.id == selection } ?? -1
        let nextIndex: Int
        if delta > 0 {
            nextIndex = min(results.count - 1, currentIndex + delta)
        } else if delta < 0 {
            nextIndex = max(0, currentIndex + delta)
        } else {
            return
        }
        if nextIndex == currentIndex { return }
        selection = results[nextIndex].id
    }

    public func selectFirst() {
        selection = results.first?.id
    }

    public func currentResult() -> SearchResult? {
        guard let selection else { return nil }
        return results.first { $0.id == selection }
    }

    private func applyBatch(_ batch: SearchBatch, expectedGeneration: UInt64) {
        guard expectedGeneration == inflightGeneration else {
            return
        }
        lastGeneration = batch.generation
        results = batch.results

        if let current = selection, results.contains(where: { $0.id == current }) {
            // 保持当前选择
        } else {
            selection = results.first?.id
        }

        if results.isEmpty {
            if batch.failures.isEmpty {
                state = .empty
            } else {
                state = .partialFailure(Self.describe(failures: batch.failures))
            }
        } else if !batch.failures.isEmpty {
            state = .partialFailure(Self.describe(failures: batch.failures))
        } else {
            state = .showingResults
        }
    }

    private static func describe(failures: [SearchProviderFailure]) -> String {
        failures
            .map { $0.userDescription ?? $0.stableCode }
            .joined(separator: ", ")
    }
}
