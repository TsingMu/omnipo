# Proposal: Harden Local Daily Use

## Why

The `v0.1.0-alpha` baseline builds and passes unit tests, but daily local use can still turn a launch-at-login registration failure, clipboard database failure, or expired directory authorization into misleading UI or a whole-application startup failure. Because Omnipo is intended for long-running use on one local Mac, truthful recovery and bounded background activity are now more valuable than distribution infrastructure or additional cleanup features.

## What Changes

- Derive launch-at-login presentation from the effective `SMAppService` state and roll back failed requests instead of persisting an unconfirmed value.
- Replace the clipboard initialization `preconditionFailure` path with an unavailable service that disables only clipboard-dependent operations.
- Distinguish never-authorized disk and WeChat roots from stale, malformed, moved, or inaccessible persisted authorization, with a direct reauthorization path.
- Audit and test the lifecycle policy for continuous system sampling, application-wide clipboard monitoring, Launcher search, finite scans, and confirmed uninstall execution.
- Add deterministic recovery tests and a privacy-safe manual smoke matrix for the real local account.
- Keep all diagnostics local and sanitized.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `application-foundation`: Require truthful macOS-managed settings, non-fatal degradation of optional subsystems, and explicit background activity lifetimes.
- `clipboard`: Require a safe unavailable state when local clipboard persistence cannot initialize.
- `disk-analysis`: Require visible recovery when a persisted scan-directory bookmark can no longer be used.
- `wechat-storage`: Require partial results and reauthorization state when user-selected WeChat roots expire or become inaccessible.

## Impact

- **Application and UI:** `DependencyContainer`, `SettingsView`, Clipboard UI, Cleaner UI, WeChat Manager UI, and lifecycle coordination.
- **Service boundaries:** a new injectable launch-at-login boundary, clipboard availability/fallback behavior, and explicit authorization availability models.
- **Infrastructure:** `SMAppService`, Clipboard SQLite/Application Support initialization, and security-scoped bookmark resolution.
- **Tests:** launch-at-login state mapping, clipboard initialization failure, bookmark recovery, cancellation, stale-result rejection, and real-account smoke verification.
- **Dependencies:** no third-party dependency or network service is introduced.

## Non-Goals

- No Developer ID signing, notarization, DMG/PKG creation, App Store work, public telemetry, cloud CI, or automatic updates.
- No disk cleanup execution, permanent deletion, WeChat modification, or new uninstall mode.
- No bulk backup/export or destructive "reset all Omnipo data" action in this change.
- No automatic deletion or replacement of a damaged clipboard database without explicit future design and user confirmation.
- No promise that a user-started finite scan survives application termination.

## Risks

- `SMAppService` behavior varies between an Xcode-launched app and a copied application bundle; unsupported and approval-required states must remain honest.
- A fallback clipboard service must not accidentally re-enable capture or overwrite local data.
- Bookmark errors may contain private paths; models, UI, and logs must expose only sanitized reason codes and safe display text.
- Lifecycle changes can introduce races between cancellation and late async results; stores must ignore stale completions.

## Success Criteria

- Launch-at-login state is derived from the system service, and a failed toggle does not persist a false state.
- A forced clipboard initialization failure still allows Omnipo to open and use non-clipboard destinations.
- Expired or inaccessible bookmarks display a reauthorization state and are not reported as zero data.
- Continuous system monitoring stops after leaving its view; cancellation and late-result tests pass for affected stores.
- `openspec validate --all --strict` and full `xcodebuild test` pass.
- The real-account smoke checklist is completed without privacy-sensitive evidence being committed.
