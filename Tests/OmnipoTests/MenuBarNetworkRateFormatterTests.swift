import XCTest
@testable import Omnipo

final class MenuBarNetworkRateFormatterTests: XCTestCase {

    // MARK: - 紧凑格式化:字节档

    func test_compactText_byteTier() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 0), "0.0B/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 0.4), "0.4B/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 9.94), "9.9B/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 10), "10B/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 824), "824B/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 999.4), "999B/s")
    }

    // MARK: - 紧凑格式化:千/兆/吉档

    func test_compactText_kiloTier() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 1_000), "1.0K/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 1_234), "1.2K/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 128_000), "128K/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 999_499), "999K/s")
    }

    func test_compactText_megaTier() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 1_000_000), "1.0M/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 1_234_567), "1.2M/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 128_000_000), "128M/s")
    }

    func test_compactText_gigaTier() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 1_000_000_000), "1.0G/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 1_500_000_000), "1.5G/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 128_000_000_000), "128G/s")
    }

    // MARK: - 单位边界与长度控制

    func test_compactText_promotesWhenRoundingCrossesBoundary() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 999.6), "1.0K/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 999_999.6), "1.0M/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: 999_999_999.6), "1.0G/s")
    }

    func test_compactText_outputLengthStaysBounded() {
        for exponent in stride(from: 0.0, through: 10.0, by: 0.05) {
            let text = MenuBarNetworkRateFormatter.compactText(for: pow(10, exponent))
            XCTAssertLessThanOrEqual(text.count, 7, "输出超宽: \(text)")
        }
    }

    // MARK: - 负值与非有限值

    func test_compactText_clampsNegativeToZero() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: -5), "0.0B/s")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: -1_000), "0.0B/s")
    }

    func test_compactText_treatsNonFiniteAsPlaceholder() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: .nan), "--")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: .infinity), "--")
        XCTAssertEqual(MenuBarNetworkRateFormatter.compactText(for: -.infinity), "--")
    }

    // MARK: - 上传/下载字段映射

    func test_displayText_warmingUpShowsPlaceholder() {
        let text = MenuBarNetworkRateFormatter.displayText(from: .warmingUp)
        XCTAssertEqual(text.uploadText, "--")
        XCTAssertEqual(text.downloadText, "--")
    }

    func test_displayText_unavailableShowsPlaceholder() {
        let text = MenuBarNetworkRateFormatter.displayText(from: .unavailable)
        XCTAssertEqual(text.uploadText, "--")
        XCTAssertEqual(text.downloadText, "--")
    }

    func test_displayText_mapsUploadToUpperAndDownloadToLower() {
        let text = MenuBarNetworkRateFormatter.displayText(
            from: .available(MenuBarNetworkRateSnapshot(
                uploadBytesPerSecond: 1_234_567,
                downloadBytesPerSecond: 8_400_000
            ))
        )
        XCTAssertEqual(text.uploadText, "1.2M/s")
        XCTAssertEqual(text.downloadText, "8.4M/s")
    }

    func test_displayText_zeroRatesRemainVisible() {
        let text = MenuBarNetworkRateFormatter.displayText(
            from: .available(MenuBarNetworkRateSnapshot(uploadBytesPerSecond: 0, downloadBytesPerSecond: 0))
        )
        XCTAssertEqual(text.uploadText, "0.0B/s")
        XCTAssertEqual(text.downloadText, "0.0B/s")
    }

    // MARK: - 辅助功能文本

    func test_accessibilityText_usesFullChineseUnits() {
        let text = MenuBarNetworkRateFormatter.accessibilityText(
            from: .available(MenuBarNetworkRateSnapshot(
                uploadBytesPerSecond: 1_200_000,
                downloadBytesPerSecond: 8_400_000
            ))
        )
        XCTAssertEqual(text, "上传每秒 1.2 兆字节，下载每秒 8.4 兆字节")
    }

    func test_accessibilityQuantityText_coversAllUnits() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.accessibilityQuantityText(for: 824), "824 字节")
        XCTAssertEqual(MenuBarNetworkRateFormatter.accessibilityQuantityText(for: 1_234), "1.2 千字节")
        XCTAssertEqual(MenuBarNetworkRateFormatter.accessibilityQuantityText(for: 128_000_000), "128 兆字节")
        XCTAssertEqual(MenuBarNetworkRateFormatter.accessibilityQuantityText(for: 1_500_000_000), "1.5 吉字节")
    }

    func test_accessibilityText_placeholderStates() {
        XCTAssertEqual(MenuBarNetworkRateFormatter.accessibilityText(from: .warmingUp), "网络速率预热中")
        XCTAssertEqual(MenuBarNetworkRateFormatter.accessibilityText(from: .unavailable), "网络速率不可用")
    }
}
