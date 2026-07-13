import XCTest
@testable import Omnipo

final class LargeFileWorkbenchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func record(
        id: UUID = UUID(),
        name: String,
        path: String,
        size: Int64,
        modifiedAt: Date? = nil
    ) -> LargeFileRecord {
        LargeFileRecord(
            id: id,
            name: name,
            displayPath: path,
            sizeBytes: size,
            lastModifiedAt: modifiedAt,
            sourceVolumeIdentifier: "test-volume"
        )
    }

    func test_kindClassification_isCaseInsensitiveAndConservative() {
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "movie.MP4"), .video)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "photo.JpG"), .image)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "song.flac"), .audio)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "notes.pdf"), .document)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "backup.zip"), .archive)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "installer.dmg"), .diskImage)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "project.xcodeproj"), .developerArtifact)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "README"), .other)
        XCTAssertEqual(LargeFileFacetClassifier.kind(for: "payload.unknown"), .other)
    }

    func test_sizeClassification_respectsExactBoundaries() {
        let mib = LargeFileSizeBucket.mebibyte
        let gib = LargeFileSizeBucket.gibibyte
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: 100 * mib - 1), .under100MiB)
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: 100 * mib), .from100MiBTo1GiB)
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: gib - 1), .from100MiBTo1GiB)
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: gib), .from1GiBTo10GiB)
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: 10 * gib - 1), .from1GiBTo10GiB)
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: 10 * gib), .atLeast10GiB)
        XCTAssertEqual(LargeFileSizeBucket.classify(sizeBytes: -1), .under100MiB)
    }

    func test_ageClassification_usesInjectedNowAndKeepsUnknown() {
        let day: TimeInterval = 86_400
        XCTAssertEqual(LargeFileAgeBucket.classify(lastModifiedAt: nil, now: now), .unknown)
        XCTAssertEqual(LargeFileAgeBucket.classify(lastModifiedAt: now.addingTimeInterval(-30 * day), now: now), .within30Days)
        XCTAssertEqual(LargeFileAgeBucket.classify(lastModifiedAt: now.addingTimeInterval(-30 * day - 1), now: now), .withinOneYear)
        XCTAssertEqual(LargeFileAgeBucket.classify(lastModifiedAt: now.addingTimeInterval(-365 * day), now: now), .withinOneYear)
        XCTAssertEqual(LargeFileAgeBucket.classify(lastModifiedAt: now.addingTimeInterval(-365 * day - 1), now: now), .olderThanOneYear)
        XCTAssertEqual(LargeFileAgeBucket.classify(lastModifiedAt: now.addingTimeInterval(day), now: now), .within30Days)
    }

    func test_directoryClassification_usesFirstRelativeDirectoryAndFallbacks() {
        XCTAssertEqual(
            LargeFileFacetClassifier.directory(for: "/authorized/Movies/clip.mov", authorizedRootPath: "/authorized"),
            LargeFileDirectoryFacet(key: "Movies", displayName: "Movies")
        )
        XCTAssertEqual(
            LargeFileFacetClassifier.directory(for: "/authorized/direct.dat", authorizedRootPath: "/authorized"),
            .authorizedRoot
        )
        XCTAssertEqual(
            LargeFileFacetClassifier.directory(for: "/authorized-other/file.dat", authorizedRootPath: "/authorized"),
            .unavailable
        )
        XCTAssertEqual(
            LargeFileFacetClassifier.directory(for: "/authorized/file.dat", authorizedRootPath: nil),
            .unavailable
        )
    }

    func test_combinedQueryFiltersTextFacetsAndDirectory() {
        let gib = LargeFileSizeBucket.gibibyte
        let records = [
            record(name: "Summer.MP4", path: "/root/Movies/Summer.MP4", size: 2 * gib, modifiedAt: now),
            record(name: "Winter.mov", path: "/root/Movies/Winter.mov", size: 2 * gib, modifiedAt: now),
            record(name: "Summer.jpg", path: "/root/Photos/Summer.jpg", size: 2 * gib, modifiedAt: now)
        ]
        let facets = LargeFileWorkbenchQueryEngine.classify(records: records, authorizedRootPath: "/root", now: now)
        let query = LargeFileWorkbenchQuery(
            text: "summer",
            kind: .video,
            sizeBucket: .from1GiBTo10GiB,
            ageBucket: .within30Days,
            directory: LargeFileDirectoryFacet(key: "Movies", displayName: "Movies")
        )

        XCTAssertEqual(LargeFileWorkbenchQueryEngine.apply(query, to: facets).map(\.record.name), ["Summer.MP4"])
        XCTAssertTrue(query.hasFilters)
    }

    func test_sortingUsesStableFallbackAndKeepsUnknownDatesLast() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let records = [
            record(id: secondID, name: "same.bin", path: "/root/same.bin", size: 10, modifiedAt: nil),
            record(name: "new.bin", path: "/root/new.bin", size: 10, modifiedAt: now),
            record(id: firstID, name: "same.bin", path: "/root/same.bin", size: 10, modifiedAt: nil),
            record(name: "old.bin", path: "/root/old.bin", size: 10, modifiedAt: now.addingTimeInterval(-10))
        ]
        let facets = LargeFileWorkbenchQueryEngine.classify(records: records, authorizedRootPath: "/root", now: now)

        let newest = LargeFileWorkbenchQueryEngine.apply(
            LargeFileWorkbenchQuery(sortOrder: .modifiedNewest),
            to: facets
        )
        XCTAssertEqual(newest.map(\.record.name), ["new.bin", "old.bin", "same.bin", "same.bin"])
        XCTAssertEqual(newest.suffix(2).map(\.record.id), [firstID, secondID])

        let bySize = LargeFileWorkbenchQueryEngine.apply(
            LargeFileWorkbenchQuery(sortOrder: .sizeDescending),
            to: facets
        )
        XCTAssertEqual(bySize.map(\.record.name), ["new.bin", "old.bin", "same.bin", "same.bin"])
        XCTAssertEqual(bySize.suffix(2).map(\.record.id), [firstID, secondID])
    }

    func test_summaryCountsVisibleAndSelectedAcrossCurrentSource() {
        let selectedID = UUID()
        let hiddenSelectedID = UUID()
        let records = [
            record(id: selectedID, name: "a.bin", path: "/root/a.bin", size: 100),
            record(id: hiddenSelectedID, name: "b.bin", path: "/root/b.bin", size: 200),
            record(name: "c.bin", path: "/root/c.bin", size: 300)
        ]
        let facets = LargeFileWorkbenchQueryEngine.classify(records: records, authorizedRootPath: "/root", now: now)
        let summary = LargeFileWorkbenchSummary(
            sourceRecords: facets,
            visibleRecords: [facets[0], facets[2]],
            selectedIDs: [selectedID, hiddenSelectedID, UUID()]
        )

        XCTAssertEqual(summary.visibleCount, 2)
        XCTAssertEqual(summary.visibleBytes, 400)
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.selectedBytes, 300)
    }

    func test_directoriesAreUniqueAndPredictablySorted() {
        let records = [
            record(name: "z.bin", path: "/root/Zeta/z.bin", size: 1),
            record(name: "a.bin", path: "/root/Alpha/a.bin", size: 1),
            record(name: "a2.bin", path: "/root/Alpha/a2.bin", size: 1)
        ]
        let facets = LargeFileWorkbenchQueryEngine.classify(records: records, authorizedRootPath: "/root", now: now)
        XCTAssertEqual(LargeFileWorkbenchQueryEngine.directories(in: facets).map(\.displayName), ["Alpha", "Zeta"])
    }
}
