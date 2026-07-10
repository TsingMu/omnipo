import Foundation

/// 默认微信存储分析服务:串联根解析与扫描,只读、可取消。
public final class DefaultWeChatStorageService: WeChatStorageService, @unchecked Sendable {
    private let resolver: WeChatStorageRootResolver
    private let scanner: WeChatStorageScanner
    private let lock = NSLock()
    private var cancelled = false

    public init(resolver: WeChatStorageRootResolver, scanner: WeChatStorageScanner) {
        self.resolver = resolver
        self.scanner = scanner
    }

    public func scan() async -> Result<WeChatStorageScanResult, AppError> {
        performScan(resetFirst: false)
    }

    public func refresh() async -> Result<WeChatStorageScanResult, AppError> {
        performScan(resetFirst: true)
    }

    public func cancel() async {
        setCancelled(true)
    }

    /// 扫描流程:可选先重置取消标志(用于 refresh 强制全新扫描),scanner 通过 closure
    /// 读取取消标志;扫描结束后清理,允许下一次 scan/refresh 正常进行。
    private func performScan(resetFirst: Bool) -> Result<WeChatStorageScanResult, AppError> {
        if resetFirst { setCancelled(false) }
        let isCancelled = { [weak self] in self?.isCancelledFlag() ?? false }
        let roots = resolver.resolve()
        let result = scanner.scan(roots: roots, isCancelled: isCancelled)
        setCancelled(false)
        return .success(result)
    }

    private func setCancelled(_ value: Bool) {
        lock.lock()
        cancelled = value
        lock.unlock()
    }

    private func isCancelledFlag() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
