# Design: Expand Read-Only Disk Analysis

## Background

The current disk-analysis flow has a sound security boundary: `AppState` owns `LargeFileAvailability`, `SystemDiskUsageService` scans a user-authorized root, the scanner reads only regular-file metadata, and the authorization manager releases security scope after each finite scan. The current UI, however, is a simple bounded list and still contains copy written before large-file scanning was delivered.

This change adds a presentation and review layer over the existing result. It does not broaden scan roots or introduce file mutation.

## Capability Boundary

The workbench may:

- summarize records already returned by the bounded scan;
- infer display facets from file name extension, size, and modification date;
- filter and sort those in-memory records;
- hold selection and ignore state for the current result only;
- ask Finder to reveal a current record after narrow authorization validation.

It must not delete, move, rename, open file contents, persist paths, start background scans, or claim that the bounded result represents the whole disk.

## Current Inconsistencies

- `CleanerView` says directory analysis is not implemented even though authorized large-file scanning is delivered.
- One prominent refresh button refreshes both capacity and large files, while the main disk-analysis specification requires capacity refresh not to start directory scanning.
- `CleanerLargeFileSection` always renders a fixed size-sorted list and cannot explain its current subset.
- Paths are available for local display, but there is no narrow action boundary for revealing a current result in Finder.

## Implementation Baseline

Before implementation, the local `v0.1.0` baseline at commit `3ee76b6` passed the Debug build, the complete `OmnipoTests` suite, and `openspec validate --all --strict` on macOS 26.5, Xcode 26.6, and Swift 6.3.3. The recorded evidence contains only pass/fail status, toolchain versions, and stable identifiers; it excludes device names, real file paths, and scanned file lists.

The implementation audit also confirmed these boundaries:

- the Cleaner page still contains pre-scan Phase 0 copy and a combined capacity/scan refresh action;
- `CleanerLargeFileSection` only maps availability to a fixed service-ordered list and owns no query or review state;
- `FileLauncher` couples Finder reveal to launcher result/bookmark behavior and is not a suitable authorization boundary for disk-analysis records;
- `LargeFileRecord` identity is sufficient for one result snapshot only, so selection and ignore state must reset when that snapshot is replaced;
- no deletion service, Trash execution, persistent file index, telemetry, cloud dependency, or distribution workflow is part of this change.

## Architecture

```text
AppState.largeFileAvailability
  -> LargeFileWorkbenchStore (@MainActor, @Observable)
       -> LargeFileFacetClassifier (pure metadata mapping)
       -> LargeFileWorkbenchQuery (filters + sort)
       -> ephemeral selection / ignore state
       -> visible records + aggregate summary

CleanerView
  -> capacity refresh (volume metadata only)
  -> scan refresh (authorized directory metadata only)
  -> CleanerLargeFileWorkbench
       -> LargeFileRevealService
            -> AuthorizedRootManager (finite scope)
            -> NSWorkspace.activateFileViewerSelecting
```

## Metadata Facets

`LargeFileFacetClassifier` is a pure, deterministic mapping and never opens a file.

- **Type:** derive broad groups such as video, image, audio, document, archive, disk image, developer artifact, and other from the lowercased extension. Unknown or missing extensions remain `other`.
- **Size:** derive bounded buckets suitable for the current result, while keeping an “all sizes” option. Exact thresholds are centralized and unit-tested.
- **Age:** derive recent, medium-age, old, and unknown buckets from `lastModifiedAt` relative to an injected `now` value.
- **Directory:** derive a display-only parent group from the current authorized root and record path. It remains in memory, is never logged, and falls back to a generic label when a safe relative group cannot be derived.

Classification is explicitly approximate. The UI must not describe extension-based type as content verification.

## Workbench State

`LargeFileWorkbenchStore` is the single source of truth for presentation state:

- query text;
- selected type, size, age, and directory facets;
- sort order;
- selected record IDs;
- ignored record IDs;
- current source generation or result token;
- latest reveal outcome as a sanitized UI message.

The store receives a complete current `[LargeFileRecord]` snapshot. When the source result is replaced, it resets selection and ignore state instead of persisting path-derived identity. Filter changes do not alter source records or selection membership. Ignored candidates are excluded from the primary list and can be restored from a separate current-result review section.

All aggregate counts and byte totals state that they describe only the current authorized, capped result set.

## Refresh Boundaries

The UI exposes two separate actions:

1. **Refresh capacity:** invokes only `refreshStartupVolumeCapacity()`.
2. **Refresh directory analysis:** invokes only `refreshLargeFiles()` and keeps the existing cancellation, stale-result, and scope-release behavior.

Opening the page may retain the existing `loadLargeFilesIfNeeded()` behavior for the currently configured root. Filter or sort changes never trigger a scan.

## Finder Reveal

Introduce a narrow injectable `LargeFileRevealService` rather than calling `NSWorkspace` directly from SwiftUI.

Before revealing, the application layer verifies that:

- the record is still part of the current result;
- its standardized URL remains within the currently authorized root;
- the path still exists;
- the security scope can be acquired when required.

The service then calls Finder selection and releases the manager-owned scope on success, unavailable, denial, cancellation, and unexpected failure. Returned errors use stable codes and generic user text. Logs contain the action and stable result only—never the file name, path, filter text, directory facet, or bookmark bytes.

## UI Composition

The existing large-file card becomes a workbench with:

- a boundary note describing the authorized root and capped current result;
- compact summary values for visible files, visible bytes, selected files, and selected bytes;
- search, type, size, age, directory, and sort controls;
- rows with selection, metadata-derived type, size, modification date, path, ignore, and Finder actions;
- empty states that distinguish no scan results, no filter matches, and all candidates ignored;
- a review area for selected and ignored candidates;
- a persistent read-only notice that no cleanup action is available in this change.

The stale Phase 0 panel is removed or rewritten to list only capabilities that genuinely remain unavailable.

## Privacy and Persistence

- Raw paths and file names remain in the in-memory scan result and local UI only.
- Query text, selected IDs, ignored IDs, directory groups, and reveal targets are not written to settings, Codable persistence, logs, or analytics.
- No new database table, cache, index, telemetry, or network request is introduced.
- Tests use synthetic temporary paths and assert that operational logs do not contain them.

## Accessibility and Keyboard Use

- Filter controls have explicit accessibility labels and values.
- Rows expose selection state, file name, metadata-derived type, size, and modification status without requiring pointer hover.
- Finder and ignore actions are available from buttons and contextual menus.
- Keyboard focus order follows filters, results, and review state; Return does not perform mutation.

## Verification

- Unit-test facet classification, filter combinations, sorting, aggregate totals, and injected time boundaries.
- Unit-test source replacement reset, selection/ignore invariants, and empty-state distinctions.
- Unit-test reveal success, missing item, out-of-root path, authorization denial, and scope release.
- Verify capacity refresh does not call large-file scanning and filter changes do not trigger service calls.
- Run focused disk-analysis tests after each implementation group.
- Run `openspec validate --all --strict` and full `./script/build_and_run.sh verify`.
- Complete a privacy-safe local smoke check using only pass/fail evidence.
