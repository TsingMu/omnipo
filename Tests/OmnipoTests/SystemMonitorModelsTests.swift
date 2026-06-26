import XCTest
@testable import Omnipo

final class SystemMonitorModelsTests: XCTestCase {

    // MARK: - CPU

    func test_cpuMetrics_normalizesToUnitSum() {
        let m = CPUMetrics(userPercent: 0.3, systemPercent: 0.2, idlePercent: 0.5)
        XCTAssertEqual(m.userPercent, 0.3, accuracy: 1e-9)
        XCTAssertEqual(m.systemPercent, 0.2, accuracy: 1e-9)
        XCTAssertEqual(m.idlePercent, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.busyPercent, 0.5, accuracy: 1e-9)
    }

    func test_cpuMetrics_clampsOutOfBoundsAndRescales() {
        // 0.5 + 0.5 + 0.5 = 1.5,会按比例归一化到 0.333... 0.333... 0.333...
        let m = CPUMetrics(userPercent: 0.5, systemPercent: 0.5, idlePercent: 0.5)
        XCTAssertEqual(m.userPercent, 1.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(m.idlePercent, 1.0 / 3.0, accuracy: 1e-6)
    }

    func test_cpuMetrics_zeroSumFallsBackToIdle() {
        let m = CPUMetrics(userPercent: 0, systemPercent: 0, idlePercent: 0)
        XCTAssertEqual(m.idlePercent, 1.0)
        XCTAssertEqual(m.userPercent, 0.0)
        XCTAssertEqual(m.systemPercent, 0.0)
    }

    func test_cpuAvailability_accessors() {
        let available: CPULoadAvailability = .available(CPUMetrics(userPercent: 0.3, systemPercent: 0.2, idlePercent: 0.5))
        XCTAssertNotNil(available.metrics)
        XCTAssertNil(available.unavailableReason)

        let unavailable: CPULoadAvailability = .unavailable(reason: .warmup)
        XCTAssertNil(unavailable.metrics)
        XCTAssertEqual(unavailable.unavailableReason, .warmup)
    }

    func test_cpuUnavailableReasons_haveUniqueStableCodes() {
        let codes = Set(CPULoadUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, CPULoadUnavailableReason.allCases.count)
    }

    func test_cpuUnavailableReasons_haveNonEmptyDescriptions() {
        for reason in CPULoadUnavailableReason.allCases {
            XCTAssertFalse(reason.userDescription.isEmpty)
        }
    }

    // MARK: - Memory

    func test_memoryMetrics_clampsToTotal() {
        let m = MemoryMetrics(totalBytes: 100, usedBytes: 200, availableBytes: 50)
        XCTAssertEqual(m.totalBytes, 100)
        XCTAssertLessThanOrEqual(m.usedBytes + m.availableBytes, m.totalBytes)
    }

    func test_memoryMetrics_clampsNegative() {
        let m = MemoryMetrics(totalBytes: -50, usedBytes: -10, availableBytes: -5)
        XCTAssertEqual(m.totalBytes, 0)
        XCTAssertEqual(m.usedBytes, 0)
        XCTAssertEqual(m.availableBytes, 0)
    }

    func test_memoryMetrics_usedFraction() {
        let m = MemoryMetrics(totalBytes: 100, usedBytes: 40, availableBytes: 60)
        XCTAssertEqual(m.usedFraction ?? -1, 0.4, accuracy: 1e-9)

        let zero = MemoryMetrics(totalBytes: 0, usedBytes: 0, availableBytes: 0)
        XCTAssertNil(zero.usedFraction)
    }

    func test_memoryUnavailableReasons_haveUniqueStableCodes() {
        let codes = Set(MemoryUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, MemoryUnavailableReason.allCases.count)
    }

    // MARK: - Energy

    func test_energyMetrics_clampsBatteryPercent() {
        let m = EnergyMetrics(batteryPercent: 1.5, isCharging: true)
        XCTAssertEqual(m.batteryPercent, 1.0)
        XCTAssertEqual(m.isCharging, true)
        XCTAssertTrue(m.hasBattery)

        let negative = EnergyMetrics(batteryPercent: -0.5, isCharging: false)
        XCTAssertEqual(negative.batteryPercent, 0.0)
    }

    func test_energyMetrics_wholeMachinePowerUnsupportedDefaultsTrue() {
        let m = EnergyMetrics(batteryPercent: 0.8, isCharging: false)
        XCTAssertTrue(m.wholeMachinePowerUnsupported, "整机能耗瓦数无公开 API,默认标记为不支持")
    }

    func test_energyAvailability_noBatteryUnavailable() {
        let unavailable: EnergyAvailability = .unavailable(reason: .noBattery)
        XCTAssertNil(unavailable.metrics)
        XCTAssertEqual(unavailable.unavailableReason, .noBattery)
    }

    func test_energyUnavailableReasons_haveUniqueStableCodes() {
        let codes = Set(EnergyUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, EnergyUnavailableReason.allCases.count)
    }

    // MARK: - Network

    func test_networkMetrics_aggregatesTotals() {
        let m = NetworkMetrics(interfaces: [
            InterfaceStats(name: "en0", bytesInPerSec: 100, bytesOutPerSec: 50),
            InterfaceStats(name: "en1", bytesInPerSec: 200, bytesOutPerSec: 30)
        ])
        XCTAssertEqual(m.totalBytesInPerSec, 300, accuracy: 1e-9)
        XCTAssertEqual(m.totalBytesOutPerSec, 80, accuracy: 1e-9)
    }

    func test_networkMetrics_sortsInterfacesByName() {
        let m = NetworkMetrics(interfaces: [
            InterfaceStats(name: "en5", bytesInPerSec: 0, bytesOutPerSec: 0),
            InterfaceStats(name: "en0", bytesInPerSec: 0, bytesOutPerSec: 0)
        ])
        XCTAssertEqual(m.interfaces.map(\.name), ["en0", "en5"])
    }

    func test_interfaceStats_clampsNegativeRates() {
        let i = InterfaceStats(name: "en0", bytesInPerSec: -100, bytesOutPerSec: -50)
        XCTAssertEqual(i.bytesInPerSec, 0)
        XCTAssertEqual(i.bytesOutPerSec, 0)
    }

    func test_networkUnavailableReasons_haveUniqueStableCodes() {
        let codes = Set(NetworkUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, NetworkUnavailableReason.allCases.count)
    }

    // MARK: - SystemMetricSnapshot

    func test_snapshot_emptyIsEmpty() {
        XCTAssertTrue(SystemMetricSnapshot.empty.isEmpty)
    }

    func test_snapshot_partialFieldsAreIndependent() {
        let s = SystemMetricSnapshot(
            cpu: .available(CPUMetrics(userPercent: 0.5, systemPercent: 0.3, idlePercent: 0.2)),
            memory: nil,
            energy: .available(EnergyMetrics(batteryPercent: 0.8, isCharging: false))
        )
        XCTAssertNotNil(s.cpu)
        XCTAssertNil(s.memory)
        XCTAssertNotNil(s.energy)
        XCTAssertNil(s.disk)
        XCTAssertNil(s.network)
        XCTAssertFalse(s.isEmpty)
    }

    func test_snapshot_canCarryUnavailableStates() {
        let s = SystemMetricSnapshot(
            cpu: .unavailable(reason: .warmup),
            network: .unavailable(reason: .getifaddrsFailed)
        )
        XCTAssertEqual(s.cpu?.unavailableReason, .warmup)
        XCTAssertEqual(s.network?.unavailableReason, .getifaddrsFailed)
    }
}

// MARK: - SystemMonitorInterval

final class SystemMonitorIntervalTests: XCTestCase {

    func test_defaultsAreSensible() {
        XCTAssertEqual(SystemMonitorInterval.defaultSeconds, 5)
        XCTAssertEqual(SystemMonitorInterval.minSeconds, 1)
        XCTAssertEqual(SystemMonitorInterval.maxSeconds, 30)
    }

    func test_isValid_acceptsInRange() {
        XCTAssertTrue(SystemMonitorInterval.isValid(1))
        XCTAssertTrue(SystemMonitorInterval.isValid(5))
        XCTAssertTrue(SystemMonitorInterval.isValid(30))
    }

    func test_isValid_rejectsOutOfBoundsAndNaN() {
        XCTAssertFalse(SystemMonitorInterval.isValid(0))
        XCTAssertFalse(SystemMonitorInterval.isValid(-1))
        XCTAssertFalse(SystemMonitorInterval.isValid(31))
        XCTAssertFalse(SystemMonitorInterval.isValid(.nan))
        XCTAssertFalse(SystemMonitorInterval.isValid(.infinity))
    }

    func test_clampOrFallback_returnsValidValueUntouched() {
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(5), 5)
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(1), 1)
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(30), 30)
    }

    func test_clampOrFallback_fallsBackOnInvalid() {
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(0), 5)
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(-3), 5)
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(60), 5)
        XCTAssertEqual(SystemMonitorInterval.clampOrFallback(.nan), 5)
    }
}
