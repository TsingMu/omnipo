import Foundation

/// 已安装应用的进程内索引。
///
/// 首次读取在索引为空时等待一次发现；索引过期后仍优先返回已有快照，并在后台刷新。
/// 所有并发刷新共享同一个任务，避免快速输入时重复扫描应用目录。
public actor ApplicationIndex {
    public typealias Discover = @Sendable () async -> [AppRecord]

    private struct RefreshFlight {
        let id: UInt64
        let task: Task<[AppRecord], Never>
    }

    private let discover: Discover
    private let cacheTTL: TimeInterval
    private var records: [AppRecord] = []
    private var lastRefresh: Date = .distantPast
    private var nextFlightID: UInt64 = 0
    private var refreshFlight: RefreshFlight?

    public init(
        cacheTTL: TimeInterval = 60,
        discover: @escaping Discover
    ) {
        self.cacheTTL = cacheTTL
        self.discover = discover
    }

    /// 启动阶段后台调用；若已有有效快照则不重复刷新。
    public func prewarm() async {
        guard needsRefresh(at: Date()) else { return }
        _ = await refreshedRecords()
    }

    /// 返回可用于即时匹配的快照。
    ///
    /// 索引为空时等待正在进行或新建的刷新；已有过期快照时立即返回，并启动后台刷新。
    public func currentRecords() async -> [AppRecord] {
        guard needsRefresh(at: Date()) else { return records }

        if records.isEmpty {
            return await refreshedRecords()
        }

        let flight = refreshFlight ?? makeRefreshFlight()
        Task { [weak self] in
            await self?.finish(flight)
        }
        return records
    }

    /// 显式刷新索引；并发调用仍共享同一个发现任务。
    public func refresh() async {
        _ = await refreshedRecords()
    }

    private func needsRefresh(at now: Date) -> Bool {
        records.isEmpty || now.timeIntervalSince(lastRefresh) >= cacheTTL
    }

    private func refreshedRecords() async -> [AppRecord] {
        let flight = refreshFlight ?? makeRefreshFlight()
        return await finish(flight)
    }

    private func makeRefreshFlight() -> RefreshFlight {
        nextFlightID &+= 1
        let discover = discover
        let task = Task.detached(priority: .utility) {
            await discover()
        }
        let flight = RefreshFlight(id: nextFlightID, task: task)
        refreshFlight = flight
        return flight
    }

    private func finish(_ flight: RefreshFlight) async -> [AppRecord] {
        let fresh = await flight.task.value
        guard refreshFlight?.id == flight.id else { return fresh }
        records = fresh
        lastRefresh = Date()
        refreshFlight = nil
        return fresh
    }
}
