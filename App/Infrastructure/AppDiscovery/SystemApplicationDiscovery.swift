import Foundation
import AppKit

/// 应用记录的可发送值表示。
public struct AppRecord: Sendable, Hashable {
    public let bundleIdentifier: String
    public let displayName: String
    public let aliases: [String]
    public let searchCandidates: [String]
    public let searchCandidateForms: [SearchMatcher.CandidateForms]

    public init(
        bundleIdentifier: String,
        displayName: String,
        aliases: [String] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        let builtAliases = ApplicationSearchAliasBuilder.makeAliases(
            displayName: displayName,
            explicitAliases: aliases
        )
        let candidates = [displayName, bundleIdentifier] + builtAliases
        self.aliases = builtAliases
        self.searchCandidates = candidates
        self.searchCandidateForms = SearchMatcher.preparedCandidates(for: candidates)
    }
}

/// 在应用发现阶段生成稳定的本地搜索别名，避免每次按键重复做中文转写。
enum ApplicationSearchAliasBuilder {
    static func makeAliases(displayName: String, explicitAliases: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = SearchMatcher.normalize(trimmed)
            guard !key.isEmpty, key != SearchMatcher.normalize(displayName), seen.insert(key).inserted else {
                return
            }
            result.append(trimmed)
        }

        for alias in explicitAliases {
            append(alias)
        }

        if containsHanCharacters(displayName),
           let mandarin = displayName.applyingTransform(.mandarinToLatin, reverse: false),
           let withoutDiacritics = mandarin.applyingTransform(.stripDiacritics, reverse: false) {
            let fullPinyin = SearchMatcher.normalize(withoutDiacritics)
            append(fullPinyin)

            let compactPinyin = SearchMatcher.forms(for: fullPinyin).last ?? fullPinyin
            append(compactPinyin)

            let initials = fullPinyin
                .split(separator: " ")
                .compactMap(\.first)
                .map(String.init)
                .joined()
            append(initials)
        }

        return result
    }

    private static func containsHanCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x20000...0x2A6DF, 0x2A700...0x2EBEF:
                return true
            default:
                return false
            }
        }
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
            let rawInfo = bundle.infoDictionary ?? [:]
            let discoveredNames = [
                bundle.omnipoDisplayName,
                rawInfo["CFBundleDisplayName"] as? String,
                rawInfo["CFBundleName"] as? String,
                bundle.executableURL?.lastPathComponent,
                url.deletingPathExtension().lastPathComponent
            ].compactMap { $0 } + localizedBundleNames(in: url)
            let name = discoveredNames.first ?? bundleId
            results.append(AppRecord(
                bundleIdentifier: bundleId,
                displayName: name,
                aliases: Array(discoveredNames.dropFirst())
            ))
        }
        return results
    }

    private static func localizedBundleNames(in appURL: URL) -> [String] {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        guard let resourceEntries = try? FileManager.default.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var names: [String] = []
        for lprojURL in resourceEntries where lprojURL.pathExtension == "lproj" {
            let stringsURL = lprojURL.appendingPathComponent("InfoPlist.strings")
            guard let dictionary = NSDictionary(contentsOf: stringsURL) as? [String: Any] else {
                continue
            }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                guard let value = dictionary[key] as? String else { continue }
                names.append(value)
            }
        }
        return names
    }
}
