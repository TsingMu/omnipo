# Design: WeChat Storage Analysis

## Background

The current WeChat Manager page is a placeholder. The product promise is to analyze WeChat local space while preserving privacy. WeChat data is especially sensitive, so the first implementation must be read-only and metadata-only. It should provide useful storage visibility without inspecting message content or offering cleanup.

## Capability Boundary

The first version answers:

- Which likely WeChat storage roots are visible?
- How much space is used by broad categories?
- Which top-level storage groups account for most visible usage?
- Which roots could not be read, and why?

It does not answer:

- Who the user chatted with.
- What messages, files, images, videos, or contacts contain.
- Which conversation owns a file.
- Whether a specific file is safe to delete.

## Architecture

```text
App/
  Models/
    WeChatStorage.swift
  Services/
    WeChatStorageService.swift
  Infrastructure/
    WeChat/
      DefaultWeChatStorageService.swift
      WeChatStorageScanner.swift
      WeChatStorageRootResolver.swift
  UI/
    WeChatManager/
      WeChatManagerView.swift
```

The exact file split may be adjusted during implementation, but UI must depend on `WeChatStorageService`, not direct file-system APIs.

## Models

### WeChatStorageRoot

Represents a discovered or user-authorized root:

- `id`
- `url`
- `kind`: application container, application support, cache, shared/group container, user-selected, other
- `displayName`
- `availability`

### WeChatStorageCategory

Suggested categories:

- `cache`
- `mediaAndFiles`
- `logs`
- `databasesAndState`
- `backups`
- `configuration`
- `other`

Each category must provide a user-facing privacy note and an explanation of what the size means. The UI must avoid implying that category names were derived from message contents.

### WeChatStorageGroup

Represents an aggregate path group such as a root child directory:

- `id`
- `category`
- `displayName`
- `sizeBytes`
- `fileCount`
- `lastModified`
- `riskNote`

`displayName` must be sanitized. It may use neutral labels such as "媒体与文件组 1" instead of raw private directory names when the raw name could reveal an account or contact.

### WeChatStorageScanResult

Contains:

- `totalVisibleBytes`
- `categories`
- `topGroups`
- `roots`
- `issues`
- `completedAt`

## Root Resolution

The resolver should inspect only narrow, known macOS locations and optional user-authorized directories. Candidate roots may include:

- `~/Library/Containers/<wechat-bundle-id>`
- `~/Library/Application Support/<wechat-bundle-id>`
- `~/Library/Caches/<wechat-bundle-id>`
- `~/Library/Group Containers/*<wechat-bundle-id>*` (shared containers; see below)
- user-selected directories that the user explicitly grants

`<wechat-bundle-id>` MUST be resolved dynamically, not hard-coded:

- Primary: discover the installed WeChat application via `NSWorkspace` / `/Applications` and read its `bundleIdentifier`. This covers WeChat 3.x (`com.tencent.xinWeChat`), 4.0, and channel variants whose bundle id may differ across versions.
- Fallback: if discovery fails (WeChat not installed or not resolvable), use the known `com.tencent.xinWeChat` candidate plus any version-specific ids confirmed at implementation time.

Group Containers are included as candidates because a large share of WeChat data (multi-account state, extensions) lives there. They MUST be tagged with a shared/group kind; category inference on their children stays conservative (lean toward `other`), and display names are sanitized. Inclusion is read-only metadata scanning and does not relax the no-content-parse boundary.

The resolver must tolerate missing locations. Missing roots are not errors. Unreadable existing roots produce issues.

Implementation must not recursively search all of `~/Library` or the whole home directory for "WeChat" in the first version.

## Scanning Strategy

The scanner walks visible candidate roots and reads only resource metadata:

- directory/file type
- file size or allocated size where available
- last modified date
- path components for category inference

Symbolic links MUST be handled explicitly:

- Resolve each symlink to its real path before accounting.
- De-duplicate by real path so the same physical directory is not counted twice across roots or via self-referential links.
- Do not follow links whose real path resolves outside the union of candidate roots; surface them as a skipped or permission-limited issue rather than reading foreign metadata.
- Symlink issues must remain privacy-safe: include only stable reason codes, root id/kind, and sanitized display names. Do not log or emphasize raw symlink source paths, target real paths, file names, or account-like path components.

The scanner must not:

- open regular files to inspect bytes
- parse SQLite databases
- generate thumbnails
- inspect image/video metadata
- read plist contents unless the design is explicitly expanded later

Large scans must support cancellation and should cap top group count.

## Category Inference

Category inference is path-based and conservative:

- paths containing cache-like components map to `cache`
- log-like components map to `logs`
- database/state-like components map to `databasesAndState` but are never opened
- file/media-like components map to `mediaAndFiles`
- unknown paths map to `other`

When uncertain, prefer `other` and show neutral language.

## Permission and Degradation

Unavailable reasons include:

- root missing
- permission limited
- TCC or sandbox limited
- resource unavailable
- scan cancelled
- unknown

The UI must show partial results and issues together. It must not show "0 B" for unreadable roots unless the root was actually readable and empty.

The page may provide a system settings shortcut for Full Disk Access as a supplemental read permission, but must not claim that Full Disk Access guarantees access to every WeChat file.

## UI

WeChat Manager should be a real tool screen, not a marketing page:

- header with refresh and scan state
- privacy boundary notice
- total visible size summary
- category list or chart
- top storage groups
- unavailable roots panel
- empty state that distinguishes "no WeChat roots found" from "roots unreadable"

No raw private paths should be emphasized as primary UI. If paths are shown for debugging or transparency, they must be secondary and truncatable.

## Logging

Logs may include:

- scan started/completed/failed stable event names
- aggregate counts
- stable unavailable reason codes
- duration buckets

Logs must not include:

- user paths
- file names
- account identifiers
- contact names
- message content
- raw WeChat database names when they may identify user data

## Verification

- Unit tests for category inference, size aggregation, unavailable roots, cancellation, and log sanitization.
- Integration-style tests using temporary fixture directories, not real WeChat data.
- Manual verification on a machine with and without WeChat roots, covering partial unreadable state.
- Full `./script/build_and_run.sh verify`.
