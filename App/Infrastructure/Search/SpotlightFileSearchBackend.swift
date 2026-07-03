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

protocol SpotlightMetadataItem {
    func value(forAttribute key: String) -> Any?
}

extension NSMetadataItem: SpotlightMetadataItem {}

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
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cancellation = SpotlightCancellationBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Task { @MainActor [logger, queryFactory, resultLimit, timeout, trimmedQuery] in
                    let metadataQuery = queryFactory()
                    metadataQuery.predicate = Self.predicate(for: trimmedQuery)
                    metadataQuery.searchScopes = [NSMetadataQueryUserHomeScope]
                    metadataQuery.sortDescriptors = [
                        NSSortDescriptor(key: "kMDItemFSContentChangeDate", ascending: false)
                    ]

                    let coordinator = SpotlightCoordinator(
                        query: metadataQuery,
                        userQuery: trimmedQuery,
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

    static func predicate(for query: String) -> NSPredicate {
        let attributes = ["kMDItemDisplayName", "kMDItemFSName"]
        let predicates = searchTerms(for: query).flatMap { term in
            let escaped = NSPredicate.escape(query: term)
            return attributes.map { attribute in
                NSPredicate(format: "%K LIKE[cd] %@", attribute, "*\(escaped)*")
            }
        }
        guard !predicates.isEmpty else {
            return NSPredicate(value: false)
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    static func searchTerms(for query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        var terms: [String] = []
        func append(_ term: String) {
            guard term.count >= 2, seen.insert(term).inserted else { return }
            terms.append(term)
        }

        append(trimmed)
        if trimmed.containsCJKCharacters {
            for size in [3, 2] {
                guard trimmed.count > size else { continue }
                for term in trimmed.characterWindows(ofSize: size) {
                    append(term)
                }
            }
        }
        return terms
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
    private let userQuery: String
    private let resultLimit: Int
    private let timeout: TimeInterval
    private let logger: any LoggingService
    private let completion: (FileSearchBackendResult) -> Void

    private var finishedObserver: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didResume = false

    init(
        query: any SpotlightMetadataQuery,
        userQuery: String,
        resultLimit: Int,
        timeout: TimeInterval,
        logger: any LoggingService,
        completion: @escaping (FileSearchBackendResult) -> Void
    ) {
        self.query = query
        self.userQuery = userQuery
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
        let upper = query.resultCount
        for index in 0..<upper {
            guard entries.count < resultLimit,
                  let item = query.result(at: index) as? SpotlightMetadataItem,
                  let path = item.value(forAttribute: "kMDItemPath") as? String else {
                continue
            }
            let url = URL(fileURLWithPath: path)
            let displayName = (item.value(forAttribute: "kMDItemDisplayName") as? String) ?? url.lastPathComponent
            guard Self.fileName(displayName, matches: userQuery) ||
                    Self.fileName(url.lastPathComponent, matches: userQuery) else {
                continue
            }
            guard let bookmark = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { continue }
            let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
            entries.append(FileEntry(displayName: displayName, bookmark: bookmark, fileExtension: ext))
        }
        return entries
    }

    private static func fileName(_ fileName: String, matches query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return fileName.range(
            of: trimmed,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) != nil
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

private extension String {
    var containsCJKCharacters: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
                return true
            default:
                return false
            }
        }
    }

    func characterWindows(ofSize size: Int) -> [String] {
        guard size > 0, count >= size else { return [] }
        var windows: [String] = []
        var start = startIndex
        while let end = index(start, offsetBy: size, limitedBy: endIndex) {
            windows.append(String(self[start..<end]))
            guard start < endIndex else { break }
            formIndex(after: &start)
            if distance(from: start, to: endIndex) < size {
                break
            }
        }
        return windows
    }
}
