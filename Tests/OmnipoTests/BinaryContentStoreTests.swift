import XCTest
@testable import Omnipo

final class BinaryContentStoreTests: XCTestCase {

    func test_write_createsFileAndReturnsRelativePath() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = UUID()
        let path = try store.write(Data([0x89, 0x50, 0x4E, 0x47]), for: id, format: .image)

        XCTAssertEqual(path, "\(id.uuidString).image")
        XCTAssertTrue(store.exists(path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.resolveURL(path).path))
    }

    func test_write_createsRootDirectoryIfMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-bin-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BinaryContentStore(rootDirectory: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        _ = try store.write(Data([1, 2, 3]), for: UUID(), format: .rtf)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func test_read_returnsWrittenBytes() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let path = try store.write(Data("hello".utf8), for: UUID(), format: .html)
        XCTAssertEqual(try store.read(path), Data("hello".utf8))
    }

    func test_write_overwritesSameRecordAndFormat() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()

        let first = try store.write(Data([1, 1, 1]), for: id, format: .image)
        let second = try store.write(Data([2, 2, 2, 2]), for: id, format: .image)

        XCTAssertEqual(first, second)
        XCTAssertEqual(try store.read(first), Data([2, 2, 2, 2]))
    }

    func test_delete_removesFile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try store.write(Data([9]), for: UUID(), format: .rtf)

        try store.delete(path)
        XCTAssertFalse(store.exists(path))
    }

    func test_delete_missingFileSucceeds() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try store.delete("missing.rtf"))
    }

    func test_read_rejectsPathTraversal() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try store.read("../outside.rtf")) { error in
            XCTAssertEqual(error as? AppError, .invalidArgument(name: "storagePath"))
        }
        XCTAssertThrowsError(try store.read("/tmp/outside.rtf")) { error in
            XCTAssertEqual(error as? AppError, .invalidArgument(name: "storagePath"))
        }
    }

    func test_delete_rejectsPathTraversalAndDoesNotTouchOutsideFile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).rtf")
        try Data([7]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        XCTAssertThrowsError(try store.delete("../\(outside.lastPathComponent)")) { error in
            XCTAssertEqual(error as? AppError, .invalidArgument(name: "storagePath"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func test_exists_returnsFalseForUnsafePath() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(store.exists("../outside.rtf"))
        XCTAssertFalse(store.exists("/tmp/outside.rtf"))
        XCTAssertFalse(store.exists("nested/file.rtf"))
    }

    func test_deleteAll_removesAllFormatsForRecordKeepingOthers() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let other = UUID()

        let rtf = try store.write(Data([1]), for: id, format: .rtf)
        let html = try store.write(Data([2]), for: id, format: .html)
        let image = try store.write(Data([3]), for: id, format: .image)
        let otherPath = try store.write(Data([4]), for: other, format: .rtf)

        try store.deleteAll(for: id)

        XCTAssertFalse(store.exists(rtf))
        XCTAssertFalse(store.exists(html))
        XCTAssertFalse(store.exists(image))
        XCTAssertTrue(store.exists(otherPath))
    }

    private func makeStore() throws -> (BinaryContentStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-bin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (BinaryContentStore(rootDirectory: root), root)
    }
}
