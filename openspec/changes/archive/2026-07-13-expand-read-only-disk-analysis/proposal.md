# Proposal: Expand Read-Only Disk Analysis

## Why

The `v0.1.0` local baseline can scan one user-authorized directory and show a bounded list of large files, but the Cleaner page still describes directory analysis as a future Phase 0 capability. The result list also has no metadata grouping, filtering, review state, or safe Finder action, so a successful scan is harder to explore than it needs to be.

Because Omnipo is used only on one local Mac, the next useful step is a richer read-only workbench rather than deletion, publishing infrastructure, or cloud features. This change should make existing scan results understandable and actionable without modifying user files.

## What Changes

- Replace stale Phase 0 copy with a truthful description of the delivered capacity and authorized-directory analysis capabilities.
- Separate volume-capacity refresh from authorized-directory scan refresh so each action has one clear effect.
- Derive file-type, size, and modification-age facets from existing file-system metadata without reading file contents.
- Add local filtering, sorting, summary counts, and visible-byte totals for the current bounded scan result.
- Add in-memory selection, ignore, review, restore, and selected-byte totals; reset ephemeral candidate state when scan results are replaced.
- Add a narrow “Show in Finder” action for a record still present in the current result, with security-scope access released after the action.
- Keep paths, file names, filter text, and selected candidates out of logs and settings.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `disk-analysis`: Extend the existing read-only large-file list into a metadata-derived workbench with explicit refresh boundaries, filters, session-only candidate review, and Finder reveal.

## Impact

- **Models/Application:** metadata facet models and a MainActor workbench store derived from `LargeFileAvailability`.
- **UI:** `CleanerView` and `CleanerLargeFileSection` become a truthful read-only analysis workbench.
- **Services:** a narrow injectable Finder-reveal boundary; no cleaner or deletion service is added.
- **Infrastructure:** security-scoped root access is reacquired only for the finite Finder action and released on every terminal path.
- **Tests:** pure facet/filter/sort tests, store state reconciliation, reveal authorization/release behavior, UI state mapping, and full regression verification.
- **Dependencies:** no third-party or network dependency.

## Non-Goals

- No delete, permanent delete, move to Trash, move, rename, quarantine, compression, deduplication, or automatic cleanup.
- No scanning beyond the user-selected root, no full-disk index, and no file-content parsing or preview generation.
- No persistent file list, path history, ignored-path database, or selected-candidate recovery across refresh/relaunch.
- No WeChat cleanup, system-cache cleanup, application uninstall changes, drag-and-drop uninstall, or publication work.
- No promise that Finder can reveal an item that was moved, deleted, or had its authorization revoked after the scan.

## Risks

- File type inferred from extension is approximate and must be labeled as metadata-derived rather than content-verified.
- A file may disappear or move between scan and Finder reveal; this must become a safe unavailable result rather than a crash.
- Persisting selection or ignore state would retain path-derived identity, so candidate review remains memory-only and resets with new results.
- Filter controls can imply full-disk completeness; UI must state that summaries cover only the current authorized, capped result set.
- Finder reveal must not leave a security scope active or log the selected path.

## Success Criteria

- The Cleaner page no longer claims implemented directory scanning is a Phase 0 placeholder.
- Capacity refresh and directory scan refresh are separate and covered by tests.
- Users can filter and sort the current scan by metadata-derived type, size, and modification age.
- Users can select, ignore, review, and restore current-result candidates without any file mutation or persistence.
- “Show in Finder” handles success, missing file, revoked authorization, and scope release without logging names or paths.
- Focused tests, `openspec validate --all --strict`, and full `./script/build_and_run.sh verify` pass.
