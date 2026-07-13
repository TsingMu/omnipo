import AppKit
import Foundation

public enum LargeFileRevealFailure: String, Sendable, Equatable, CaseIterable {
    case staleResult
    case outsideAuthorizedRoot
    case missingItem
    case authorizationUnavailable
    case unexpected

    public var stableCode: String {
        switch self {
        case .staleResult: return "LARGE_FILE_REVEAL_STALE_RESULT"
        case .outsideAuthorizedRoot: return "LARGE_FILE_REVEAL_OUTSIDE_ROOT"
        case .missingItem: return "LARGE_FILE_REVEAL_MISSING"
        case .authorizationUnavailable: return "LARGE_FILE_REVEAL_AUTH_UNAVAILABLE"
        case .unexpected: return "LARGE_FILE_REVEAL_UNEXPECTED"
        }
    }

    public var userDescription: String {
        switch self {
        case .staleResult: return "扫描结果已更新，请重新选择文件。"
        case .outsideAuthorizedRoot: return "该项目不再位于当前授权范围内。"
        case .missingItem: return "该项目可能已移动或删除，请刷新目录分析。"
        case .authorizationUnavailable: return "目录授权不可用，请重新授权后再试。"
        case .unexpected: return "Finder 暂时无法定位该项目，请稍后重试。"
        }
    }
}

public enum LargeFileRevealResult: Sendable, Equatable {
    case success
    case failure(LargeFileRevealFailure)

    public var stableCode: String {
        switch self {
        case .success: return "LARGE_FILE_REVEAL_OK"
        case .failure(let failure): return failure.stableCode
        }
    }

    public var userDescription: String {
        switch self {
        case .success: return "已请求 Finder 定位该项目。"
        case .failure(let failure): return failure.userDescription
        }
    }
}

/// SwiftUI 与 `NSWorkspace` 之间最小的只读 AppKit 边界。
@MainActor
public final class LargeFileRevealService {
    private let rootManager: AuthorizedRootManager
    private let fileExists: (String) -> Bool
    private let revealInFinder: ([URL]) throws -> Void
    private let logger: (any LoggingService)?

    public convenience init(
        rootManager: AuthorizedRootManager,
        logger: (any LoggingService)? = nil
    ) {
        self.init(
            rootManager: rootManager,
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            revealInFinder: { NSWorkspace.shared.activateFileViewerSelecting($0) },
            logger: logger
        )
    }

    init(
        rootManager: AuthorizedRootManager,
        fileExists: @escaping (String) -> Bool,
        revealInFinder: @escaping ([URL]) throws -> Void,
        logger: (any LoggingService)? = nil
    ) {
        self.rootManager = rootManager
        self.fileExists = fileExists
        self.revealInFinder = revealInFinder
        self.logger = logger
    }

    public func reveal(
        record: LargeFileRecord,
        currentRecords: [LargeFileRecord]
    ) -> LargeFileRevealResult {
        guard currentRecords.contains(where: {
            $0.id == record.id && $0.displayPath == record.displayPath
        }) else {
            return finish(.failure(.staleResult))
        }

        guard let rootURL = rootManager.currentRoot() else {
            rootManager.releaseRoot()
            return finish(.failure(.authorizationUnavailable))
        }
        defer { rootManager.releaseRoot() }

        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let targetURL = URL(fileURLWithPath: record.displayPath)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard Self.contains(targetURL, within: resolvedRoot) else {
            return finish(.failure(.outsideAuthorizedRoot))
        }
        guard fileExists(targetURL.path) else {
            return finish(.failure(.missingItem))
        }

        do {
            try revealInFinder([targetURL])
            return finish(.success)
        } catch {
            return finish(.failure(.unexpected))
        }
    }

    private static func contains(_ target: URL, within root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let targetComponents = target.pathComponents
        return targetComponents.count > rootComponents.count
            && Array(targetComponents.prefix(rootComponents.count)) == rootComponents
    }

    private func finish(_ result: LargeFileRevealResult) -> LargeFileRevealResult {
        logger?.log(LogEvent(
            level: result == .success ? .info : .warning,
            category: .application,
            message: "disk.analysis.reveal",
            stableCode: result.stableCode,
            sanitizedContext: ["result": result.stableCode]
        ))
        return result
    }
}
