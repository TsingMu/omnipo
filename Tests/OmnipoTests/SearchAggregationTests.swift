import XCTest
import os
@testable import Omnipo

private final class FakeProvider: SearchProvider, @unchecked Sendable {
    let kind: String
    let delay: TimeInterval
    let outcome: SearchProviderResult
    private(set) var calls = OSAllocatedUnfairLock<Int>(initialState: 0)
    private(set) var queries = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(kind: String, outcome: SearchProviderResult, delay: TimeInterval = 0) {
        self.kind = kind
        self.outcome = outcome
        self.delay = delay
    }

    func search(query: String, generation: UInt64) async -> SearchProviderResult {
        calls.withLock { $0 += 1 }
        queries.withLock { $0.append(query) }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return outcome
    }
}

private func makeLogger() -> any LoggingService {
    OSLogLoggingService(subsystem: "com.omnipo.tests.search")
}

private func collectBatches(
    from service: any SearchService,
    query: String
) async -> [SearchBatch] {
    var batches: [SearchBatch] = []
    for await batch in service.search(query: query) {
        batches.append(batch)
    }
    return batches
}

final class DefaultSearchServiceTests: XCTestCase {

    func test_search_combinesResultsFromAllProviders() async {
        let command = FakeProvider(
            kind: "command",
            outcome: .success([
                SearchResult(
                    kind: .command,
                    title: "Open Clipboard",
                    matchScore: 1.0,
                    sourceIdentifier: "openClipboard",
                    iconDescriptor: .none,
                    executionPayload: .launcherCommand(LauncherCommand.openClipboard.id)
                )
            ])
        )
        let app = FakeProvider(
            kind: "application",
            outcome: .success([
                SearchResult(
                    kind: .application,
                    title: "Safari",
                    matchScore: 0.8,
                    sourceIdentifier: "com.apple.Safari",
                    iconDescriptor: .appBundleIdentifier("com.apple.Safari"),
                    executionPayload: .applicationBundleIdentifier("com.apple.Safari")
                )
            ])
        )
        let service = DefaultSearchService(providers: [command, app], logger: makeLogger())

        let batch = await collectBatches(from: service, query: "test").last!

        XCTAssertEqual(batch.results.count, 2)
        XCTAssertTrue(batch.failures.isEmpty)
    }

    func test_search_isolatesProviderFailures() async {
        let good = FakeProvider(
            kind: "command",
            outcome: .success([
                SearchResult(
                    kind: .command,
                    title: "Open Clipboard",
                    matchScore: 1.0,
                    sourceIdentifier: "openClipboard",
                    iconDescriptor: .none,
                    executionPayload: .launcherCommand(LauncherCommand.openClipboard.id)
                )
            ])
        )
        let bad = FakeProvider(
            kind: "file",
            outcome: .failure(SearchProviderFailure(
                providerKind: "file",
                stableCode: "E_FILE",
                userDescription: nil
            ))
        )
        let service = DefaultSearchService(providers: [good, bad], logger: makeLogger())

        let batch = await collectBatches(from: service, query: "find test").last!

        XCTAssertEqual(batch.results.count, 1, "successful provider results should still appear")
        XCTAssertEqual(batch.failures.count, 1)
    }

    func test_search_unavailable_isRecordedAsFailure() async {
        let unavailable = FakeProvider(
            kind: "file",
            outcome: .unavailable(reason: "spotlight-disabled")
        )
        let service = DefaultSearchService(providers: [unavailable], logger: makeLogger())

        let batch = await collectBatches(from: service, query: "find test").last!

        XCTAssertEqual(batch.failures.count, 1)
        XCTAssertEqual(batch.failures.first?.providerKind, "file")
    }

    func test_search_generationIncreasesPerCall() async {
        let empty = FakeProvider(kind: "command", outcome: .success([]))
        let service = DefaultSearchService(providers: [empty], logger: makeLogger())

        let first = await collectBatches(from: service, query: "a").last!
        let second = await collectBatches(from: service, query: "b").last!

        XCTAssertGreaterThan(second.generation, first.generation)
    }

    func test_search_runsAllProvidersConcurrently() async {
        let slow = FakeProvider(
            kind: "command",
            outcome: .success([
                SearchResult(
                    kind: .command,
                    title: "x",
                    matchScore: 1.0,
                    sourceIdentifier: "x",
                    iconDescriptor: .none,
                    executionPayload: .launcherCommand("x")
                )
            ]),
            delay: 0.05
        )
        let service = DefaultSearchService(providers: [slow, slow, slow], logger: makeLogger())

        let start = Date()
        _ = await collectBatches(from: service, query: "x")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.12, "should be parallel, total < 3 * delay")
    }

    func test_search_publishesLocalBatchBeforeDebouncedFilesAfterFindPrefix() async {
        let localResult = SearchResult(
            kind: .application,
            title: "Safari",
            matchScore: 1,
            sourceIdentifier: "com.apple.Safari",
            iconDescriptor: .none,
            executionPayload: .applicationBundleIdentifier("com.apple.Safari")
        )
        let fileResult = SearchResult(
            kind: .file,
            title: "Safari Notes",
            matchScore: 0.3,
            sourceIdentifier: "file",
            iconDescriptor: .genericFile,
            executionPayload: .fileBookmark(Data([1]))
        )
        let local = FakeProvider(kind: "application", outcome: .success([localResult]))
        let file = FakeProvider(kind: "file", outcome: .success([fileResult]), delay: 0.05)
        let service = DefaultSearchService(
            providers: [local, file],
            logger: makeLogger(),
            fileDebounce: .milliseconds(50)
        )

        let start = ContinuousClock.now
        var iterator = service.search(query: "find safari").makeAsyncIterator()
        let first = await iterator.next()
        let firstElapsed = start.duration(to: .now)
        let final = await iterator.next()

        XCTAssertEqual(first?.results.map(\.kind), [.application])
        XCTAssertEqual(first?.isFinal, false)
        XCTAssertLessThan(firstElapsed, .milliseconds(50))
        XCTAssertEqual(final?.results.map(\.kind), [.application, .file])
        XCTAssertEqual(final?.isFinal, true)
        XCTAssertEqual(file.queries.withLock { $0 }, ["safari"])
    }

    func test_search_doesNotRunFileProviderWithoutFindPrefix() async {
        let local = FakeProvider(kind: "application", outcome: .success([]))
        let file = FakeProvider(kind: "file", outcome: .success([]))
        let service = DefaultSearchService(providers: [local, file], logger: makeLogger())

        let batch = await collectBatches(from: service, query: "safari").last!

        XCTAssertEqual(batch.isFinal, true)
        XCTAssertEqual(file.calls.withLock { $0 }, 0)
    }

    func test_newQueryCancelsOldFileSearchDuringDebounce() async {
        let local = FakeProvider(kind: "command", outcome: .success([]))
        let file = FakeProvider(kind: "file", outcome: .success([]))
        let service = DefaultSearchService(
            providers: [local, file],
            logger: makeLogger(),
            fileDebounce: .milliseconds(150)
        )

        let oldConsumer = Task {
            await collectBatches(from: service, query: "find old query")
        }
        try? await Task.sleep(for: .milliseconds(20))
        _ = await collectBatches(from: service, query: "x")
        _ = await oldConsumer.value

        XCTAssertEqual(file.calls.withLock { $0 }, 0)
    }
}

@MainActor
final class LauncherStoreTests: XCTestCase {

    private func makeService(_ outcomes: [(String, SearchProviderResult)]) -> DefaultSearchService {
        let providers = outcomes.map { FakeProvider(kind: $0.0, outcome: $0.1) }
        return DefaultSearchService(providers: providers, logger: makeLogger())
    }

    private func sampleResult(id: String, kind: SearchResult.Kind = .command) -> SearchResult {
        SearchResult(
            kind: kind,
            title: id,
            matchScore: 1.0,
            sourceIdentifier: id,
            iconDescriptor: .none,
            executionPayload: .launcherCommand(id)
        )
    }

    func test_updateQuery_appliesResultsAndSelectsFirst() async {
        let service = makeService([
            ("command", .success([sampleResult(id: "alpha"), sampleResult(id: "beta")]))
        ])
        let store = LauncherStore(service: service)

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.results.count, 2)
        XCTAssertEqual(store.selection, store.results.first?.id)
        XCTAssertEqual(store.state, .showingResults)
    }

    func test_updateQuery_keepsExistingSelectionWhenStillPresent() async {
        let service = makeService([
            ("command", .success([sampleResult(id: "alpha"), sampleResult(id: "beta"), sampleResult(id: "gamma")]))
        ])
        let store = LauncherStore(service: service)

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        let firstSelection = store.results.first?.id
        store.moveSelection(by: 1)
        let movedSelection = store.selection

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.selection, movedSelection)
        XCTAssertNotEqual(store.selection, firstSelection)
    }

    func test_updateQuery_reselectsFirstWhenSelectionDisappears() async {
        let service = makeService([
            ("command", .success([sampleResult(id: "alpha"), sampleResult(id: "beta")]))
        ])
        let store = LauncherStore(service: service)

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        store.moveSelection(by: 1)
        XCTAssertEqual(store.selection, store.results.last?.id)

        // 第二次查询返回完全不同的结果
        let service2 = makeService([
            ("command", .success([sampleResult(id: "charlie"), sampleResult(id: "delta")]))
        ])
        let store2 = LauncherStore(service: service2)
        store2.updateQuery("b")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store2.selection, store2.results.first?.id)
    }

    func test_moveSelection_clampsAtBounds() async {
        let service = makeService([
            ("command", .success([sampleResult(id: "alpha"), sampleResult(id: "beta")]))
        ])
        let store = LauncherStore(service: service)

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)

        store.moveSelection(by: -5)
        XCTAssertEqual(store.selection, store.results.first?.id)

        store.moveSelection(by: 100)
        XCTAssertEqual(store.selection, store.results.last?.id)
    }

    func test_cancelAll_clearsState() async {
        let result = sampleResult(id: "alpha")
        let service = CancellationRecordingSearchService(result: result)
        let store = LauncherStore(service: service)

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(store.results.isEmpty)

        store.cancelAll()

        XCTAssertEqual(store.query, "")
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertNil(store.selection)
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(service.cancelCallCount, 1)
    }

    func test_emptyResults_marksStateEmpty() async {
        let service = makeService([("command", .success([]))])
        let store = LauncherStore(service: service)

        store.updateQuery("zzz")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .empty)
        XCTAssertNil(store.selection)
    }

    func test_fileBatchKeepsSelectionFromLocalBatch() async {
        let localResults = [sampleResult(id: "alpha"), sampleResult(id: "beta")]
        let fileResult = SearchResult(
            kind: .file,
            title: "alpha.txt",
            matchScore: 0.3,
            sourceIdentifier: "file.alpha",
            iconDescriptor: .genericFile,
            executionPayload: .fileBookmark(Data([1]))
        )
        let service = DefaultSearchService(
            providers: [
                FakeProvider(kind: "command", outcome: .success(localResults)),
                FakeProvider(kind: "file", outcome: .success([fileResult]))
            ],
            logger: makeLogger(),
            fileDebounce: .milliseconds(80)
        )
        let store = LauncherStore(service: service)

        store.updateQuery("find alpha")
        try? await Task.sleep(for: .milliseconds(30))
        store.moveSelection(by: 1)
        let localSelection = store.selection
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(store.selection, localSelection)
        XCTAssertEqual(store.results.count, 3)
    }
}

private final class CancellationRecordingSearchService: SearchService, @unchecked Sendable {
    private let result: SearchResult
    private let cancellationCount = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(result: SearchResult) {
        self.result = result
    }

    var cancelCallCount: Int {
        cancellationCount.withLock { $0 }
    }

    func search(query: String) -> AsyncStream<SearchBatch> {
        AsyncStream { continuation in
            continuation.yield(SearchBatch(
                generation: 1,
                results: [result],
                failures: [],
                isFinal: true
            ))
            continuation.finish()
        }
    }

    func cancel() {
        cancellationCount.withLock { $0 += 1 }
    }
}
