import Foundation
import IOKit.ps
import os

/// 能耗采样器。
///
/// 使用公开 IOKit API(`IOPSCopyPowerSourcesInfo`)读取电池电量与充放电状态;
/// 整机能耗瓦数在 macOS 无公开 API(SMC/PowerMetrics 私有或需特权),固定降级,
/// UI 据此展示说明文案,不调用任何私有框架。
public struct EnergyStatus: Sendable {

    /// 单个电池的 Sendable 包装。
    public struct BatteryInfo: Sendable, Equatable {
        /// 0.0 ... 1.0;由 IOKit 的 current/max 归一化得到。
        public let percent: Double
        public let isCharging: Bool
        public let isOnExternalPower: Bool

        public init(percent: Double, isCharging: Bool, isOnExternalPower: Bool) {
            self.percent = max(0, min(1, percent))
            self.isCharging = isCharging
            self.isOnExternalPower = isOnExternalPower
        }
    }

    private let logger: any LoggingService
    private let powerSourcesProvider: @Sendable () -> BatteryInfo?

    public init(logger: any LoggingService) {
        self.logger = logger
        self.powerSourcesProvider = Self.readBatteryInfo
    }

    init(
        logger: any LoggingService,
        powerSourcesProvider: @escaping @Sendable () -> BatteryInfo?
    ) {
        self.logger = logger
        self.powerSourcesProvider = powerSourcesProvider
    }

    public func sample() -> EnergyAvailability {
        guard let battery = powerSourcesProvider() else {
            // IOKit 在桌面机或读不到电池信息时返回 nil → 视为无电池。
            return .unavailable(reason: .noBattery)
        }
        return Self.availability(from: battery)
    }

    /// 从 BatteryInfo 派生 EnergyAvailability(纯函数)。
    ///
    /// 整机能耗瓦数固定 `wholeMachinePowerUnsupported = true`,UI 据此显示降级文案;
    /// 电池百分比与充放电状态由调用方传入的 BatteryInfo 决定。
    public static func availability(from battery: BatteryInfo) -> EnergyAvailability {
        .available(EnergyMetrics(
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            isOnExternalPower: battery.isOnExternalPower,
            wholeMachinePowerUnsupported: true
        ))
    }

    // MARK: - 真实 IOKit 读取

    /// 读取主电池信息;无电池(桌面机)或 IOKit 调用失败返回 nil。
    private static func readBatteryInfo() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return nil
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first else {
            return nil
        }
        guard let desc = IOPSGetPowerSourceDescription(blob, firstSource)?
            .takeUnretainedValue() as? [String: Any] else {
            return nil
        }

        // IOKit 通常返回 0...100 的归一化值,但保险起见用 max 做除数。
        guard let max = desc[kIOPSMaxCapacityKey] as? Int,
              let current = desc[kIOPSCurrentCapacityKey] as? Int,
              max > 0 else {
            return nil
        }
        let percent = Double(current) / Double(max)
        let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let powerSourceState = desc[kIOPSPowerSourceStateKey] as? String
        let isOnExternalPower = powerSourceState == kIOPSACPowerValue

        return BatteryInfo(
            percent: percent,
            isCharging: isCharging,
            isOnExternalPower: isOnExternalPower
        )
    }
}
