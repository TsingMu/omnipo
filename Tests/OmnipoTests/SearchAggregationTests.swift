import XCTest
import os
@testable import Omnipo

private final class FakeProvider: SearchProvider, @unchecked Sendable {
    let kind: String
    let delay: TimeInterval
    let outcome: SearchProviderResult
    private(set) var calls = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(kind: String, outcome: SearchProviderResult, delay: TimeInterval = 0) {
        self.kind = kind
        self.outcome = outcome
        self.delay = delay
    }

    func search(query: String, generation: UInt64) async -> SearchProviderResult {
        calls.withLock { $0 += 1 }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return outcome
    }
}

private func makeLogger() -> any LoggingService {
    OSLogLoggingService(subsystem: "com.omnipo.tests.search")
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

        let batch = await service.search(query: "test")

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

        let batch = await service.search(query: "test")

        XCTAssertEqual(batch.results.count, 1, "successful provider results should still appear")
        XCTAssertEqual(batch.failures.count, 1)
    }

    func test_search_unavailable_isRecordedAsFailure() async {
        let unavailable = FakeProvider(
            kind: "file",
            outcome: .unavailable(reason: "spotlight-disabled")
        )
        let service = DefaultSearchService(providers: [unavailable], logger: makeLogger())

        let batch = await service.search(query: "test")

        XCTAssertEqual(batch.failures.count, 1)
        XCTAssertEqual(batch.failures.first?.providerKind, "file")
    }

    func test_search_generationIncreasesPerCall() async {
        let empty = FakeProvider(kind: "command", outcome: .success([]))
        let service = DefaultSearchService(providers: [empty], logger: makeLogger())

        let first = await service.search(query: "a")
        let second = await service.search(query: "b")

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
        _ = await service.search(query: "x")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.12, "should be parallel, total < 3 * delay")
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
        let service = makeService([
            ("command", .success([sampleResult(id: "alpha")]))
        ])
        let store = LauncherStore(service: service)

        store.updateQuery("a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(store.results.isEmpty)

        store.cancelAll()

        XCTAssertEqual(store.query, "")
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertNil(store.selection)
        XCTAssertEqual(store.state, .idle)
    }

    func test_emptyResults_marksStateEmpty() async {
        let service = makeService([("command", .success([]))])
        let store = LauncherStore(service: service)

        store.updateQuery("zzz")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state, .empty)
        XCTAssertNil(store.selection)
    }
}
