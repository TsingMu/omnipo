import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var lastOpenedDestination: AppDestination
    var startupVolumeCapacity: DiskCapacityAvailability = .idle
    var largeFileAvailability: LargeFileAvailability = .idle

    private let diskUsageService: any DiskUsageService
    private var loadTask: Task<Void, Never>?
    private var loadTaskID: UUID?
    private var largeFileTask: Task<Void, Never>?
    private var largeFileTaskID: UUID?
    private let largeFileLimit: Int

    init(
        lastOpenedDestination: AppDestination = .dashboard,
        diskUsageService: any DiskUsageService,
        largeFileLimit: Int = 50
    ) {
        self.lastOpenedDestination = lastOpenedDestination
        self.diskUsageService = diskUsageService
        self.largeFileLimit = largeFileLimit
    }

    // MARK: - Startup Volume Capacity

    func loadStartupVolumeCapacityIfNeeded() async {
        guard case .idle = startupVolumeCapacity else { return }
        await performLoad(trigger: .initialLoad)
    }

    func refreshStartupVolumeCapacity() async {
        await performLoad(trigger: .userRefresh)
    }

    private func performLoad(trigger: DiskCapacityLoadTrigger) async {
        if let loadTask {
            await loadTask.value
            return
        }

        startupVolumeCapacity = .loading
        let taskID = UUID()
        let task = Task { @MainActor in
            let result = await diskUsageService.loadStartupVolumeCapacity(trigger: trigger)
            startupVolumeCapacity = result
        }
        loadTaskID = taskID
        loadTask = task
        await task.value
        if loadTaskID == taskID {
            loadTask = nil
            loadTaskID = nil
        }
    }

    // MARK: - Large Files

    /// 首次显示磁盘分析页时调用;若状态仍是 `.idle` 才触发,避免重复扫描。
    func loadLargeFilesIfNeeded() async {
        guard case .idle = largeFileAvailability else { return }
        await performLargeFileLoad(trigger: .initialLoad)
    }

    /// 用户在磁盘分析页点击刷新时调用;强制重新扫描。
    /// SystemDiskUsageService 内部会取消上一次未完成的扫描任务。
    func refreshLargeFiles() async {
        await performLargeFileLoad(trigger: .userRefresh)
    }

    private func performLargeFileLoad(trigger: LargeFileLoadTrigger) async {
        if let largeFileTask, trigger == .initialLoad {
            // 已有进行中的初次加载,直接 join 避免重复扫描。
            await largeFileTask.value
            return
        }

        if trigger == .userRefresh {
            largeFileTask?.cancel()
        }

        largeFileAvailability = .loading
        let taskID = UUID()
        let limit = largeFileLimit
        let task = Task { @MainActor in
            let result = await diskUsageService.loadLargeFiles(limit: limit, trigger: trigger)
            guard !Task.isCancelled, largeFileTaskID == taskID else { return }
            largeFileAvailability = result
        }
        largeFileTaskID = taskID
        largeFileTask = task
        await task.value
        if largeFileTaskID == taskID {
            largeFileTask = nil
            largeFileTaskID = nil
        }
    }
}
