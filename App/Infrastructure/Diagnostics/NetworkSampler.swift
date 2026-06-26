import Foundation
import Darwin
import os

/// 网络采样器。
///
/// 使用 BSD `getifaddrs()` 读取每个接口的累计字节数,通过两次采样差值除以时间间隔
/// 得到上下行速率(字节/秒)。回环接口(`lo0` 等)与无 `ifa_data` 的项被过滤;
/// 首次采样无 previous,返回所有接口速率为 0 的占位 metrics。
public struct NetworkSampler: Sendable {

    /// 单次 `getifaddrs` 读取的接口累计字节计数。
    public struct Counters: Sendable, Equatable {
        public let bytesInByInterface: [String: UInt64]
        public let bytesOutByInterface: [String: UInt64]

        public init(bytesInByInterface: [String: UInt64], bytesOutByInterface: [String: UInt64]) {
            self.bytesInByInterface = bytesInByInterface
            self.bytesOutByInterface = bytesOutByInterface
        }

        public static let empty = Counters(bytesInByInterface: [:], bytesOutByInterface: [:])
    }

    /// 上一轮采样的计数与时间戳;首次为 nil。
    public struct Previous: Sendable, Equatable {
        public let counters: Counters
        public let at: Date

        public init(counters: Counters, at: Date) {
            self.counters = counters
            self.at = at
        }
    }

    private let logger: any LoggingService
    private let countersProvider: @Sendable () -> Counters?

    public init(logger: any LoggingService) {
        self.logger = logger
        self.countersProvider = Self.readCounters
    }

    init(
        logger: any LoggingService,
        countersProvider: @escaping @Sendable () -> Counters?
    ) {
        self.logger = logger
        self.countersProvider = countersProvider
    }

    /// 采样一次,返回 availability 与最新 Previous(供下次传入)。
    public func sample(previous: Previous?) -> (NetworkAvailability, Previous?) {
        guard let current = countersProvider() else {
            logger.log(Self.logGetifaddrsFailed())
            return (.unavailable(reason: .getifaddrsFailed), previous)
        }
        let now = Date()
        if let previous {
            let interval = now.timeIntervalSince(previous.at)
            let metrics = Self.metrics(
                from: previous.counters,
                to: current,
                interval: interval
            )
            return (.available(metrics), Previous(counters: current, at: now))
        }
        // 首次采样:返回所有已知接口但速率为 0 的占位 metrics
        let placeholder = Self.placeholderMetrics(from: current)
        return (.available(placeholder), Previous(counters: current, at: now))
    }

    /// 从两次计数差值计算每接口速率(纯函数,便于测试)。
    ///
    /// - delta 为负(接口重置或 wraparound)时按 0 处理,不报错。
    /// - interval <= 0 时所有速率为 0。
    /// - 合并两次采样中出现的新接口;消失的接口忽略。
    public static func metrics(
        from previous: Counters,
        to current: Counters,
        interval: TimeInterval
    ) -> NetworkMetrics {
        let names = Set(previous.bytesInByInterface.keys)
            .union(current.bytesInByInterface.keys)
            .union(current.bytesOutByInterface.keys)
            .union(previous.bytesOutByInterface.keys)

        let safeInterval = interval > 0 ? interval : 0
        let interfaces: [InterfaceStats] = names.sorted().map { name in
            let prevIn = previous.bytesInByInterface[name] ?? 0
            let currIn = current.bytesInByInterface[name] ?? 0
            let prevOut = previous.bytesOutByInterface[name] ?? 0
            let currOut = current.bytesOutByInterface[name] ?? 0

            let deltaIn = currIn >= prevIn ? currIn &- prevIn : 0
            let deltaOut = currOut >= prevOut ? currOut &- prevOut : 0

            let rateIn = safeInterval > 0 ? Double(deltaIn) / safeInterval : 0
            let rateOut = safeInterval > 0 ? Double(deltaOut) / safeInterval : 0
            return InterfaceStats(name: name, bytesInPerSec: rateIn, bytesOutPerSec: rateOut)
        }
        return NetworkMetrics(interfaces: interfaces)
    }

    /// 首次采样占位 metrics:所有接口速率为 0。
    public static func placeholderMetrics(from current: Counters) -> NetworkMetrics {
        let names = Set(current.bytesInByInterface.keys).union(current.bytesOutByInterface.keys)
        let interfaces = names.sorted().map { name in
            InterfaceStats(name: name, bytesInPerSec: 0, bytesOutPerSec: 0)
        }
        return NetworkMetrics(interfaces: interfaces)
    }

    // MARK: - getifaddrs

    private static func readCounters() -> Counters? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return nil
        }
        defer { freeifaddrs(ifaddrPtr) }

        var bytesIn: [String: UInt64] = [:]
        var bytesOut: [String: UInt64] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next

            let nameCString = entry.pointee.ifa_name
            guard let nameCString else { continue }
            let name = String(cString: nameCString)

            // 过滤回环(lo0、llw0 等),只关心真实流量接口
            if name.hasPrefix("lo") { continue }

            guard let dataPtr = entry.pointee.ifa_data else { continue }
            // ifa_data 指向 if_data;字段对齐与平台相关,用 memoryBound 读取。
            // macOS 上 if_data 前 4 个字段是 type / typelen / physical / addrlen,
            // 接下来是 6 个 u_int32:received_bytes / transmitted_bytes 等(SDK 头文档)。
            // 直接 bind 为 if_data_ptr 不可移植,改用 offset 读取最稳。
            let ifdPtr = dataPtr.assumingMemoryBound(to: if_data.self)
            let ifd = ifdPtr.pointee

            // ifi_ibytes 与 ifi_obytes 字段位于 if_data 结构中。
            // macOS if_data 头:`ifi_obytes`、`ifi_imobytes` 等。
            // 在 Apple 平台,`if_data.ifi_ibytes` / `ifi_obytes` 是 u_int32_t。
            bytesIn[name, default: 0] &+= UInt64(ifd.ifi_ibytes)
            bytesOut[name, default: 0] &+= UInt64(ifd.ifi_obytes)
        }

        return Counters(bytesInByInterface: bytesIn, bytesOutByInterface: bytesOut)
    }

    private static func logGetifaddrsFailed() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "monitor.network.getifaddrsFailed",
            stableCode: "W_NET_GETIFADDRS_FAILED",
            sanitizedContext: ["code": "W_NET_GETIFADDRS_FAILED", "reason": "getifaddrs-failed"]
        )
    }
}
