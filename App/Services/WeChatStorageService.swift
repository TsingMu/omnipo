import Foundation

/// 微信存储分析服务:只读、元数据扫描,不解析内容,不删除。
public protocol WeChatStorageService: AnyObject, Sendable {
    /// 执行一次本地微信存储扫描,返回分类汇总、top groups、roots 与 issues。
    func scan() async -> Result<WeChatStorageScanResult, AppError>

    /// 用户触发刷新:重新扫描并返回最新结果。
    func refresh() async -> Result<WeChatStorageScanResult, AppError>

    /// 取消正在进行的扫描或刷新。best-effort,不抛错。
    func cancel() async
}
