import Foundation
import os

@MainActor
protocol SpotlightMetadataQuery: AnyObject {
    var predicate: NSPredicate? { get set }
    var searchScopes: [Any] { get set }
    var sortDescriptors: [NSSortDescriptor] { get set }
    var resultCount: Int { get }

    func result(at index: Int) -> Any
    func start() -> Bool
    func stop()
}

extension NSMetadataQuery: SpotlightMetadataQuery {}

/// 用 `NSMetadataQuery` 实现 Spotlight 文件搜索后端。
///
/// 查询对象与通知生命周期限制在 MainActor。任务取消会显式调用 `stop()`；
/// 完成、超时和取消共享同一个幂等恢复出口，continuation 最多完成一次。
public final class SpotlightFileSearchBackend: FileSearchBackend {
    typealias QueryFactory = @MainActor @Sendable () -> any SpotlightMetadataQuery

    private let logger: any LoggingService
    private let timeout: TimeInterval
    private let resultLimit: Int
    private let queryFactory: QueryFactory

    public init(
        logger: any LoggingService,
        timeout: TimeInterval = 2.0,
        resultLimit: Int = 100
    ) {
        self.logger = logger
        self.timeout = timeout
        self.resultLimit = resultLimit
        self.queryFactory = { NSMetadataQuery() }
    }

    init(
        logger: any LoggingService,
        timeout: TimeInterval,
        resultLimit: Int,
        queryFactory: @escaping QueryFactory
    ) {
        self.logger = logger
        self.timeout = timeout
        self.resultLimit = resultLimit
        self.queryFactory = queryFactory
    }

    public func search(query: String) async -> FileSearchBackendResult {
        let escaped = NSPredicate.escape(query: query)
        let cancellation = SpotlightCancellationBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor [logger, queryFactory, resultLimit, timeout] in
                    let metadataQuery = queryFactory()
                    metadataQuery.predicate = NSPredicate(
                        format: "(kMDItemDisplayName LIKE[cd] %@) OR (kMDItemFSName LIKE[cd] %@)",
                        "*\(escaped)*",
                        "*\(escaped)*"
                    )
                    metadataQuery.searchScopes = [NSMetadataQueryUserHomeScope]
                    metadataQuery.sortDescriptors = [
                        NSSortDescriptor(key: "kMDItemFSContentChangeDate", ascending: false)
                    ]

                    let coordinator = SpotlightCoordinator(
                        query: metadataQuery,
                        resultLimit: resultLimit,
                        timeout: timeout,
                        logger: logger
                    ) { result in
                        cancellation.clear()
                        continuation.resume(returning: result)
                    }
                    let shouldStart = cancellation.register {
                        Task { @MainActor in
                            coordinator.cancel()
                        }
                    }
                    if shouldStart {
                        coordinator.start()
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

private final class SpotlightCancellationBox: @unchecked Sendable {
    private struct State {
        var isCancelled = false
        var action: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    /// 返回 false 表示取消先于 coordinator 注册发生；此时立即执行取消动作。
    func register(_ action: @escaping @Sendable () -> Void) -> Bool {
        let shouldStart = state.withLock { state -> Bool in
            guard !state.isCancelled else { return false }
            state.action = action
            return true
        }
        if !shouldStart {
            action()
        }
        return shouldStart
    }

    func cancel() {
        let action = state.withLock { state -> (@Sendable () -> Void)? in
            state.isCancelled = true
            return state.action
        }
        action?()
    }

    func clear() {
        state.withLock { state in
            state.action = nil
        }
    }
}

@MainActor
private final class SpotlightCoordinator {
    private let query: any SpotlightMetadataQuery
    private let resultLimit: Int
    private let timeout: TimeInterval
    private let logger: any LoggingService
    private let completion: (FileSearchBackendResult) -> Void

    private var finishedObserver: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didResume = false

    init(
        query: any SpotlightMetadataQuery,
        resultLimit: Int,
        timeout: TimeInterval,
        logger: any LoggingService,
        completion: @escaping (FileSearchBackendResult) -> Void
    ) {
        self.query = query
        self.resultLimit = resultLimit
        self.timeout = timeout
        self.logger = logger
        self.completion = completion
    }

    func start() {
        guard !didResume else { return }
        finishedObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleFinish()
            }
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.handleTimeout()
            }
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        _ = query.start()
    }

    func cancel() {
        guard !didResume else { return }
        query.stop()
        resume(.unavailable(reason: "cancelled"))
    }

    private func handleFinish() {
        guard !didResume else { return }
        let entries = collectEntries()
        query.stop()
        resume(.success(entries))
    }

    private func handleTimeout() {
        guard !didResume else { return }
        query.stop()
        logger.log(Self.logTimeout())
        resume(.unavailable(reason: "timeout"))
    }

    private func collectEntries() -> [FileEntry] {
        var entries: [FileEntry] = []
        let upper = min(query.resultCount, resultLimit)
        for index in 0..<upper {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: "kMDItemPath") as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)
            guard let bookmark = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { continue }
            let displayName = (item.value(forAttribute: "kMDItemDisplayName") as? String) ?? url.lastPathComponent
            let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
            entries.append(FileEntry(displayName: displayName, bookmark: bookmark, fileExtension: ext))
        }
        return entries
    }

    private func resume(_ result: FileSearchBackendResult) {
        guard !didResume else { return }
        didResume = true
        cleanup()
        completion(result)
    }

    private func cleanup() {
        if let observer = finishedObserver {
            NotificationCenter.default.removeObserver(observer)
            finishedObserver = nil
        }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private static func logTimeout() -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "launcher.file.timeout",
            stableCode: "I_FILE_TIMEOUT",
            sanitizedContext: ["code": "I_FILE_TIMEOUT", "reason": "spotlight-timeout"]
        )
    }
}

private extension NSPredicate {
    static func escape(query: String) -> String {
        query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
    }
}
