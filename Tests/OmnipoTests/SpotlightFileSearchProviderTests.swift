import XCTest
import os
@testable import Omnipo

private final class FakeFileSearchBackend: FileSearchBackend, @unchecked Sendable {
    var result: FileSearchBackendResult
    private(set) var lastQuery: String?
    private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)

    init(result: FileSearchBackendResult) {
        self.result = result
    }

    func search(query: String) async -> FileSearchBackendResult {
        lock.withLock { _ in }
        lastQuery = query
        return result
    }
}

final class SpotlightFileSearchProviderTests: XCTestCase {

    private func makeLogger() -> any LoggingService {
        OSLogLoggingService(subsystem: "com.qing.omnipo.tests.spotlight")
    }

    func test_shortQuery_skipsBackend() async {
        let backend = FakeFileSearchBackend(result: .success([]))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "a", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.isEmpty)
        } else {
            XCTFail("expected success empty")
        }
        XCTAssertNil(backend.lastQuery, "short query should not invoke backend")
    }

    func test_emptyQuery_skipsBackend() async {
        let backend = FakeFileSearchBackend(result: .success([]))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "  ", generation: 1)

        if case .success(let results) = result {
            XCTAssertTrue(results.isEmpty)
        }
        XCTAssertNil(backend.lastQuery)
    }

    func test_backendUnavailable_propagatesAsUnavailable() async {
        let backend = FakeFileSearchBackend(result: .unavailable(reason: "spotlight-disabled"))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "report", generation: 1)

        if case .unavailable(let reason) = result {
            XCTAssertEqual(reason, "spotlight-disabled")
        } else {
            XCTFail("expected unavailable")
        }
    }

    func test_backendSuccess_returnsSearchResults() async {
        let bookmark = Data([0x01, 0x02, 0x03])
        let entry = FileEntry(displayName: "report.pdf", bookmark: bookmark, fileExtension: "pdf")
        let backend = FakeFileSearchBackend(result: .success([entry]))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "report", generation: 1)

        guard case .success(let results) = result, let first = results.first else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(first.title, "report.pdf")
        XCTAssertEqual(first.kind, .file)
        if case .fileBookmark(let data) = first.executionPayload {
            XCTAssertEqual(data, bookmark)
        } else {
            XCTFail("expected fileBookmark payload")
        }
    }

    func test_maxResults_truncatesLongLists() async {
        let entries = (0..<200).map { i in
            FileEntry(displayName: "file\(i)", bookmark: Data([UInt8(truncatingIfNeeded: i)]), fileExtension: "txt")
        }
        let backend = FakeFileSearchBackend(result: .success(entries))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger(), maxResults: 10)

        let result = await provider.search(query: "file", generation: 1)

        if case .success(let results) = result {
            XCTAssertEqual(results.count, 10)
        } else {
            XCTFail("expected success")
        }
    }

    func test_results_carryIconDescriptorFromFileExtension() async {
        let entry = FileEntry(displayName: "image.png", bookmark: Data([0x00]), fileExtension: "png")
        let backend = FakeFileSearchBackend(result: .success([entry]))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "image", generation: 1)

        guard case .success(let results) = result, let first = results.first else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(first.iconDescriptor, .fileType("png"))
    }

    func test_fileWithoutExtension_usesGenericFileIcon() async {
        let entry = FileEntry(displayName: "README", bookmark: Data([0x00]), fileExtension: nil)
        let backend = FakeFileSearchBackend(result: .success([entry]))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "readme", generation: 1)

        guard case .success(let results) = result, let first = results.first else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(first.iconDescriptor, .genericFile)
    }

    func test_sourceIdentifier_doesNotEmbedPath() async {
        let entry = FileEntry(displayName: "secret.pdf", bookmark: Data([0xAB, 0xCD]), fileExtension: "pdf")
        let backend = FakeFileSearchBackend(result: .success([entry]))
        let provider = SpotlightFileSearchProvider(backend: backend, logger: makeLogger())

        let result = await provider.search(query: "secret", generation: 1)

        guard case .success(let results) = result, let first = results.first else {
            XCTFail("expected success")
            return
        }
        XCTAssertFalse(first.sourceIdentifier.contains("/"), "source id must not embed paths")
        XCTAssertFalse(first.sourceIdentifier.contains("secret"))
    }

    func test_backendSearchTerms_includeCJKAdjacentWindowsForLongQuery() {
        let terms = SpotlightFileSearchBackend.searchTerms(for: "吃面包")

        XCTAssertEqual(terms, ["吃面包", "吃面", "面包"])
    }

    @MainActor
    func test_backendFiltersBroadCJKRecallByFullFileNameQuery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnipo-spotlight-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let target = directory.appendingPathComponent("吃面包.mp4")
        let nearMiss = directory.appendingPathComponent("吃面条.mp4")
        try Data().write(to: target)
        try Data().write(to: nearMiss)

        let query = FakeSpotlightMetadataQuery(items: [
            FakeSpotlightMetadataItem(path: target.path, displayName: target.lastPathComponent),
            FakeSpotlightMetadataItem(path: nearMiss.path, displayName: nearMiss.lastPathComponent)
        ])
        let backend = SpotlightFileSearchBackend(
            logger: makeLogger(),
            timeout: 5,
            resultLimit: 10,
            queryFactory: { query }
        )

        let task = Task {
            await backend.search(query: "吃面包")
        }
        while query.startCount == 0 {
            await Task.yield()
        }
        NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: query)

        guard case .success(let entries) = await task.value else {
            XCTFail("expected success")
            return
        }
        XCTAssertEqual(entries.map(\.displayName), ["吃面包.mp4"])
    }

    @MainActor
    func test_backendCancellationStopsMetadataQueryAndCompletesOnce() async {
        let query = FakeSpotlightMetadataQuery()
        let backend = SpotlightFileSearchBackend(
            logger: makeLogger(),
            timeout: 5,
            resultLimit: 10,
            queryFactory: { query }
        )

        let task = Task {
            await backend.search(query: "report")
        }
        while query.startCount == 0 {
            await Task.yield()
        }
        task.cancel()
        let result = await task.value
        NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: query)

        XCTAssertEqual(query.stopCount, 1)
        if case .unavailable(let reason) = result {
            XCTAssertEqual(reason, "cancelled")
        } else {
            XCTFail("expected cancelled result")
        }
    }
}

@MainActor
private final class FakeSpotlightMetadataQuery: SpotlightMetadataQuery {
    var predicate: NSPredicate?
    var searchScopes: [Any] = []
    var sortDescriptors: [NSSortDescriptor] = []
    var resultCount: Int { items.count }
    private let items: [FakeSpotlightMetadataItem]
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(items: [FakeSpotlightMetadataItem] = []) {
        self.items = items
    }

    func result(at index: Int) -> Any { items[index] }

    func start() -> Bool {
        startCount += 1
        return true
    }

    func stop() {
        stopCount += 1
    }
}

private final class FakeSpotlightMetadataItem: SpotlightMetadataItem {
    private let values: [String: Any]

    init(path: String, displayName: String) {
        self.values = [
            "kMDItemPath": path,
            "kMDItemDisplayName": displayName
        ]
    }

    func value(forAttribute key: String) -> Any? {
        values[key]
    }
}
