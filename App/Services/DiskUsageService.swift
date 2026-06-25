import Foundation

public enum DiskCapacityLoadTrigger: String, Sendable, Equatable, CaseIterable {
    case initialLoad
    case userRefresh
}

public enum LargeFileLoadTrigger: String, Sendable, Equatable, CaseIterable {
    case initialLoad
    case userRefresh
}

/// 磁盘只读信息服务的最小职责集合。
///
/// `loadStartupVolumeCapacity` 返回启动卷容量摘要;`loadLargeFiles` 返回按大小降序的大文件列表。
/// 实现必须保证:
/// - 不通过目录递归统计生成首页容量数字(容量只用卷级元数据)。
/// - 大文件枚举只读取元数据,不读取文件内容。
/// - 大文件刷新必须取消上一次未完成的扫描,避免并发堆积。
public protocol DiskUsageService: AnyObject, Sendable {
    func loadStartupVolumeCapacity(
        trigger: DiskCapacityLoadTrigger
    ) async -> DiskCapacityAvailability

    func loadLargeFiles(
        limit: Int,
        trigger: LargeFileLoadTrigger
    ) async -> LargeFileAvailability
}

public extension DiskUsageService {
    func loadStartupVolumeCapacity() async -> DiskCapacityAvailability {
        await loadStartupVolumeCapacity(trigger: .initialLoad)
    }

    func refreshStartupVolumeCapacity() async -> DiskCapacityAvailability {
        await loadStartupVolumeCapacity(trigger: .userRefresh)
    }

    func loadLargeFiles(limit: Int) async -> LargeFileAvailability {
        await loadLargeFiles(limit: limit, trigger: .initialLoad)
    }

    func refreshLargeFiles(limit: Int) async -> LargeFileAvailability {
        await loadLargeFiles(limit: limit, trigger: .userRefresh)
    }

    /// 默认大文件结果条数上限。具体调用方可以传入更小或更大的值。
    static var defaultLargeFileLimit: Int { 50 }
}
