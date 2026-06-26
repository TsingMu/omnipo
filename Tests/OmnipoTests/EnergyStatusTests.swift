import XCTest
import os
@testable import Omnipo

final class EnergyStatusTests: XCTestCase {

    // MARK: - availability(from:) 纯函数

    func test_availability_carriesBatteryAndChargingState() {
        let battery = EnergyStatus.BatteryInfo(percent: 0.7, isCharging: true, isOnExternalPower: true)
        let result = EnergyStatus.availability(from: battery)

        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.batteryPercent ?? -1, 0.7, accuracy: 1e-9)
        XCTAssertEqual(metrics.isCharging, true)
        XCTAssertEqual(metrics.isOnExternalPower, true)
        XCTAssertTrue(metrics.wholeMachinePowerUnsupported, "整机能耗瓦数无公开 API,固定降级")
        XCTAssertTrue(metrics.hasBattery)
    }

    func test_availability_dischargedBattery() {
        let battery = EnergyStatus.BatteryInfo(percent: 0.15, isCharging: false, isOnExternalPower: false)
        let result = EnergyStatus.availability(from: battery)

        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.batteryPercent ?? -1, 0.15, accuracy: 1e-9)
        XCTAssertEqual(metrics.isCharging, false)
        XCTAssertEqual(metrics.isOnExternalPower, false)
    }

    func test_availability_externalPowerWithoutCharging() {
        let battery = EnergyStatus.BatteryInfo(percent: 0.92, isCharging: false, isOnExternalPower: true)
        let result = EnergyStatus.availability(from: battery)

        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.isCharging, false)
        XCTAssertEqual(metrics.isOnExternalPower, true)
    }

    // MARK: - sample() with injected provider

    func test_sample_injectedBatteryReturnsAvailable() {
        let status = EnergyStatus(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.energy"),
            powerSourcesProvider: { .init(percent: 0.42, isCharging: false, isOnExternalPower: false) }
        )

        let result = status.sample()
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.batteryPercent ?? -1, 0.42, accuracy: 1e-9)
        XCTAssertEqual(metrics.isCharging, false)
        XCTAssertEqual(metrics.isOnExternalPower, false)
    }

    func test_sample_nilProviderReturnsNoBattery() {
        let status = EnergyStatus(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.energy"),
            powerSourcesProvider: { nil }
        )

        XCTAssertEqual(status.sample(), .unavailable(reason: .noBattery))
    }

    // MARK: - BatteryInfo 钳制

    func test_batteryInfo_clampsPercentToUnitRange() {
        let high = EnergyStatus.BatteryInfo(percent: 1.5, isCharging: true, isOnExternalPower: true)
        XCTAssertEqual(high.percent, 1.0)

        let negative = EnergyStatus.BatteryInfo(percent: -0.5, isCharging: false, isOnExternalPower: false)
        XCTAssertEqual(negative.percent, 0.0)
    }

    // MARK: - 真实 IOKit 冒烟

    func test_sample_realIOKitReturnsAvailableOrNoBattery() {
        let status = EnergyStatus(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.energy")
        )

        let result = status.sample()
        switch result {
        case .available(let metrics):
            XCTAssertNotNil(metrics.batteryPercent, "真实 IOKit available 时必须有 batteryPercent")
            if let percent = metrics.batteryPercent {
                XCTAssertGreaterThanOrEqual(percent, 0.0)
                XCTAssertLessThanOrEqual(percent, 1.0)
            }
            XCTAssertTrue(metrics.wholeMachinePowerUnsupported)
        case .unavailable(let reason):
            // 桌面机会走 noBattery;笔记本读不到时也可能走 noBattery
            XCTAssertEqual(reason, .noBattery, "真实 IOKit 失败应是 noBattery,不是 iopsFailed 或 unknown")
        }
    }
}
