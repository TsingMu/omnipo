import Foundation

public struct AssociatedFileScanRoot: Sendable, Hashable {
    public let category: AssociatedFileCategory
    public let url: URL

    public init(category: AssociatedFileCategory, url: URL) {
        self.category = category
        self.url = url
    }
}

public struct AssociatedFileScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static func defaultRoots(
        forHomeDirectory home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [AssociatedFileScanRoot] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return [
            AssociatedFileScanRoot(category: .cache, url: library.appendingPathComponent("Caches", isDirectory: true)),
            AssociatedFileScanRoot(category: .applicationSupport, url: library.appendingPathComponent("Application Support", isDirectory: true)),
            AssociatedFileScanRoot(category: .preferences, url: library.appendingPathComponent("Preferences", isDirectory: true)),
            AssociatedFileScanRoot(category: .logs, url: library.appendingPathComponent("Logs", isDirectory: true)),
            AssociatedFileScanRoot(category: .savedApplicationState, url: library.appendingPathComponent("Saved Application State", isDirectory: true)),
            AssociatedFileScanRoot(category: .container, url: library.appendingPathComponent("Containers", isDirectory: true)),
            AssociatedFileScanRoot(category: .groupContainer, url: library.appendingPathComponent("Group Containers", isDirectory: true))
        ]
    }

    public func scan(
        for application: InstalledApplication,
        roots: [AssociatedFileScanRoot] = AssociatedFileScanner.defaultRoots()
    ) -> AssociatedFileScanResult {
        let matcher = AssociatedFileMatcher(application: application)
        var filesByPath: [String: AppAssociatedFile] = [:]
        var issues: [AssociatedFileScanIssue] = []

        for root in roots {
            let result = scan(root: root, matcher: matcher)
            for file in result.files {
                filesByPath[file.url.standardizedFileURL.path] = file
            }
            issues.append(contentsOf: result.issues)
        }

        return AssociatedFileScanResult(files: Array(filesByPath.values), issues: issues)
    }

    private func scan(
        root: AssociatedFileScanRoot,
        matcher: AssociatedFileMatcher
    ) -> AssociatedFileScanResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return AssociatedFileScanResult(
                files: [],
                issues: [AssociatedFileScanIssue(rootURL: root.url, category: root.category, reason: .resourceUnavailable)]
            )
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: root.url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AssociatedFileScanResult(
                files: [],
                issues: [AssociatedFileScanIssue(rootURL: root.url, category: root.category, reason: .permissionLimited)]
            )
        }

        let files = entries.compactMap { url in
            makeAssociatedFile(url: url, category: root.category, matcher: matcher)
        }
        return AssociatedFileScanResult(files: files)
    }

    private func makeAssociatedFile(
        url: URL,
        category: AssociatedFileCategory,
        matcher: AssociatedFileMatcher
    ) -> AppAssociatedFile? {
        guard let match = matcher.match(url: url, category: category) else {
            return nil
        }

        let sensitiveReason = highSensitivityReason(for: url)
        let unavailableReason = sensitiveReason ?? unavailableReason(for: category, match: match)
        let riskLevel = riskLevel(for: category, match: match, unavailableReason: unavailableReason)

        return AppAssociatedFile(
            category: category,
            displayName: url.lastPathComponent,
            url: url,
            sizeBytes: sizeBytes(at: url),
            ownershipConfidence: unavailableReason == .ownershipUnclear ? .unavailable : match.confidence,
            riskLevel: riskLevel,
            unavailableReason: unavailableReason
        )
    }

    private func unavailableReason(
        for category: AssociatedFileCategory,
        match: AssociatedFileMatcher.Match
    ) -> AssociatedFileUnavailableReason? {
        if category == .groupContainer && match.confidence != .high {
            return .ownershipUnclear
        }
        return nil
    }

    private func riskLevel(
        for category: AssociatedFileCategory,
        match: AssociatedFileMatcher.Match,
        unavailableReason: AssociatedFileUnavailableReason?
    ) -> AssociatedFileRiskLevel {
        if unavailableReason != nil {
            return .high
        }
        if category == .groupContainer || category == .launchAgent {
            return .high
        }
        switch match.confidence {
        case .high:
            return category == .applicationSupport || category == .container ? .medium : .low
        case .medium:
            return .medium
        case .low, .unavailable:
            return .high
        }
    }

    private func highSensitivityReason(for url: URL) -> AssociatedFileUnavailableReason? {
        if containsHighSensitivityComponent(in: url.standardizedFileURL.pathComponents) {
            return .highSensitivity
        }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true,
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return nil
        }

        for case let childURL as URL in enumerator {
            if containsHighSensitivityComponent(in: childURL.standardizedFileURL.pathComponents) {
                return .highSensitivity
            }
        }
        return nil
    }

    private func containsHighSensitivityComponent(in pathComponents: [String]) -> Bool {
        let lowerComponents = pathComponents.map { $0.lowercased() }
        let sensitiveNames: Set<String> = [
            "keychains",
            "messages",
            "chat.db",
            "safari",
            "firefox",
            "google",
            "chrome",
            "profiles",
            "cookies"
        ]
        if lowerComponents.contains(where: { sensitiveNames.contains($0) }) {
            return true
        }
        return false
    }

    private func sizeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey])
        if values?.isRegularFile == true {
            return Int64(values?.fileSize ?? 0)
        }

        guard values?.isDirectory == true,
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return 0
        }

        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            guard let childValues = try? childURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  childValues.isRegularFile == true else {
                continue
            }
            total += Int64(childValues.fileSize ?? 0)
        }
        return max(0, total)
    }
}

private struct AssociatedFileMatcher {
    struct Match {
        let confidence: OwnershipConfidence
    }

    private let bundleIdentifier: String?
    private let exactNameKeys: Set<String>
    private let containsNameKeys: Set<String>

    init(application: InstalledApplication) {
        bundleIdentifier = application.bundleIdentifier?.lowercased()
        var names: [String] = [
            application.displayName,
            application.localizedDisplayName,
            application.executableURL?.deletingPathExtension().lastPathComponent,
            application.bundleURL.deletingPathExtension().lastPathComponent
        ].compactMap { $0 }

        if let executable = application.executableURL?.lastPathComponent {
            names.append(executable)
        }

        exactNameKeys = Set(names.compactMap { $0.associatedScannerKey })
        containsNameKeys = Set(exactNameKeys.filter { $0.count >= 3 })
    }

    func match(url: URL, category: AssociatedFileCategory) -> Match? {
        let components = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let last = url.lastPathComponent.lowercased()
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()

        if let bundleIdentifier,
           components.contains(bundleIdentifier)
            || last == bundleIdentifier
            || stem == bundleIdentifier
            || last == "\(bundleIdentifier).plist"
            || last == "\(bundleIdentifier).savedstate" {
            return Match(confidence: .high)
        }

        let comparableComponents = Set(components.compactMap { $0.associatedScannerKey })
            .union([last.associatedScannerKey, stem.associatedScannerKey].compactMap { $0 })
        if !exactNameKeys.isDisjoint(with: comparableComponents) {
            return Match(confidence: .medium)
        }

        let haystack = components.joined(separator: "/").associatedScannerKey ?? ""
        if containsNameKeys.contains(where: { haystack.contains($0) }) {
            return Match(confidence: .low)
        }

        return nil
    }
}

private extension String {
    var associatedScannerKey: String? {
        let normalized = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return compact.isEmpty ? nil : compact
    }
}
