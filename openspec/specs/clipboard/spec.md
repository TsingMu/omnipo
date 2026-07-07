# clipboard Specification

## Purpose

Clipboard provides local-only clipboard history inside Omnipo, including first-run acknowledgement, supported content capture, search, history actions, copy-back, auto-paste downgrade, and privacy constraints.

## Requirements

### Requirement: Clipboard First-Run Acknowledgement

Clipboard MUST require an explicit first-run acknowledgement before it begins monitoring or storing clipboard history.

#### Scenario: User opens Clipboard for the first time

- **Given** the user has never acknowledged Clipboard local storage behavior
- **When** the user opens the Clipboard page
- **Then** the app shows a clear notice that clipboard contents will be stored only on the local device
- **And** the notice warns that copied content may include passwords, verification codes, links, file paths, or other sensitive data
- **And** Clipboard monitoring does not start before the user confirms

#### Scenario: User confirms first-run notice

- **Given** the first-run notice is visible
- **When** the user confirms the notice
- **Then** the app stores the acknowledgement locally
- **And** Clipboard monitoring may start
- **And** subsequent Clipboard page visits do not require the same notice again unless the acknowledgement is reset

### Requirement: Local-Only Clipboard History

Clipboard MUST store clipboard history only on the local device and MUST NOT upload clipboard contents to any remote service.

#### Scenario: Clipboard captures content

- **Given** Clipboard has been enabled after first-run acknowledgement
- **When** the system pasteboard changes to supported content
- **Then** the app may persist the clipboard content locally for history purposes
- **And** the content is not uploaded, synced, or sent to any network service

### Requirement: Supported Clipboard Content Types

Clipboard MUST support local history capture for text, rich text, HTML, images, and file paths.

#### Scenario: User copies supported content

- **Given** Clipboard monitoring is active
- **When** the user copies plain text, rich text, HTML, an image, or a file path
- **Then** the app records the content as a clipboard history item of the corresponding content type

### Requirement: Clipboard Search And History Actions

Clipboard MUST allow users to search history, filter by content type, favorite records, delete records, and copy a record back to the system pasteboard.

#### Scenario: User searches clipboard history

- **Given** the app has stored multiple clipboard items locally
- **When** the user enters a search query in the Clipboard page
- **Then** the app shows matching local history items without sending the query off-device

#### Scenario: User copies an existing record again

- **Given** the Clipboard page shows a stored history item
- **When** the user chooses to copy that item
- **Then** the app writes that record back to the system pasteboard

#### Scenario: User views a record with source application metadata

- **Given** a clipboard history item has a source application bundle identifier
- **When** the Clipboard page or floating panel shows that item
- **Then** the app prefers the localized Chinese application name or application display name
- **And** the app uses the bundle identifier only when no application name can be resolved

### Requirement: Auto-Paste Permission Downgrade

Clipboard MUST degrade auto-paste to copy-only behavior when the app does not have required accessibility permission.

#### Scenario: User requests auto-paste without permission

- **Given** the app does not have accessibility permission
- **When** the user chooses a clipboard action that requests auto-paste
- **Then** the app still copies the selected record back to the system pasteboard
- **And** the app does not block the copy action
- **And** the app clearly explains that auto-paste requires accessibility permission
- **And** the app opens the macOS Accessibility authorization prompt or settings entry

### Requirement: Clipboard Privacy In Logs

Clipboard MUST NOT include clipboard raw content, search queries, file paths, or file names in logs.

#### Scenario: Clipboard logs internal events

- **Given** Clipboard monitoring, searching, saving, or copy-back operations occur
- **When** the app writes operational logs
- **Then** the logs contain only stable codes or sanitized context
- **And** the logs do not contain clipboard raw content, search queries, file paths, or file names

### Requirement: Clipboard Floating Panel Shortcut

Clipboard MUST support a clippy-style shortcut-invoked floating panel. The floating panel MUST reuse Omnipo's unified shortcut service and Clipboard data/action services rather than migrating clippy's `HotKeyManager`, `HotKeyConfig`, or a parallel clipboard stack.

#### Scenario: User invokes the Clipboard panel shortcut after acknowledgement

- **Given** the user has acknowledged local Clipboard storage
- **And** Clipboard monitoring is enabled
- **When** the user presses the configured Clipboard panel shortcut
- **Then** the system shows or toggles the Clipboard floating panel
- **And** the panel focuses search input by default
- **And** the panel MUST list history through the same Clipboard service/repository used by the main Clipboard page

#### Scenario: User double-clicks a Clipboard panel record

- **Given** the Clipboard floating panel is visible
- **And** auto-paste is enabled
- **When** the user double-clicks a Clipboard history record
- **Then** the app writes that record back to the system pasteboard
- **And** the panel hides before the synthetic paste event is sent
- **And** the synthetic paste event targets the application that was frontmost before the panel opened when that target is known

#### Scenario: User invokes the shortcut before acknowledgement

- **Given** the user has not acknowledged local Clipboard storage
- **When** the user presses the configured Clipboard panel shortcut
- **Then** the system MAY open a first-run acknowledgement entry point or route to the Clipboard page
- **And** Clipboard monitoring and persistence MUST NOT start before acknowledgement

#### Scenario: User dismisses the Clipboard floating panel

- **Given** the Clipboard floating panel is visible
- **When** the user presses the same Clipboard panel shortcut again or presses Escape
- **Then** the panel hides without mutating Clipboard history

#### Scenario: User configures the Clipboard panel shortcut

- **Given** the user opens Omnipo Settings
- **When** the user records a valid shortcut for the Clipboard panel
- **Then** the app registers that shortcut through the unified shortcut service
- **And** the app stores the shortcut locally
- **And** the Launcher shortcut remains independently configurable

### Requirement: Clippy-Style Clipboard Settings

Clipboard MUST expose clippy-style clipboard settings inside Omnipo Settings while preserving Omnipo's existing settings service and UI architecture.

#### Scenario: User configures general Clipboard behavior

- **Given** the user opens Omnipo Settings
- **When** the user changes auto-paste or Clipboard panel position
- **Then** the app stores the preference locally
- **And** the Clipboard floating panel uses the saved behavior

#### Scenario: User configures Clipboard retention

- **Given** Clipboard monitoring is active
- **When** the user configures maximum record count, retention days, or maximum storage size
- **Then** the app stores the preference locally
- **And** newly persisted Clipboard history is pruned according to those limits

#### Scenario: User configures Clipboard exclusion rules

- **Given** Clipboard monitoring is active
- **When** the user adds excluded applications or text-pattern exclusion rules
- **Then** matching Clipboard changes are not persisted to history

#### Scenario: User configures advanced Clipboard options

- **Given** the user opens Omnipo Settings
- **When** the user changes menu bar icon visibility, Clipboard polling interval, or image quality
- **Then** the app stores the preference locally
- **And** supported runtime components use the saved preference where applicable
