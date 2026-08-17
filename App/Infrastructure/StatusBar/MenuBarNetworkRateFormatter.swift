/// 菜单栏网络速率纯函数格式化器。
///
/// 采用十进制单位(1 K = 1,000 B),小于 10 个单位保留 1 位小数,
/// 达到 10 后省略小数以限制宽度;输出固定使用 ASCII 数字与小数点,
/// 配合等宽数字字体避免每秒刷新造成布局抖动。
/// 负值钳制为 0;NaN 与无穷值视为不可用,显示占位符。
enum MenuBarNetworkRateFormatter {

    /// 预热或不可用状态的占位文本。
    static let placeholder = "--"

    private static let tiers: [(divisor: Double, compactUnit: String, accessibilityUnit: String)] = [
        (1, "B/s", "字节"),
        (1_000, "K/s", "千字节"),
        (1_000_000, "M/s", "兆字节"),
        (1_000_000_000, "G/s", "吉字节"),
    ]

    /// 菜单栏展示文本:`uploadText` 对应上行,`downloadText` 对应下行。
    struct DisplayText: Sendable, Equatable {
        let uploadText: String
        let downloadText: String
    }

    /// 紧凑速率文本,如 `824B/s`、`1.2K/s`、`128M/s`、`1.2G/s`。
    static func compactText(for bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return placeholder }
        let value = max(0, bytesPerSecond)
        let (number, tierIndex) = roundedNumber(for: value)
        return number + tiers[tierIndex].compactUnit
    }

    /// 完整中文速率文本,如 `1.2 兆字节`,供 VoiceOver 辅助功能描述使用。
    static func accessibilityQuantityText(for bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return placeholder }
        let value = max(0, bytesPerSecond)
        let (number, tierIndex) = roundedNumber(for: value)
        return "\(number) \(tiers[tierIndex].accessibilityUnit)"
    }

    /// 将可用性状态映射为上行/下行展示文本。
    static func displayText(from availability: MenuBarNetworkRateAvailability) -> DisplayText {
        switch availability {
        case .warmingUp, .unavailable:
            return DisplayText(uploadText: placeholder, downloadText: placeholder)
        case .available(let snapshot):
            return DisplayText(
                uploadText: compactText(for: snapshot.uploadBytesPerSecond),
                downloadText: compactText(for: snapshot.downloadBytesPerSecond)
            )
        }
    }

    /// 完整中文辅助功能描述,明确区分上传与下载方向。
    static func accessibilityText(from availability: MenuBarNetworkRateAvailability) -> String {
        switch availability {
        case .warmingUp:
            return "网络速率预热中"
        case .unavailable:
            return "网络速率不可用"
        case .available(let snapshot):
            return "上传每秒 \(accessibilityQuantityText(for: snapshot.uploadBytesPerSecond))，下载每秒 \(accessibilityQuantityText(for: snapshot.downloadBytesPerSecond))"
        }
    }

    /// 按档位规则四舍五入;四舍五入跨过单位边界(如 999.6 → 1000)时提升一档,
    /// 保证输出长度受控。
    private static func roundedNumber(for value: Double) -> (text: String, tierIndex: Int) {
        var index = tiers.firstIndex { value < $0.divisor * 1_000 } ?? tiers.index(before: tiers.endIndex)
        while true {
            let scaled = value / tiers[index].divisor
            let fractionDigits = scaled < 10 ? 1 : 0
            let text = String(format: "%.\(fractionDigits)f", scaled)
            if let number = Double(text), number >= 1_000, index + 1 < tiers.count {
                index += 1
                continue
            }
            return (text, index)
        }
    }
}
