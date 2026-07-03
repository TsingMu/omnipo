import XCTest
@testable import Omnipo

final class ClipboardPasteControllerTests: XCTestCase {

    func test_copyToPasteboard_writesStoredPayloadsUsingItemContentType() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = try fixture.insertItem(type: .plainText, payloads: [
            .init(format: .plainText, data: Data("hello".utf8))
        ])

        let result = fixture.controller.copyToPasteboard(item.id)

        guard case .success = result else {
            return XCTFail("Expected copy to succeed, got \(result)")
        }
        XCTAssertEqual(fixture.writer.writes.count, 1)
        XCTAssertEqual(fixture.writer.writes.first?.contentType, .plainText)
        XCTAssertEqual(fixture.writer.writes.first?.payloads, [
            ClipboardCapturedPayload(format: .plainText, data: Data("hello".utf8))
        ])
        XCTAssertEqual(fixture.pastePerformer.performCount, 0)
    }

    func test_copyToPasteboard_missingItemReturnsFailure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = fixture.controller.copyToPasteboard(UUID())

        guard case .failure(.resourceUnavailable(reason: "clipboard-item-missing")) = result else {
            return XCTFail("Expected missing-item failure, got \(result)")
        }
        XCTAssertTrue(fixture.writer.writes.isEmpty)
    }

    func test_copyAndPaste_copiesOnlyWhenAccessibilityPermissionMissing() throws {
        let fixture = try makeFixture(accessibilityTrusted: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = try fixture.insertItem(type: .plainText, payloads: [
            .init(format: .plainText, data: Data("hello".utf8))
        ])

        let result = fixture.controller.copyAndPaste(item.id)

        XCTAssertEqual(result, .success(.copiedOnly(reason: "accessibility-permission-missing")))
        XCTAssertEqual(fixture.writer.writes.count, 1)
        XCTAssertEqual(fixture.pastePerformer.performCount, 0)
    }

    func test_copyAndPaste_performsSyntheticPasteWhenPermissionAllows() throws {
        let fixture = try makeFixture(accessibilityTrusted: true, pasteSucceeds: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = try fixture.insertItem(type: .html, payloads: [
            .init(format: .html, data: Data("<p>Hello</p>".utf8)),
            .init(format: .plainText, data: Data("Hello".utf8))
        ])

        let result = fixture.controller.copyAndPaste(item.id)

        XCTAssertEqual(result, .success(.pasted))
        XCTAssertEqual(fixture.writer.writes.count, 1)
        XCTAssertEqual(fixture.writer.writes.first?.contentType, .html)
        XCTAssertEqual(fixture.pastePerformer.performCount, 1)
    }

    func test_copyAndPaste_degradesWhenSyntheticPasteFails() throws {
        let fixture = try makeFixture(accessibilityTrusted: true, pasteSucceeds: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let item = try fixture.insertItem(type: .plainText, payloads: [
            .init(format: .plainText, data: Data("hello".utf8))
        ])

        let result = fixture.controller.copyAndPaste(item.id)

        XCTAssertEqual(result, .success(.copiedOnly(reason: "synthetic-paste-failed")))
        XCTAssertEqual(fixture.writer.writes.count, 1)
        XCTAssertEqual(fixture.pastePerformer.performCount, 1)
    }

    // MARK: - Helpers

    private func makeFixture(
        accessibilityTrusted: Bool = true,
        pasteSucceeds: Bool = true
    ) throws -> ClipboardPasteControllerFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-clipboard-paste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = try ClipboardDatabase(location: ClipboardStorageLocation(rootDirectory: root))
        try database.initialize()
        let repository = ClipboardRepository(database: database)
        let binaryStore = BinaryContentStore(rootDirectory: root.appendingPathComponent("Payloads", isDirectory: true))
        let writer = RecordingClipboardContentWriter()
        let pastePerformer = RecordingSyntheticPastePerformer(result: pasteSucceeds)
        let controller = ClipboardPasteController(
            repository: repository,
            binaryStore: binaryStore,
            writer: writer,
            accessibility: FixedAccessibilityPermissionChecker(isTrusted: accessibilityTrusted),
            pastePerformer: pastePerformer
        )
        return ClipboardPasteControllerFixture(
            root: root,
            repository: repository,
            binaryStore: binaryStore,
            writer: writer,
            pastePerformer: pastePerformer,
            controller: controller
        )
    }
}

private struct ClipboardPasteControllerFixture {
    let root: URL
    let repository: ClipboardRepository
    let binaryStore: BinaryContentStore
    let writer: RecordingClipboardContentWriter
    let pastePerformer: RecordingSyntheticPastePerformer
    let controller: ClipboardPasteController

    func insertItem(
        type: ClipboardContentType,
        payloads: [ClipboardCapturedPayload]
    ) throws -> ClipboardItem {
        let item = try repository.insert(
            ClipboardItem(
                contentHash: UUID().uuidString,
                contentType: type,
                textPreview: "preview"
            )
        )
        for payload in payloads {
            let path = try binaryStore.write(payload.data, for: item.id, format: payload.format)
            try repository.insertPayload(
                ClipboardBinaryPayload(
                    recordID: item.id,
                    format: payload.format,
                    storagePath: path,
                    fileSize: payload.data.count
                )
            )
        }
        return item
    }
}

private final class RecordingClipboardContentWriter: ClipboardContentWriting, @unchecked Sendable {
    struct Write: Equatable {
        let payloads: [ClipboardCapturedPayload]
        let contentType: ClipboardContentType
    }

    private let lock = NSLock()
    private var storedWrites: [Write] = []

    var writes: [Write] {
        lock.lock()
        defer { lock.unlock() }
        return storedWrites
    }

    func write(_ payloads: [ClipboardCapturedPayload], as contentType: ClipboardContentType) throws {
        lock.lock()
        storedWrites.append(Write(payloads: payloads, contentType: contentType))
        lock.unlock()
    }
}

private struct FixedAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    let isTrusted: Bool

    var isTrustedForSyntheticPaste: Bool {
        isTrusted
    }
}

private final class RecordingSyntheticPastePerformer: SyntheticPastePerforming, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Bool
    private var storedPerformCount = 0

    init(result: Bool) {
        self.result = result
    }

    var performCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedPerformCount
    }

    func performPaste() -> Bool {
        lock.lock()
        storedPerformCount += 1
        lock.unlock()
        return result
    }
}
