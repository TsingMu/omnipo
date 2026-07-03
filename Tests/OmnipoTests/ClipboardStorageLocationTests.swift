import XCTest
@testable import Omnipo

final class ClipboardStorageLocationTests: XCTestCase {

    func test_paths_areDerivedFromRootDirectory() {
        let root = URL(fileURLWithPath: "/tmp/omnipo-clipboard-test", isDirectory: true)
        let location = ClipboardStorageLocation(rootDirectory: root)

        XCTAssertEqual(location.databaseURL.lastPathComponent, "Clipboard.sqlite")
        XCTAssertEqual(location.databaseURL.deletingLastPathComponent(), root)
        XCTAssertEqual(location.binaryPayloadsDirectory.lastPathComponent, "Payloads")
        XCTAssertEqual(location.binaryPayloadsDirectory.deletingLastPathComponent(), root)
    }

    func test_prepare_createsRootAndPayloadDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-clipboard-storage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let location = ClipboardStorageLocation(rootDirectory: root)
        try location.prepare()

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: location.binaryPayloadsDirectory.path,
            isDirectory: &isDirectory
        ))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.databaseURL.path))
    }

    func test_applicationSupportLocation_usesBundleNamespaceAndClipboardLeaf() throws {
        let location = try ClipboardStorageLocation.applicationSupport(
            bundleIdentifier: "com.example.TestHost"
        )

        XCTAssertEqual(location.rootDirectory.lastPathComponent, "Clipboard")
        XCTAssertEqual(
            location.rootDirectory.deletingLastPathComponent().lastPathComponent,
            "com.example.TestHost"
        )
    }
}
