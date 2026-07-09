import AppKit
import Foundation

public struct InstalledApplicationScanner {
    public typealias RunningApplicationProvider = @Sendable () async -> Set<String>
    public typealias SystemProtectionEvaluator = @Sendable (URL) -> Bool

    public static let defaultSearchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
    ]

    private let fileManager: FileManager
    private let runningApplicationProvider: RunningApplicationProvider
    private let systemProtectionEvaluator: SystemProtectionEvaluator

    public init(
        fileManager: FileManager = .default,
        runningApplicationProvider: @escaping RunningApplicationProvider = {
            await MainActor.run {
                Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            }
        },
        systemProtectionEvaluator: @escaping SystemProtectionEvaluator = InstalledApplicationScanner.defaultSystemProtectionEvaluator
    ) {
        self.fileManager = fileManager
        self.runningApplicationProvider = runningApplicationProvider
        self.systemProtectionEvaluator = systemProtectionEvaluator
    }

    public func scan(roots: [URL] = defaultSearchRoots) async -> InstalledApplicationScanResult {
        let runningBundleIdentifiers = await runningApplicationProvider()
        var applicationsByIdentity: [String: InstalledApplication] = [:]
        var issues: [InstalledApplicationScanIssue] = []

        for root in roots {
            let result = scan(root: root, runningBundleIdentifiers: runningBundleIdentifiers)
            for application in result.applications {
                let identity = application.bundleIdentifier ?? application.bundleURL.path
                if let existing = applicationsByIdentity[identity] {
                    applicationsByIdentity[identity] = preferredApplication(existing, application)
                } else {
                    applicationsByIdentity[identity] = application
                }
            }
            issues.append(contentsOf: result.issues)
        }

        return InstalledApplicationScanResult(
            applications: Array(applicationsByIdentity.values),
            issues: issues
        )
    }

    private func scan(
        root: URL,
        runningBundleIdentifiers: Set<String>
    ) -> InstalledApplicationScanResult {
        guard root.hasDirectoryPath || root.pathExtension.isEmpty else {
            return InstalledApplicationScanResult(
                applications: [],
                issues: [InstalledApplicationScanIssue(rootURL: root, reason: .resourceUnavailable)]
            )
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return InstalledApplicationScanResult(
                applications: [],
                issues: [InstalledApplicationScanIssue(rootURL: root, reason: .resourceUnavailable)]
            )
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return InstalledApplicationScanResult(
                applications: [],
                issues: [InstalledApplicationScanIssue(rootURL: root, reason: .permissionLimited)]
            )
        }

        var applications: [InstalledApplication] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            guard let application = makeApplication(
                bundleURL: url,
                root: root,
                runningBundleIdentifiers: runningBundleIdentifiers
            ) else {
                continue
            }
            applications.append(application)
        }

        return InstalledApplicationScanResult(applications: applications)
    }

    private func makeApplication(
        bundleURL: URL,
        root: URL,
        runningBundleIdentifiers: Set<String>
    ) -> InstalledApplication? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }

        guard let bundleIdentifier = bundle.bundleIdentifier?.omnipoNonEmptyValue else {
            return nil
        }
        let localizedDisplayName = bundle.omnipoDisplayName
        let rawInfo = bundle.infoDictionary ?? [:]
        let displayName = localizedDisplayName
            ?? (rawInfo["CFBundleDisplayName"] as? String)?.omnipoNonEmptyValue
            ?? (rawInfo["CFBundleName"] as? String)?.omnipoNonEmptyValue
            ?? bundle.executableURL?.lastPathComponent.omnipoNonEmptyValue
            ?? bundleURL.deletingPathExtension().lastPathComponent

        return InstalledApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            localizedDisplayName: localizedDisplayName,
            bundleURL: bundleURL,
            executableURL: bundle.executableURL,
            iconIdentifier: bundleIdentifier,
            bundleSizeBytes: bundleSizeBytes(at: bundleURL),
            source: source(for: root),
            isSystemProtected: systemProtectionEvaluator(bundleURL),
            isRunning: runningBundleIdentifiers.contains(bundleIdentifier)
        )
    }

    private func bundleSizeBytes(at bundleURL: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return max(0, total)
    }

    private func source(for root: URL) -> ApplicationInstallSource {
        let path = root.standardizedFileURL.path
        if path == "/Applications" {
            return .applications
        }
        if path == "/System/Applications" {
            return .systemApplications
        }
        if path == "/System/Library/CoreServices" {
            return .coreServices
        }
        if path == URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path {
            return .userApplications
        }
        return .other
    }

    public static func defaultSystemProtectionEvaluator(_ bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        return path.hasPrefix("/System/")
            || path.hasPrefix("/Library/Apple/System/")
            || path == "/Applications/Safari.app"
    }

    private func preferredApplication(
        _ lhs: InstalledApplication,
        _ rhs: InstalledApplication
    ) -> InstalledApplication {
        if lhs.source == .applications && rhs.source != .applications {
            return lhs
        }
        if rhs.source == .applications && lhs.source != .applications {
            return rhs
        }
        if !lhs.isSystemProtected && rhs.isSystemProtected {
            return lhs
        }
        if !rhs.isSystemProtected && lhs.isSystemProtected {
            return rhs
        }
        return lhs.bundleURL.path.count <= rhs.bundleURL.path.count ? lhs : rhs
    }
}
