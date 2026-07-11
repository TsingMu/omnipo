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
- **And** the user may explicitly select additional WeChat roots through a system directory picker

#### Scenario: Symbolic links are deduplicated and bounded

- **Given** candidate roots contain symbolic links
- **When** the app scans metadata
- **Then** it resolves each link to its real path and de-duplicates by real path
- **And** it does not follow links whose real path resolves outside the union of candidate roots
- **And** out-of-scope links are reported with a dedicated external-link-skipped reason, not as a permission failure
- **And** repeated out-of-scope links are aggregated to at most one issue per root
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

### Requirement: Large File and Asset Type Summary

WeChat Storage MUST summarize regular files by metadata-derived asset type and MUST provide a bounded ranking of the largest visible files without reading their contents.

#### Scenario: Visible roots contain large media files

- **Given** a readable WeChat root contains regular files
- **When** the scan completes
- **Then** it classifies files as video, image, audio, document, archive, database, or other using extensions and system type metadata
- **And** it returns a size-sorted capped large-file list
- **And** large-file display labels do not expose raw filenames or paths
- **And** each file contributes exactly once to the visible total

#### Scenario: User explicitly enables sensitive names

- **Given** sensitive names are disabled by default
- **When** the user accepts the sensitive-name warning and refreshes the scan
- **Then** large-file rows may show the real filename without its parent path
- **And** filenames remain only in the in-memory scan result
- **And** filenames are not written to logs or settings

### Requirement: Anonymous Conversation Usage

WeChat Storage MUST provide anonymous conversation usage only when a conservative directory-layout rule can attribute files without parsing messages or databases.

#### Scenario: A supported conversation media layout is present

- **Given** a readable root contains a recognized message attachment directory layout
- **When** the scanner attributes files to conversation buckets
- **Then** it returns anonymous single-chat, group-chat, or unknown-conversation labels sorted by size
- **And** it reports attribution confidence
- **And** it keeps unrecognized files in an explicit unattributed total
- **And** it does not retain or log raw conversation identifiers, contact names, group names, filenames, or paths

### Requirement: Local Conversation Names Without Database Bypass

WeChat Storage MUST allow an explicitly consenting user to assign a local in-memory name to an anonymous conversation, and MUST NOT bypass encrypted WeChat databases to obtain contact or group names.

#### Scenario: User names an anonymous conversation

- **Given** sensitive-name consent is enabled
- **When** the user assigns a contact or group name to an anonymous conversation
- **Then** the UI displays that name for the matching opaque conversation identifier
- **And** the name is cleared when sensitive names are disabled or the app exits
- **And** the name is not persisted or logged

#### Scenario: WeChat identity database is encrypted or unsupported

- **Given** the installed WeChat version does not expose a safely readable identity index
- **When** conversation storage is displayed
- **Then** the UI explains that automatic names are unavailable
- **And** the app does not extract keys, inject into WeChat, decrypt protected databases, or claim aliases are WeChat-derived names

### Requirement: Read-Only File Location and Conversation Composition

WeChat Storage MUST help the user locate large files and understand each conversation's storage composition without adding cleanup behavior or persisting sensitive paths.

#### Scenario: User reveals a consented large file

- **Given** sensitive-name consent is enabled and a scanned large file remains available
- **When** the user chooses to show that file in Finder
- **Then** Finder selects the file without modifying or deleting it
- **And** the temporary file URL exists only in the in-memory scan result
- **And** the URL is omitted from encoded models and logs
- **And** anonymous scan results do not contain a file URL or offer the Finder action

#### Scenario: User reviews a conversation's storage composition

- **Given** a conversation has attributed files of one or more asset types
- **When** the conversation row is displayed
- **Then** the UI shows the leading type percentages and a proportional segmented bar
- **And** the conversation's total bytes and file count remain visible

#### Scenario: User prepares a read-only cleanup candidate list

- **Given** a storage scan has produced large-file candidates
- **When** the user selects one or more visible candidates
- **Then** the UI shows the selected item count and estimated combined bytes
- **And** the user can review selected items separately
- **And** the user can ignore and restore candidates within the current scan result
- **And** selection and ignore state are reconciled when a refreshed scan no longer contains an item
- **And** the app does not delete, move, rename, or modify any selected file

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
