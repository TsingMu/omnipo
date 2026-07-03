import AppKit
import Foundation

public protocol ClipboardSourceApplicationProviding: AnyObject, Sendable {
    func sourceApplicationID() throws -> String?
}

public final class SystemClipboardSourceApplicationProvider: ClipboardSourceApplicationProviding, @unchecked Sendable {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func sourceApplicationID() throws -> String? {
        workspace.frontmostApplication?.bundleIdentifier
    }
}
