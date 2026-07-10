# wechat-storage 增量规范

## ADDED Requirements

### Requirement: Read-Only WeChat Storage Analysis

WeChat Storage MUST analyze local WeChat disk usage using file-system metadata only. It MUST NOT parse chat content, contacts, account data, databases, media contents, or message-derived metadata.

#### Scenario: User opens WeChat Manager

- **Given** the user opens WeChat Manager
- **When** the app scans visible WeChat storage roots
- **Then** the app computes storage usage from file-system metadata
- **And** the app does not open regular files to inspect content
- **And** the app does not parse message databases, contacts, media files, thumbnails, or account profiles

### Requirement: Narrow Root Discovery

WeChat Storage MUST search only known macOS WeChat storage candidates and user-authorized roots. It MUST resolve the installed WeChat bundle identifier dynamically to cover version and channel differences. It MUST NOT recursively search the whole disk or the whole home directory for WeChat-like names in the first implementation.

#### Scenario: Resolve candidate roots

- **Given** the user starts a WeChat storage scan
- **When** the app resolves storage roots
- **Then** it resolves the installed WeChat bundle identifier via the system workspace and uses it as the candidate key
- **And** it falls back to known bundle identifiers when WeChat is not resolvable
- **And** it checks Containers, Application Support, Caches, and Group Containers candidate locations
- **And** Group Containers are tagged as shared and their children use conservative categorization
- **And** missing candidate roots are treated as absent, not failures
- **And** unreadable existing roots are reported as unavailable

#### Scenario: Symbolic links are deduplicated and bounded

- **Given** candidate roots contain symbolic links
- **When** the app scans metadata
- **Then** it resolves each link to its real path and de-duplicates by real path
- **And** it does not follow links whose real path resolves outside the union of candidate roots
- **And** out-of-scope links are reported as skipped or permission-limited
- **And** symlink issues include only stable reason codes, root identifiers or kinds, and sanitized display names
- **And** symlink issues do not log or emphasize raw source paths, target paths, file names, or account-like path components

### Requirement: Categorized Storage Summary

WeChat Storage MUST summarize visible usage by broad category without implying that categories were derived from message contents.

#### Scenario: Storage roots are readable

- **Given** one or more WeChat storage roots are readable
- **When** the app scans metadata
- **Then** it reports total visible size
- **And** it groups usage into categories such as cache, media/files, logs, databases/local state, backups, configuration, and other
- **And** each category includes a user-facing privacy note or explanation

### Requirement: Partial Degradation

WeChat Storage MUST support partial results and MUST distinguish unavailable data from empty data.

#### Scenario: Some roots are unreadable

- **Given** one WeChat storage root is readable and another root is unreadable
- **When** the scan completes
- **Then** visible usage from the readable root is shown
- **And** the unreadable root is shown with an unavailable reason
- **And** the unreadable root is not counted as 0 B
- **And** the UI does not present the result as complete

### Requirement: No Cleanup in First Implementation

WeChat Storage MUST NOT delete, move, modify, or clean WeChat data in the first implementation.

#### Scenario: User reviews storage results

- **Given** a WeChat storage scan has completed
- **When** the user views categories or top storage groups
- **Then** the app does not offer a deletion or cleanup action
- **And** no WeChat file or directory is modified by the scan

### Requirement: WeChat Storage Privacy in Logs

WeChat Storage MUST NOT include user paths, file names, account identifiers, contact names, message content, database rows, or media-derived metadata in logs.

#### Scenario: WeChat storage scan writes operational logs

- **Given** the app starts, completes, or fails a WeChat storage scan
- **When** it writes logs
- **Then** logs contain only stable event names, aggregate counts, stable reason codes, and sanitized context
- **And** logs do not contain raw paths, file names, account identifiers, contact names, message content, database rows, or media-derived metadata
