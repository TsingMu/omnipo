import Foundation

/// APP 使用情况单次采样边界。
///
/// 实现必须只返回当前采样周期的资源快照,不得持久化历史使用情况。
public protocol AppUsageSampling: Sendable {
    func sampleAppUsage() async -> AppUsageAvailability
}
