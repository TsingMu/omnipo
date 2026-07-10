import AppKit
import Foundation

/// 发现已安装微信的 bundle identifier,覆盖版本与渠道差异。
public protocol WeChatBundleIdentifierProviding: Sendable {
    func installedWeChatBundleIdentifier() -> String?
}

/// 默认实现:先以已知 bundle id 经 `NSWorkspace` 定位;失败则枚举 `/Applications`、`~/Applications`
/// 读取名为微信的 app 的 `bundleIdentifier`,覆盖 3.x / 4.0 / 渠道差异。
public struct SystemWeChatBundleIdentifierProvider: WeChatBundleIdentifierProviding {
    public init() {}

    public static let knownBundleIdentifiers = ["com.tencent.xinWeChat", "com.tencent.WeChat"]

    public func installedWeChatBundleIdentifier() -> String? {
        for bid in Self.knownBundleIdentifiers {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil {
                return bid
            }
        }
        return discoverByEnumeration()
    }

    private func discoverByEnumeration() -> String? {
        let fm = FileManager.default
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        for directory in directories {
            guard let entries = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appURL = directory.appendingPathComponent(entry)
                guard let bundle = Bundle(url: appURL),
                      let bid = bundle.bundleIdentifier,
                      Self.isWeChat(bundleID: bid, bundle: bundle) else { continue }
                return bid
            }
        }
        return nil
    }

    static func isWeChat(bundleID: String, bundle: Bundle) -> Bool {
        let lower = bundleID.lowercased()
        if lower.contains("tencent"), lower.contains("wechat") { return true }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? ""
        return name.lowercased().contains("wechat") || name == "微信"
    }
}

/// 生成微信存储候选 root。仅判断存在性与可读性,不遍历内容(由 `WeChatStorageScanner` 负责)。
public final class WeChatStorageRootResolver: @unchecked Sendable {
    public static let fallbackBundleIdentifier = "com.tencent.xinWeChat"

    private let bundleIDProvider: any WeChatBundleIdentifierProviding
    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(
        bundleIDProvider: any WeChatBundleIdentifierProviding = SystemWeChatBundleIdentifierProvider(),
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.bundleIDProvider = bundleIDProvider
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    /// 解析候选 root。missing 候选视为 absent(不返回);存在但不可读的 root 带 unavailable availability。
    public func resolve(
        bundleIdentifier override: String? = nil,
        userSelectedRoots: [URL] = []
    ) -> [WeChatStorageRoot] {
        let bid = override
            ?? bundleIDProvider.installedWeChatBundleIdentifier()
            ?? Self.fallbackBundleIdentifier

        var candidates = libraryCandidates(bid: bid)
        candidates.append(contentsOf: userSelectedRoots.map { ($0, WeChatStorageRootKind.userSelected) })

        var seen = Set<String>()
        var roots: [WeChatStorageRoot] = []
        var groupSerial = 0

        for candidate in candidates {
            let resolved = candidate.0.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(resolved.path).inserted else { continue }

            // missing 候选视为 absent,不返回也不报错。
            guard fileManager.fileExists(atPath: candidate.0.path) else { continue }

            roots.append(WeChatStorageRoot(
                url: resolved,
                kind: candidate.1,
                displayName: displayName(for: candidate.1, serial: &groupSerial),
                availability: availability(for: candidate.0)
            ))
        }
        return roots
    }

    // MARK: - Candidates

    private func libraryCandidates(bid: String) -> [(URL, WeChatStorageRootKind)] {
        let library = homeDirectory.appendingPathComponent("Library")
        var candidates: [(URL, WeChatStorageRootKind)] = [
            (library.appendingPathComponent("Containers/\(bid)"), .applicationContainer),
            (library.appendingPathComponent("Application Support/\(bid)"), .applicationSupport),
            (library.appendingPathComponent("Caches/\(bid)"), .cache)
        ]
        candidates.append(contentsOf: groupContainerCandidates(bid: bid, library: library))
        return candidates
    }

    private func groupContainerCandidates(bid: String, library: URL) -> [(URL, WeChatStorageRootKind)] {
        let groupDir = library.appendingPathComponent("Group Containers")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: groupDir.path) else { return [] }
        return entries
            .filter { $0.localizedCaseInsensitiveContains(bid) }
            .map { (groupDir.appendingPathComponent($0), .groupContainer) }
    }

    // MARK: - Availability

    private func availability(for url: URL) -> WeChatStorageAvailability {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .unavailable(.resourceUnavailable)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            return .unavailable(.permissionLimited)
        }
        // TCC/沙箱可能让 isReadable 为 true 但实际无法列举;用列举确认。
        guard (try? fileManager.contentsOfDirectory(atPath: url.path)) != nil else {
            return .unavailable(.tccOrSandboxLimited)
        }
        return .readable
    }

    // MARK: - Sanitized display name

    private func displayName(for kind: WeChatStorageRootKind, serial: inout Int) -> String {
        if kind == .groupContainer {
            serial += 1
            return "共享容器 \(serial)"
        }
        return kind.displayName
    }
}
