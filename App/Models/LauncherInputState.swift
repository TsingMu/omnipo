import Foundation

/// Launcher 搜索框的值状态。
///
/// `displayedText` 保留文本系统正在展示的内容；`effectiveQuery` 是仅用于
/// 当前进程内匹配的查询。后续 AppKit 输入法桥接会在 marked text 变化时
/// 更新这三个值，而不强制提交候选。
public struct LauncherInputState: Sendable, Equatable {
    public let displayedText: String
    public let effectiveQuery: String
    public let isComposing: Bool

    public init(
        displayedText: String,
        effectiveQuery: String? = nil,
        isComposing: Bool = false
    ) {
        self.displayedText = displayedText
        self.effectiveQuery = effectiveQuery ?? displayedText
        self.isComposing = isComposing
    }
}
