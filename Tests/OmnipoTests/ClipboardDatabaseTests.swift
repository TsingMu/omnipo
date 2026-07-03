import XCTest
@testable import Omnipo

final class ClipboardDatabaseTests: XCTestCase {

    func test_initialize_createsDatabaseAndPayloadDirectories() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = ClipboardStorageLocation(rootDirectory: root)

        let database = try ClipboardDatabase(location: location)
        try database.initialize()

        XCTAssertTrue(FileManager.default.fileExists(atPath: location.databaseURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.binaryPayloadsDirectory.path))
    }

    func test_initialize_createsVersionedSchemaTables() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try ClipboardDatabase(location: ClipboardStorageLocation(rootDirectory: root))

        try database.initialize()

        XCTAssertEqual(try database.currentSchemaVersion(), ClipboardDatabase.currentVersion)
        XCTAssertTrue(try database.tableExists("clipboard_schema_migrations"))
        XCTAssertTrue(try database.tableExists("clipboard_items"))
        XCTAssertTrue(try database.tableExists("clipboard_binary_payloads"))
    }

    func test_initialize_isIdempotent() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try ClipboardDatabase(location: ClipboardStorageLocation(rootDirectory: root))

        try database.initialize()
        try database.initialize()

        XCTAssertEqual(try database.currentSchemaVersion(), ClipboardDatabase.currentVersion)
    }

    func test_tableExists_returnsFalseForUnknownOrEmptyTable() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try ClipboardDatabase(location: ClipboardStorageLocation(rootDirectory: root))

        try database.initialize()

        XCTAssertFalse(try database.tableExists(""))
        XCTAssertFalse(try database.tableExists("missing_table"))
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-clipboard-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
