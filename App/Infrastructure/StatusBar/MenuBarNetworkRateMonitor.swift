import Foundation

/// 菜单栏专属的轻量网络速率采样生命周期。
///
/// 复用 `NetworkSampler` 的公开计数与差值算法,不启动包含 CPU/内存/能耗/磁盘的
/// 完整系统监控服务。仅在状态项可见期间按固定间隔采样:
/// 首次采样仅建立差值基线;第二次起发布 `available`;计数读取失败发布 `unavailable`。
/// stop 取消采样任务、结束更新流并清空基线;再次 start 重新预热。
/// 速率与接口名不写入日志,沿用 `NetworkSampler` 的脱敏日志策略。
///
/// 生命周期请求带单调递增的 `requestGeneration`(由调用方的可见性代次提供):
/// 迟到的过期 start 被拒绝(不创建采样会话),迟到的过期 stop 被忽略
/// (不得停止更新一代的会话),与 actor 队列中的实际到达顺序无关。
actor MenuBarNetworkRateMonitor {

    private let sampler: NetworkSampler
    private let interval: TimeInterval

    private var previous: NetworkSampler.Previous?
    private var samplingTask: Task<Void, Never>?
    private var continuation: AsyncStream<MenuBarNetworkRateAvailability>.Continuation?

    /// 已接受的最新请求代次;旧代次请求一律视为过期。
    private var latestRequestGeneration = 0
    /// 当前采样会话代次,供采样任务识别自身是否仍是当前会话。
    private var sessionGeneration = 0

    /// - Parameters:
    ///   - sampler: 网络采样器;生产注入读取 `getifaddrs()` 的实例,测试注入可控计数。
    ///   - interval: 采样间隔秒数,生产固定 1 秒,测试可注入更短间隔。
    init(sampler: NetworkSampler, interval: TimeInterval = 1) {
        self.sampler = sampler
        self.interval = interval
    }

    /// 开始采样会话,返回本次会话的更新流。
    ///
    /// 幂等:同一最新代次内重复调用不创建第二个采样任务,也不重置差值基线;
    /// 旧流被结束,由新返回的流继续接收当前会话的更新。
    /// 新会话开始时立即发布一次 `warmingUp`。
    /// 过期代次的请求返回已结束的空流,不创建会话。
    func start(requestGeneration: Int) -> AsyncStream<MenuBarNetworkRateAvailability> {
        guard requestGeneration >= latestRequestGeneration else {
            return Self.finishedStream()
        }
        latestRequestGeneration = requestGeneration

        continuation?.finish()

        let (stream, continuation) = AsyncStream.makeStream(
            of: MenuBarNetworkRateAvailability.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        self.continuation = continuation

        guard samplingTask == nil else { return stream }

        sessionGeneration += 1
        let session = sessionGeneration
        let tick = interval
        continuation.yield(.warmingUp)

        samplingTask = Task { [weak self, session, tick] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(tick))
                } catch {
                    return
                }
                guard let self else { return }
                let keepRunning = await self.sampleAndPublish(session: session)
                if !keepRunning { return }
            }
        }
        return stream
    }

    /// 停止采样:取消任务、结束更新流并清空差值基线。可重复调用;再次 start 重新预热。
    /// 过期代次的请求被忽略,不得停止更新一代的会话。
    func stop(requestGeneration: Int) {
        guard requestGeneration >= latestRequestGeneration else { return }
        latestRequestGeneration = requestGeneration

        sessionGeneration += 1
        samplingTask?.cancel()
        samplingTask = nil
        continuation?.finish()
        continuation = nil
        previous = nil
    }

    /// 采样并发布一次;返回是否继续循环。
    /// 会话代次不匹配(stop 或重启后的晚到结果)时丢弃结果并退出循环。
    /// 速率换算使用 `NetworkSampler` 内部的实际采样时间差。
    private func sampleAndPublish(session: Int) -> Bool {
        guard session == sessionGeneration, let continuation else { return false }

        let isFirstSample = previous == nil
        let (availability, newPrevious) = sampler.sample(previous: previous)
        previous = newPrevious

        if isFirstSample {
            // 首次采样:成功仅建立基线,不发布;读取失败直接降级
            if case .unavailable = availability {
                continuation.yield(.unavailable)
            }
            return true
        }

        switch availability {
        case .available(let metrics):
            continuation.yield(.available(MenuBarNetworkRateSnapshot(
                uploadBytesPerSecond: metrics.totalBytesOutPerSec,
                downloadBytesPerSecond: metrics.totalBytesInPerSec
            )))
        case .unavailable:
            continuation.yield(.unavailable)
        }
        return true
    }

    private static func finishedStream() -> AsyncStream<MenuBarNetworkRateAvailability> {
        let (stream, continuation) = AsyncStream.makeStream(of: MenuBarNetworkRateAvailability.self)
        continuation.finish()
        return stream
    }
}
