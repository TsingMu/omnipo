import XCTest
@testable import Omnipo

@MainActor
final class LargeFileWorkbenchStoreTests: XCTestCase {
    private func record(id: UUID = UUID(), name: String, size: Int64 = 1) -> LargeFileRecord {
        LargeFileRecord(
            id: id,
            name: name,
            displayPath: "/root/Group/\(name)",
            sizeBytes: size,
            sourceVolumeIdentifier: "test-volume"
        )
    }

    func test_selectionIgnoreAndRestoreMaintainInvariants() {
        let first = record(name: "first.bin", size: 20)
        let second = record(name: "second.bin", size: 10)
        let store = LargeFileWorkbenchStore()
        store.replaceSource([first, second], authorizedRootPath: "/root")

        store.toggleSelection(for: first.id)
        store.ignore(first.id)
        XCTAssertFalse(store.selectedIDs.contains(first.id))
        XCTAssertTrue(store.ignoredIDs.contains(first.id))
        XCTAssertEqual(store.visibleRecords.map(\.id), [second.id])

        store.toggleSelection(for: first.id)
        XCTAssertFalse(store.selectedIDs.contains(first.id))

        store.restore(first.id)
        XCTAssertFalse(store.ignoredIDs.contains(first.id))
        XCTAssertEqual(Set(store.visibleRecords.map(\.id)), [first.id, second.id])
    }

    func test_selectAllVisibleDoesNotSelectFilteredOrIgnoredRecords() {
        let video = record(name: "movie.mp4")
        let image = record(name: "photo.jpg")
        let ignoredVideo = record(name: "ignored.mov")
        let store = LargeFileWorkbenchStore()
        store.replaceSource([video, image, ignoredVideo], authorizedRootPath: "/root")
        store.ignore(ignoredVideo.id)
        store.query.kind = .video

        store.selectAllVisible()
        XCTAssertEqual(store.selectedIDs, [video.id])
    }

    func test_replacingSourceClearsReviewStateAndInvalidDirectoryFilter() {
        let old = record(name: "old.bin")
        let new = LargeFileRecord(
            name: "new.bin",
            displayPath: "/root/New/new.bin",
            sizeBytes: 2,
            sourceVolumeIdentifier: "test-volume"
        )
        let store = LargeFileWorkbenchStore()
        store.replaceSource([old], authorizedRootPath: "/root")
        store.query.directory = LargeFileDirectoryFacet(key: "Group", displayName: "Group")
        store.toggleSelection(for: old.id)
        store.ignore(old.id)
        store.setRevealMessage("已定位。")
        let generation = store.sourceGeneration

        store.replaceSource([new], authorizedRootPath: "/root")
        XCTAssertEqual(store.sourceGeneration, generation + 1)
        XCTAssertTrue(store.selectedIDs.isEmpty)
        XCTAssertTrue(store.ignoredIDs.isEmpty)
        XCTAssertNil(store.revealMessage)
        XCTAssertNil(store.query.directory)
    }

    func test_identicalSourceDoesNotResetCurrentSession() {
        let item = record(name: "same.bin")
        let store = LargeFileWorkbenchStore()
        store.replaceSource([item], authorizedRootPath: "/root")
        store.toggleSelection(for: item.id)
        let generation = store.sourceGeneration

        store.replaceSource([item], authorizedRootPath: "/root")
        XCTAssertEqual(store.sourceGeneration, generation)
        XCTAssertEqual(store.selectedIDs, [item.id])
    }

    func test_emptyStatesDistinguishNoSourceNoMatchesAndAllIgnored() {
        let item = record(name: "item.bin")
        let store = LargeFileWorkbenchStore()
        XCTAssertEqual(store.emptyState, .noSourceRecords)

        store.replaceSource([item], authorizedRootPath: "/root")
        store.query.text = "no-match"
        XCTAssertEqual(store.emptyState, .noFilterMatches)

        store.query.text = ""
        store.ignore(item.id)
        XCTAssertEqual(store.emptyState, .allCandidatesIgnored)
    }

    func test_summaryTracksSelectionAcrossFilterChanges() {
        let first = record(name: "first.mp4", size: 100)
        let second = record(name: "second.jpg", size: 200)
        let store = LargeFileWorkbenchStore()
        store.replaceSource([first, second], authorizedRootPath: "/root")
        store.toggleSelection(for: second.id)
        store.query.kind = .video

        XCTAssertEqual(store.summary.visibleCount, 1)
        XCTAssertEqual(store.summary.visibleBytes, 100)
        XCTAssertEqual(store.summary.selectedCount, 1)
        XCTAssertEqual(store.summary.selectedBytes, 200)
    }
}
