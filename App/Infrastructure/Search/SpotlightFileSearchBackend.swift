import Foundation

/// 用 `NSMetadataQuery` 实现 Spotlight 文件搜索后端。
///
/// 查询超时或被取消时停止旧 query,返回 unavailable。
/// 不读取文件内容,只查询 Spotlight 已索引的元数据。
public final class SpotlightFileSearchBackend: FileSearchBackend {
    private let logger: any LoggingService
    private let timeout: TimeInterval
    private let resultLimit: Int

    public init(
        logger: any LoggingService,
        timeout: TimeInterval = 2.0,
        resultLimit: Int = 100
    ) {
        self.logger = logger
        self.timeout = timeout
        self.resultLimit = resultLimit
    }

    public func search(query: String) async -> FileSearchBackendResult {
        let escaped = NSPredicate.escape(query: query)
        let predicate = NSPredicate(
            format: "(kMDItemDisplayName LIKE[cd] %@) OR (kMDItemFSName LIKE[cd] %@)",
            "*\(escaped)*",
            "*\(escaped)*"
        )

        return await withCheckedContinuation { (continuation: CheckedContinuation<FileSearchBackendResult, Never>) in
            let metadataQuery = NSMetadataQuery()
            metadataQuery.predicate = predicate
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
                continuation.resume(returning: result)
            }
            coordinator.start()
        }
    }
}

private final class SpotlightCoordinator: NSObject {
    private let query: NSMetadataQuery
    private let resultLimit: Int
    private let timeout: TimeInterval
    private let logger: any LoggingService
    private let completion: (FileSearchBackendResult) -> Void

    private var finishedObserver: NSObjectProtocol?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didResume = false

    /// 自持有引用。`start()` 后调用方不再强持有 coordinator,如果不自持有,
    /// 通知 block(weak self)会立即看到 nil,continuation 永远不会被 resume。
    /// 在 `resume` 时清空以打破循环。
    private var selfRef: SpotlightCoordinator?

    init(
        query: NSMetadataQuery,
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
        super.init()
    }

    func start() {
        selfRef = self
        finishedObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleFinish()
        }

        let work = DispatchWorkItem { [weak self] in
            self?.handleTimeout()
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        query.start()
    }

    private func handleFinish() {
        guard !didResume else { return }
        cleanup()
        let entries = collectEntries()
        resume(.success(entries))
    }

    private func handleTimeout() {
        guard !didResume else { return }
        cleanup()
        query.stop()
        logger.log(Self.logTimeout())
        resume(.unavailable(reason: "timeout"))
    }

    private func collectEntries() -> [FileEntry] {
        var entries: [FileEntry] = []
        let count = query.resultCount
        let upper = min(count, resultLimit)
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

    private func cleanup() {
        if let observer = finishedObserver {
            NotificationCenter.default.removeObserver(observer)
            finishedObserver = nil
        }
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func resume(_ result: FileSearchBackendResult) {
        guard !didResume else { return }
        didResume = true
        completion(result)
        selfRef = nil
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
    /// 简单转义 LIKE 中的特殊字符。
    static func escape(query: String) -> String {
        query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
    }
}
