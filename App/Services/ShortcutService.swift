import Foundation

/// 全局快捷键服务协议。
///
/// 实现必须:
/// - 不申请辅助功能或输入监控权限。
/// - 注册失败时保留上一次有效快捷键。
/// - 多次注册幂等,不重复安装事件处理器。
public protocol ShortcutService: AnyObject, Sendable {
    func currentShortcut() async -> KeyboardShortcut
    func defaultShortcut() -> KeyboardShortcut
    func register(_ shortcut: KeyboardShortcut) async -> ShortcutRegistrationResult
    func unregister() async
    func restoreDefault() async -> ShortcutRegistrationResult
    var onTrigger: (@MainActor () -> Void)? { get set }
}

public enum ShortcutRegistrationResult: Sendable, Equatable {
    case success(KeyboardShortcut)
    case failure(ShortcutError)
}

public enum ShortcutError: Error, Sendable, Equatable {
    case invalidShortcut
    case conflict
    case systemFailure
    case serviceUnavailable

    public var stableCode: String {
        switch self {
        case .invalidShortcut: return "E_SHORTCUT_INVALID"
        case .conflict: return "E_SHORTCUT_CONFLICT"
        case .systemFailure: return "E_SHORTCUT_SYSTEM"
        case .serviceUnavailable: return "E_SHORTCUT_UNAVAILABLE"
        }
    }

    public var userDescription: String {
        switch self {
        case .invalidShortcut:
            return "快捷键无效,请使用至少一个修饰键加一个普通键。"
        case .conflict:
            return "该快捷键已被系统或其他应用占用。"
        case .systemFailure:
            return "注册快捷键时发生系统错误,请稍后重试。"
        case .serviceUnavailable:
            return "全局快捷键服务暂不可用。"
        }
    }
}
