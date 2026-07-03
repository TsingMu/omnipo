import Foundation

public struct ClipboardStorageLocation: Sendable, Hashable {
    public let rootDirectory: URL

    public var databaseURL: URL {
        rootDirectory.appendingPathComponent("Clipboard.sqlite", isDirectory: false)
    }

    public var binaryPayloadsDirectory: URL {
        rootDirectory.appendingPathComponent("Payloads", isDirectory: true)
    }

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static func applicationSupport(
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.omnipo.app"
    ) throws -> ClipboardStorageLocation {
        guard let baseURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppError.resourceUnavailable(reason: "application_support_directory")
        }

        return ClipboardStorageLocation(
            rootDirectory: baseURL
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("Clipboard", isDirectory: true)
        )
    }

    public func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: binaryPayloadsDirectory,
            withIntermediateDirectories: true
        )
    }
}
