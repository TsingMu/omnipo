# Design: Harden Local Daily Use

## Background

Omnipo is currently intended for one user's local Mac rather than public distribution. The application already has broad feature coverage and a passing unit-test baseline. The next reliability layer should therefore remove single-subsystem startup failures, reconcile persisted UI preferences with system-owned state, make authorization recovery visible, and verify background lifecycle boundaries.

## Verified Local Baseline

- Omnipo `0.1.0` at commit `554c3fe` (`v0.1.0-alpha`).
- macOS 26.5, Xcode 26.6, Apple Swift 6.3.3.
- Xcode Debug build and the existing full XCTest suite passed before this change was opened.
- Device name, account name, local paths, installed applications, and other private machine details are intentionally not recorded.

## Capability Boundary

This change may adjust application foundation, clipboard availability, disk authorization presentation, WeChat authorization presentation, and lifecycle coordination. It must not introduce deletion, cloud services, telemetry, publishing infrastructure, or permanent recovery actions against user data.

## Observed Failure Modes

The audit uses stable local issue identifiers:

- `LOCAL-001`: launch-at-login persisted/effective state divergence.
- `LOCAL-002`: clipboard initialization terminates the full application.
- `LOCAL-003`: disk scan bookmark failure collapses into unconfigured state.
- `LOCAL-004`: invalid WeChat bookmarks are silently pruned.
- `LOCAL-005`: background activity lifecycle needs cross-feature verification.

### Launch at Login

`SettingsView` currently initializes its toggle from `SettingsKey.launchAtLogin` and writes the preference before invoking `SMAppService.mainApp.register()` or `unregister()`. A failed request can therefore leave three different states: requested, persisted, and effective.

### Clipboard Startup

`DependencyContainer.makeClipboardService` currently uses `preconditionFailure` when Application Support, SQLite, schema initialization, or binary storage preparation fails. Clipboard persistence is optional to the rest of Omnipo, so this is an unnecessarily global failure.

### Persisted Folder Authorization

Security-scoped bookmarks can be stale, malformed, revoked, moved, or denied. The disk root manager returns `nil` for several distinct cases. The WeChat manager prunes invalid bookmarks. Both behaviors need a safe, explicit recovery state without retaining or logging raw paths.

### Background Work

System monitoring is continuous and should run only while its feature is visible. Clipboard monitoring is user-enabled and is intentionally application-wide. Searches and scans are finite and must be cancellable, release security scopes, and ignore stale results. These categories must not be governed by one blanket stop policy.

## Architecture

```text
SettingsView
  -> LaunchAtLoginService
       -> SystemLaunchAtLoginService (SMAppService)

DependencyContainer
  -> ClipboardService factory
       -> DefaultClipboardService
       -> UnavailableClipboardService (sanitized startup reason)

AuthorizedRootManager / WeChatStorageAuthorizationManager
  -> AuthorizationAvailability
       -> notConfigured
       -> available(safe display name where allowed)
       -> reauthorizationRequired(stable reason)

Feature View / Store
  -> activate / deactivate / cancel
  -> service task
  -> generation or task identifier rejects stale completion
```

## Launch-at-Login State

Introduce a small injectable service protocol rather than referencing `SMAppService` directly from the SwiftUI view. The protocol exposes a sanitized effective status and an operation to request enable or disable.

The settings toggle must be derived from effective system state. On change:

1. Disable repeated mutations while the request is in flight.
2. Ask the service to change the effective state.
3. On success, refresh the effective status and persist the confirmed value only if a cached preference is still useful.
4. On failure, restore the effective toggle state and show a safe recovery message.
5. Never log `localizedDescription`, paths, account names, or raw service payloads.

Approval-required and unsupported states remain visible and must not be presented as enabled.

## Clipboard Degradation

Replace the global `preconditionFailure` path with an `UnavailableClipboardService` that conforms to `ClipboardService`.

The unavailable service:

- never starts pasteboard monitoring;
- returns a stable sanitized `AppError` for storage-dependent operations;
- reports capture as disabled;
- allows Clipboard UI to show an unavailable state with a retry or restart suggestion;
- does not delete, rename, recreate, or migrate the failed database;
- does not include the underlying database path or SQLite message in logs.

Dependency construction logs only a stable failure code and continues creating the remaining services.

## Authorization Availability

Introduce explicit availability instead of using `URL?` as both configuration and error state. At minimum, distinguish:

- `notConfigured`: no persisted bookmark exists;
- `available`: a bookmark resolved and its security scope started;
- `reauthorizationRequired`: persisted authorization existed but could not be resolved or activated.

Stale bookmarks that can be refreshed remain available and replace their stored data. Invalid bookmarks may be removed only after the manager records the recovery-required state for UI presentation. Logs and Codable models contain stable reason codes, never raw paths or bookmark bytes.

Disk and WeChat UIs provide a direct directory picker from the recovery state. They must not call failed authorization "0 B" or "no data".

## Lifecycle Policy

Classify background activity explicitly:

| Activity | Lifetime | Required behavior |
| --- | --- | --- |
| System metrics and app-usage sampling | Feature-visible | Start on activation; stop on deactivation; ignore late results |
| Clipboard monitoring | Application-wide while user-enabled | Continue without the Clipboard view; stop immediately when disabled |
| Launcher search | Query/panel | Cancel when query is replaced or panel closes |
| Disk and WeChat scans | Finite user operation | Remain cancellable; release security scope on every terminal path; reject stale completion |
| Uninstall execution | Explicit confirmed operation | Do not auto-cancel solely because navigation changes; preserve result reporting |

Focused tests should prove these policies. Code changes are required only where the audit finds a violation.

## UI and Diagnostics

Recovery messages should state the affected capability, the safe reason, and the next action. They must not display private raw paths except for a user-approved final path component already allowed by the relevant capability.

Manual evidence stays outside git if it contains application names, folder names, account identifiers, screenshots, or other private local state. The committed task list records only pass/fail and stable issue references.

## Verification

- Unit-test launch-at-login state mapping, successful changes, failure rollback, and approval-required status.
- Inject clipboard initialization failure and verify a usable dependency container plus unavailable Clipboard behavior.
- Unit-test missing, valid, stale-refreshable, malformed, and inaccessible bookmarks.
- Test continuous monitor activation/deactivation and stale-result rejection.
- Run focused tests after each implementation section.
- Run `openspec validate --all --strict` and full Xcode tests.
- Complete the real-account smoke matrix for launch, shortcuts, clipboard, disk authorization, uninstall, permission audit, WeChat analysis, system monitor, navigation, relaunch, and cancellation.
