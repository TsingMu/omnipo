## MODIFIED Requirements

### Requirement: Clipboard Search And History Actions

Clipboard MUST allow users to search history, filter by content type, favorite records, delete records, and copy a record back to the system pasteboard. When source application metadata is available, the main Clipboard page and floating panel MUST present it consistently as the first metadata item directly below the content preview.

#### Scenario: User searches clipboard history

- **Given** the app has stored multiple clipboard items locally
- **When** the user enters a search query in the Clipboard page
- **Then** the app shows matching local history items without sending the query off-device

#### Scenario: User copies an existing record again

- **Given** the Clipboard page shows a stored history item
- **When** the user chooses to copy that item
- **Then** the app writes that record back to the system pasteboard

#### Scenario: User views a record with source application metadata

- **Given** a clipboard history item has a non-empty source application bundle identifier
- **When** the Clipboard page or floating panel shows that item
- **Then** the source application is the first metadata item directly below the content preview
- **And** the source application name is preceded by its macOS application icon
- **And** the app prefers the localized Chinese application name or application display name
- **And** the app uses the bundle identifier and a generic application icon when application resources cannot be resolved

#### Scenario: User views a record without source application metadata

- **Given** a clipboard history item has no non-empty source application bundle identifier
- **When** the Clipboard page or floating panel shows that item
- **Then** the app does not fabricate or display a source application label
- **And** content type and relative update time remain visible
