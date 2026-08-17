import AppKit

/// 菜单栏双行网速展示视图。
///
/// 仅负责绘制:左侧 Omnipo 模板图标,右侧上行上传、下行下载两行速率文本。
/// 通过 hitTest 返回 nil 不参与命中测试,鼠标事件全部落回 `NSStatusBarButton`,
/// 图标与两行文本的任意位置点击均打开现有菜单。
/// 本视图不持有采样或菜单状态;每秒更新仅改写文本。
/// 辅助功能信息(含上传/下载速率的动态 value)由状态栏按钮本体承载,
/// 本视图及其子树对辅助功能隐藏,保证状态项是 VoiceOver 的单一可操作焦点。
final class MenuBarNetworkSpeedView: NSView {

    private let iconView = NSImageView()
    private let iconFallbackLabel = NSTextField(labelWithString: "O")
    private let uploadLabel = NSTextField(labelWithString: "↑ --")
    private let downloadLabel = NSTextField(labelWithString: "↓ --")

    private static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
    private static let interLineSpacing: CGFloat = 1
    private static let iconSide: CGFloat = 18
    private static let horizontalPadding: CGFloat = 5
    private static let iconTextGap: CGFloat = 4

    /// 双行文本的固定宽度,按最大格式模板测量;数值变化不引起布局抖动。
    private static let textWidth: CGFloat = {
        let templates = ["↑ 10.0G/s", "↓ 999K/s", "↑ 1000G/s", "↑ --"]
        let widths = templates.map {
            ($0 as NSString).size(withAttributes: [.font: rateFont]).width
        }
        return ceil(widths.max() ?? 40) + 1
    }()

    /// 状态项的稳定宽度:图标 + 双行文本 + 边距,用于设置 `NSStatusItem.length`。
    static var preferredWidth: CGFloat {
        ceil(horizontalPadding + iconSide + iconTextGap + textWidth + horizontalPadding)
    }

    private static var lineHeight: CGFloat {
        ceil(rateFont.boundingRectForFont.height)
    }

    /// - Parameter icon: 已解析的模板图标(资源 → 系统符号);为 nil 时显示文本后备标识,
    ///   优先保住菜单入口。
    init(icon: NSImage?) {
        super.init(frame: .zero)

        if let icon {
            iconView.image = icon
            iconView.imageScaling = .scaleProportionallyDown
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
            iconFallbackLabel.font = .systemFont(ofSize: 11, weight: .bold)
            iconFallbackLabel.textColor = .labelColor
        }
        iconFallbackLabel.isHidden = (icon != nil)

        for label in [uploadLabel, downloadLabel] {
            label.font = Self.rateFont
            label.textColor = .labelColor
            label.alignment = .left
            label.lineBreakMode = .byClipping
        }

        for subview in [iconView, iconFallbackLabel, uploadLabel, downloadLabel] {
            addSubview(subview)
        }

        // 隐藏整棵子树,标签与图标不作为独立辅助功能元素暴露
        for view in [self, iconView, iconFallbackLabel, uploadLabel, downloadLabel] {
            view.setAccessibilityHidden(true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MenuBarNetworkSpeedView 不支持从 coder 实例化")
    }

    /// 按可用性状态刷新两行文本;预热/不可用显示 `--` 占位。
    func update(with availability: MenuBarNetworkRateAvailability) {
        let display = MenuBarNetworkRateFormatter.displayText(from: availability)
        uploadLabel.stringValue = "↑ \(display.uploadText)"
        downloadLabel.stringValue = "↓ \(display.downloadText)"
    }

    /// 展示视图不参与命中测试,点击穿透回状态栏按钮,保持整块菜单点击区域。
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    /// 高度服从系统状态栏按钮 bounds(刘海屏/显示缩放差异),宽度固定为稳定长度。
    override func layout() {
        super.layout()
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let lineH = Self.lineHeight
        let stackHeight = lineH * 2 + Self.interLineSpacing
        let stackY = (bounds.height - stackHeight) / 2

        let iconX = Self.horizontalPadding
        if !iconView.isHidden {
            iconView.frame = NSRect(
                x: iconX,
                y: (bounds.height - Self.iconSide) / 2,
                width: Self.iconSide,
                height: Self.iconSide
            )
        } else {
            let fallbackHeight = iconFallbackLabel.fittingSize.height
            iconFallbackLabel.frame = NSRect(
                x: iconX,
                y: (bounds.height - fallbackHeight) / 2,
                width: Self.iconSide,
                height: fallbackHeight
            )
        }

        let textX = iconX + Self.iconSide + Self.iconTextGap
        let textWidth = Self.textWidth
        uploadLabel.frame = NSRect(
            x: textX,
            y: stackY + lineH + Self.interLineSpacing,
            width: textWidth,
            height: lineH
        )
        downloadLabel.frame = NSRect(
            x: textX,
            y: stackY,
            width: textWidth,
            height: lineH
        )
    }
}
