import XCTest
import os
@testable import Omnipo

private func vmStats(
    free: UInt32 = 0,
    active: UInt32 = 0,
    inactive: UInt32 = 0,
    wired: UInt32 = 0,
    compressed: UInt32 = 0,
    speculative: UInt32 = 0
) -> MemorySampler.VMStatistics {
    MemorySampler.VMStatistics(
        freeCount: free,
        activeCount: active,
        inactiveCount: inactive,
        wireCount: wired,
        compressorPageCount: compressed,
        speculativeCount: speculative
    )
}

final class MemorySamplerTests: XCTestCase {

    // MARK: - availability(totalBytes:vmStats:) 纯函数

    func test_availability_computesUsedAvailableCompressed() {
        // getpagesize() 在 macOS 上与 vm_kernel_page_size 一致(Apple Silicon 16384,Intel 4096)
        let pageSize = Int64(getpagesize())
        // 用足够大的 total 让 free + inactive 不超过 total,避免 MemoryMetrics 钳制干扰
        let total: Int64 = 1_000_000_000
        let free: UInt32 = 1_000
        let inactive: UInt32 = 500
        let compressed: UInt32 = 200

        let stats = vmStats(free: free, inactive: inactive, compressed: compressed)
        let result = MemorySampler.availability(totalBytes: total, vmStats: stats)

        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.totalBytes, total)
        XCTAssertEqual(metrics.availableBytes, Int64(free) * pageSize + Int64(inactive) * pageSize)
        XCTAssertEqual(metrics.usedBytes, total - metrics.availableBytes)
        XCTAssertEqual(metrics.compressedBytes, Int64(compressed) * pageSize)
    }

    func test_availability_clampsAvailableToTotal() {
        // free + inactive 超过 total 时,available 钳到 total
        let total: Int64 = 1_000
        let stats = vmStats(free: 1_000_000, inactive: 1_000_000)
        let result = MemorySampler.availability(totalBytes: total, vmStats: stats)

        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.availableBytes, total, "available 不超过 total")
        XCTAssertEqual(metrics.usedBytes, 0)
    }

    func test_availability_handlesZeroFree() {
        let total: Int64 = 8_000_000
        let stats = vmStats(free: 0, active: 1000, compressed: 200)
        let result = MemorySampler.availability(totalBytes: total, vmStats: stats)

        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.availableBytes, 0)
        XCTAssertEqual(metrics.usedBytes, total)
        XCTAssertNotNil(metrics.compressedBytes)
    }

    // MARK: - sample() with injected providers

    func test_sample_successReturnsAvailable() {
        let sampler = MemorySampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.mem"),
            totalBytesProvider: { 1_000_000 },
            vmStatsProvider: { vmStats(free: 100, inactive: 50, compressed: 10) }
        )

        let result = sampler.sample()
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(metrics.totalBytes, 1_000_000)
        XCTAssertGreaterThan(metrics.availableBytes, 0)
    }

    func test_sample_totalBytesFailureReturnsSysctlFailed() {
        let sampler = MemorySampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.mem"),
            totalBytesProvider: { nil },
            vmStatsProvider: { vmStats() }
        )

        XCTAssertEqual(sampler.sample(), .unavailable(reason: .sysctlFailed))
    }

    func test_sample_vmStatsFailureReturnsHostStatsFailed() {
        let sampler = MemorySampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.mem"),
            totalBytesProvider: { 1_000_000 },
            vmStatsProvider: { nil }
        )

        XCTAssertEqual(sampler.sample(), .unavailable(reason: .hostStatsFailed))
    }

    // MARK: - 真实 Mach / sysctl 冒烟

    func test_sample_realProvidersReturnAvailable() {
        let sampler = MemorySampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.mem")
        )

        let result = sampler.sample()
        guard case .available(let metrics) = result else {
            return XCTFail("real sysctl + Mach should produce available metrics")
        }
        XCTAssertGreaterThan(metrics.totalBytes, 0, "hw.memsize 应返回正值")
        XCTAssertGreaterThanOrEqual(metrics.availableBytes, 0)
        XCTAssertLessThanOrEqual(metrics.availableBytes, metrics.totalBytes)
    }

    func test_sample_realMemoryTotalMatchesHardware() {
        // 真实 hw.memsize 至少应有数 GB
        let sampler = MemorySampler(
            logger: OSLogLoggingService(subsystem: "com.omnipo.tests.mem")
        )

        let result = sampler.sample()
        guard case .available(let metrics) = result else {
            return XCTFail("expected available")
        }
        // 至少 1 GB,作为冒烟下限
        XCTAssertGreaterThan(metrics.totalBytes, 1_000_000_000)
    }
}
