/// 菜单栏整机网络速率快照:上传与下载方向各自的字节/秒。
///
/// 仅承载整机总速率,不暴露接口明细;由菜单栏专属采样生命周期发布,
/// 不与系统监控页面的采样服务共享状态。
public struct MenuBarNetworkRateSnapshot: Sendable, Equatable {
    public let uploadBytesPerSecond: Double
    public let downloadBytesPerSecond: Double

    public init(uploadBytesPerSecond: Double, downloadBytesPerSecond: Double) {
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }
}

/// 菜单栏网络速率可用性状态。
///
/// 预热与不可用必须显式表达,不得以零速率冒充尚未计算或读取失败的结果。
public enum MenuBarNetworkRateAvailability: Sendable, Equatable {
    /// 首次采样仅保存基线,尚不能计算差值。
    case warmingUp
    /// 已获得两次有效样本差值计算出的真实速率。
    case available(MenuBarNetworkRateSnapshot)
    /// 底层公开 API 读取失败,需安全降级。
    case unavailable
}
