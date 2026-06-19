import Foundation
import AppKit

/// 应用记录的可发送值表示。
public struct AppRecord: Sendable, Hashable {
    public let bundleIdentifier: String
    public let displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}

/// 用系统公开文件 API 枚举已安装应用。
///
/// 不递归遍历整个文件系统;只扫描系统公开的应用目录:
/// `/Applications`、`/System/Applications`、`/System/Library/CoreServices`。
/// Sandbox 内可读这些路径。
public enum SystemApplicationDiscovery {

    public static let defaultSearchPaths: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Library/CoreServices")
    ]

    public static func discover(in paths: [URL] = defaultSearchPaths) async -> [AppRecord] {
        await withTaskGroup(of: [AppRecord].self) { group in
            for path in paths {
                let captured = path
                group.addTask {
                    scan(captured)
                }
            }
            var all: [AppRecord] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }
    }

    private static func scan(_ root: URL) -> [AppRecord] {
        let fileManager = FileManager.default
        var results: [AppRecord] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? bundleId
            results.append(AppRecord(bundleIdentifier: bundleId, displayName: name))
        }
        return results
    }
}
