import Foundation
import Observation

public enum LargeFileWorkbenchEmptyState: Sendable, Equatable {
    case noSourceRecords
    case noFilterMatches
    case allCandidatesIgnored
    case hasResults
}

/// 大文件只读工作台的会话状态。所有路径派生状态只驻留内存。
@Observable
@MainActor
public final class LargeFileWorkbenchStore {
    public var query = LargeFileWorkbenchQuery()
    public private(set) var selectedIDs: Set<UUID> = []
    public private(set) var ignoredIDs: Set<UUID> = []
    public private(set) var sourceGeneration: UInt64 = 0
    public private(set) var revealMessage: String?

    private var sourceRecords: [LargeFileFacetRecord] = []
    private var sourceSnapshot: [LargeFileRecord] = []
    private var authorizedRootPath: String?

    public init() {}

    public var visibleRecords: [LargeFileFacetRecord] {
        LargeFileWorkbenchQueryEngine.apply(
            query,
            to: sourceRecords.filter { !ignoredIDs.contains($0.id) }
        )
    }

    public var selectedRecords: [LargeFileFacetRecord] {
        LargeFileWorkbenchQueryEngine.apply(
            LargeFileWorkbenchQuery(sortOrder: .sizeDescending),
            to: sourceRecords.filter { selectedIDs.contains($0.id) }
        )
    }

    public var ignoredRecords: [LargeFileFacetRecord] {
        LargeFileWorkbenchQueryEngine.apply(
            LargeFileWorkbenchQuery(sortOrder: .sizeDescending),
            to: sourceRecords.filter { ignoredIDs.contains($0.id) }
        )
    }

    public var directories: [LargeFileDirectoryFacet] {
        LargeFileWorkbenchQueryEngine.directories(in: sourceRecords)
    }

    public var summary: LargeFileWorkbenchSummary {
        LargeFileWorkbenchSummary(
            sourceRecords: sourceRecords,
            visibleRecords: visibleRecords,
            selectedIDs: selectedIDs
        )
    }

    public var emptyState: LargeFileWorkbenchEmptyState {
        guard !sourceRecords.isEmpty else { return .noSourceRecords }
        if !visibleRecords.isEmpty { return .hasResults }
        if ignoredIDs.count == sourceRecords.count { return .allCandidatesIgnored }
        return .noFilterMatches
    }

    public func replaceSource(
        _ records: [LargeFileRecord],
        authorizedRootPath: String?,
        now: Date = Date()
    ) {
        let standardizedRoot = authorizedRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
        }
        guard records != sourceSnapshot || standardizedRoot != self.authorizedRootPath else { return }

        sourceSnapshot = records
        self.authorizedRootPath = standardizedRoot
        sourceRecords = LargeFileWorkbenchQueryEngine.classify(
            records: records,
            authorizedRootPath: standardizedRoot,
            now: now
        )
        selectedIDs.removeAll()
        ignoredIDs.removeAll()
        revealMessage = nil
        sourceGeneration &+= 1

        if let selectedDirectory = query.directory,
           !directories.contains(selectedDirectory) {
            query.directory = nil
        }
    }

    public func toggleSelection(for id: UUID) {
        guard contains(id), !ignoredIDs.contains(id) else { return }
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }
    }

    public func selectAllVisible() {
        selectedIDs.formUnion(visibleRecords.map(\.id))
    }

    public func clearSelection() {
        selectedIDs.removeAll()
    }

    public func ignore(_ id: UUID) {
        guard contains(id) else { return }
        selectedIDs.remove(id)
        ignoredIDs.insert(id)
    }

    public func restore(_ id: UUID) {
        ignoredIDs.remove(id)
    }

    public func restoreAllIgnored() {
        ignoredIDs.removeAll()
    }

    public func clearFilters() {
        query = LargeFileWorkbenchQuery(sortOrder: query.sortOrder)
    }

    public func setRevealMessage(_ message: String?) {
        revealMessage = message
    }

    public func contains(_ id: UUID) -> Bool {
        sourceRecords.contains { $0.id == id }
    }
}
