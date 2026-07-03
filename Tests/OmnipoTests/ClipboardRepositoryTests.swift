import XCTest
@testable import Omnipo

final class ClipboardRepositoryTests: XCTestCase {

    func test_insert_persistsRecordAndIsRetrievable() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = ClipboardItem(
            contentHash: "hash-1",
            contentType: .plainText,
            textPreview: "hello",
            sourceApplicationID: "com.example.app"
        )
        let inserted = try repo.insert(item)

        XCTAssertEqual(inserted.contentHash, "hash-1")
        let records = try repo.records(matching: ClipboardQuery())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.contentHash, "hash-1")
        XCTAssertEqual(records.first?.contentType, .plainText)
        XCTAssertEqual(records.first?.textPreview, "hello")
        XCTAssertEqual(records.first?.sourceApplicationID, "com.example.app")
        XCTAssertFalse(records.first?.isFavorite ?? true)
        XCTAssertFalse(records.first?.isDeleted ?? true)
        XCTAssertEqual(records.first?.timesUsed, 1)
    }

    func test_insert_updatesDuplicateContentHashWithoutDuplicating() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = self.item(
            hash: "dup",
            type: .plainText,
            preview: "first",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let second = self.item(
            hash: "dup",
            type: .html,
            preview: "second",
            updatedAt: Date(timeIntervalSince1970: 200),
            timesUsed: 2
        )

        let inserted = try repo.insert(first)
        let updated = try repo.insert(second)

        XCTAssertEqual(updated.id, inserted.id)
        XCTAssertEqual(try repo.count(), 1)
        let records = try repo.records(matching: ClipboardQuery())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.textPreview, "second")
        XCTAssertEqual(records.first?.contentType, .html)
        XCTAssertEqual(records.first?.timesUsed, 3)
        XCTAssertEqual(records.first?.updatedAt, Date(timeIntervalSince1970: 200))
    }

    func test_insert_duplicateRevivesSoftDeletedRecord() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try repo.insert(item(hash: "dup", preview: "deleted"))
        try repo.softDelete(first.id)

        let revived = try repo.insert(item(hash: "dup", preview: "revived"))

        XCTAssertEqual(revived.id, first.id)
        XCTAssertFalse(revived.isDeleted)
        XCTAssertEqual(revived.textPreview, "revived")
        XCTAssertEqual(try repo.count(), 1)
    }

    func test_records_ordersByUpdatedAtDescending() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try repo.insert(item(hash: "old", updatedAt: Date(timeIntervalSince1970: 100)))
        try repo.insert(item(hash: "new", updatedAt: Date(timeIntervalSince1970: 300)))
        try repo.insert(item(hash: "mid", updatedAt: Date(timeIntervalSince1970: 200)))

        let hashes = try repo.records(matching: ClipboardQuery()).map(\.contentHash)
        XCTAssertEqual(hashes, ["new", "mid", "old"])
    }

    func test_records_appliesPagination() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<5 {
            try repo.insert(item(hash: "h\(index)", updatedAt: Date(timeIntervalSince1970: Double(index))))
        }

        let firstPage = try repo.records(matching: ClipboardQuery(limit: 2, offset: 0))
        let secondPage = try repo.records(matching: ClipboardQuery(limit: 2, offset: 2))

        XCTAssertEqual(firstPage.map(\.contentHash), ["h4", "h3"])
        XCTAssertEqual(secondPage.map(\.contentHash), ["h2", "h1"])
    }

    func test_records_filtersByContentType() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try repo.insert(item(hash: "text", type: .plainText, preview: "a"))
        try repo.insert(item(hash: "html", type: .html, preview: "b"))
        try repo.insert(item(hash: "image", type: .image, preview: nil))

        let htmlOnly = try repo.records(matching: ClipboardQuery(contentType: .html))
        XCTAssertEqual(htmlOnly.map(\.contentHash), ["html"])
    }

    func test_records_filtersFavoritesOnly() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try repo.insert(item(hash: "fav", favorite: true))
        try repo.insert(item(hash: "plain", favorite: false))

        let favorites = try repo.records(matching: ClipboardQuery(favoritesOnly: true))
        XCTAssertEqual(favorites.map(\.contentHash), ["fav"])
    }

    func test_records_excludesSoftDeletedUnlessRequested() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try repo.insert(item(hash: "alive"))
        let deleted = try repo.insert(item(hash: "gone"))
        try repo.softDelete(deleted.id)

        let visible = try repo.records(matching: ClipboardQuery())
        XCTAssertEqual(visible.map(\.contentHash), ["alive"])

        let includingDeleted = try repo.records(matching: ClipboardQuery(includeDeleted: true))
        XCTAssertEqual(Set(includingDeleted.map(\.contentHash)), ["alive", "gone"])
        XCTAssertTrue(includingDeleted.first(where: { $0.contentHash == "gone" })?.isDeleted ?? false)
    }

    func test_records_searchesByTextPreview() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try repo.insert(item(hash: "a", preview: "hello world"))
        try repo.insert(item(hash: "b", preview: "goodbye"))
        try repo.insert(item(hash: "c", preview: nil))

        let matches = try repo.records(matching: ClipboardQuery(searchText: "hello"))
        XCTAssertEqual(matches.map(\.contentHash), ["a"])
    }

    func test_setFavorite_togglesAndReportsHit() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try repo.insert(self.item(hash: "x"))

        XCTAssertTrue(try repo.setFavorite(true, for: item.id))
        XCTAssertTrue(try repo.records(matching: ClipboardQuery()).first?.isFavorite ?? false)

        XCTAssertTrue(try repo.setFavorite(false, for: item.id))
        XCTAssertFalse(try repo.records(matching: ClipboardQuery()).first?.isFavorite ?? true)

        XCTAssertFalse(try repo.setFavorite(true, for: UUID()))
    }

    func test_setFavorite_doesNotAffectSoftDeleted() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try repo.insert(self.item(hash: "x"))
        try repo.softDelete(item.id)

        XCTAssertFalse(try repo.setFavorite(true, for: item.id))
    }

    func test_softDelete_marksAndReportsHit() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try repo.insert(self.item(hash: "x"))

        XCTAssertTrue(try repo.softDelete(item.id))
        XCTAssertFalse(try repo.softDelete(item.id))
        XCTAssertFalse(try repo.softDelete(UUID()))

        XCTAssertEqual(try repo.count(), 0)
        XCTAssertEqual(try repo.count(includeDeleted: true), 1)
    }

    func test_count_reflectsVisibleAndDeletedTotals() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        try repo.insert(item(hash: "a"))
        try repo.insert(item(hash: "b"))
        let toDelete = try repo.insert(item(hash: "c"))
        try repo.softDelete(toDelete.id)

        XCTAssertEqual(try repo.count(), 2)
        XCTAssertEqual(try repo.count(includeDeleted: true), 3)
    }

    // MARK: - Binary Payloads

    func test_insertPayload_persistsAndRetrieves() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try repo.insert(self.item(hash: "h"))

        let payload = ClipboardBinaryPayload(recordID: item.id, format: .rtf, storagePath: "a.rtf", fileSize: 12)
        XCTAssertNotNil(try repo.insertPayload(payload))

        let stored = try repo.payloads(for: item.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.format, .rtf)
        XCTAssertEqual(stored.first?.storagePath, "a.rtf")
        XCTAssertEqual(stored.first?.fileSize, 12)
    }

    func test_insertPayload_supportsMultipleFormatsPerRecord() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try repo.insert(self.item(hash: "h"))

        XCTAssertNotNil(try repo.insertPayload(.init(recordID: item.id, format: .rtf, storagePath: "a.rtf", fileSize: 1)))
        XCTAssertNotNil(try repo.insertPayload(.init(recordID: item.id, format: .html, storagePath: "a.html", fileSize: 2)))

        XCTAssertEqual(Set(try repo.payloads(for: item.id).map(\.format)), [.rtf, .html])
    }

    func test_insertPayload_returnsNilForDuplicateFormat() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try repo.insert(self.item(hash: "h"))

        let payload = ClipboardBinaryPayload(recordID: item.id, format: .rtf, storagePath: "a.rtf", fileSize: 1)
        XCTAssertNotNil(try repo.insertPayload(payload))
        XCTAssertNil(try repo.insertPayload(payload))
        XCTAssertEqual(try repo.payloads(for: item.id).count, 1)
    }

    func test_insertPayload_returnsNilWhenRecordMissing() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = ClipboardBinaryPayload(recordID: UUID(), format: .rtf, storagePath: "a.rtf", fileSize: 1)
        XCTAssertNil(try repo.insertPayload(payload))
    }

    func test_deletePayloads_removesAllForRecord() throws {
        let (repo, root) = try makeRepo()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = try repo.insert(self.item(hash: "h"))
        try repo.insertPayload(.init(recordID: item.id, format: .rtf, storagePath: "a.rtf", fileSize: 1))
        try repo.insertPayload(.init(recordID: item.id, format: .html, storagePath: "a.html", fileSize: 2))

        XCTAssertEqual(try repo.deletePayloads(for: item.id), 2)
        XCTAssertTrue(try repo.payloads(for: item.id).isEmpty)
        XCTAssertEqual(try repo.deletePayloads(for: item.id), 0)
    }

    // MARK: - Helpers

    private func makeRepo() throws -> (ClipboardRepository, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-clipboard-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try ClipboardDatabase(location: ClipboardStorageLocation(rootDirectory: root))
        try database.initialize()
        return (ClipboardRepository(database: database), root)
    }

    private func item(
        hash: String,
        type: ClipboardContentType = .plainText,
        preview: String? = "preview",
        favorite: Bool = false,
        updatedAt: Date = Date(),
        timesUsed: Int = 1
    ) -> ClipboardItem {
        ClipboardItem(
            contentHash: hash,
            contentType: type,
            textPreview: preview,
            isFavorite: favorite,
            timesUsed: timesUsed,
            updatedAt: updatedAt
        )
    }
}
