import Foundation

public struct PermissionAuditQuery: Sendable, Hashable {
    public var searchText: String
    public var category: PermissionCategory?

    public init(searchText: String = "", category: PermissionCategory? = nil) {
        self.searchText = searchText
        self.category = category
    }
}

/// 权限审计服务协议。
///
/// 实现必须:
/// - 只读读取权限授权状态,不得读取相机/麦克风/通讯录/日历等隐私内容本身。
/// - 不修改 TCC 或任何系统授权记录。
/// - 显式区分“不可读取”和“未授权”,不得用空结果替代不可读取。
/// - 不记录应用路径、原始数据库行或其他敏感元数据到日志。
public protocol PermissionAuditService: AnyObject, Sendable {
    /// 执行一次全量本地权限审计。`query` 仅影响返回结果的过滤,不改变底层系统状态。
    func auditPermissions(matching query: PermissionAuditQuery) async -> Result<PermissionAuditResult, AppError>
}
