# app-uninstaller Specification

## Purpose

App Uninstaller provides a local, user-confirmed macOS application uninstall workflow in Omnipo. It lists visible installed applications, builds uninstall previews, supports application-only uninstall and full removal, and deletes selected items only after explicit confirmation. Full removal includes the application bundle and safely attributable associated files such as caches, preferences, logs, application support data, saved state, and containers.

## Requirements

### Requirement: Installed Application Discovery

App Uninstaller MUST discover locally visible macOS applications and present enough identity information for the user to choose the correct target.

#### Scenario: User opens App Uninstaller

- **Given** the user opens the App Uninstaller page
- **When** the app scans visible application locations
- **Then** the app lists discovered `.app` bundles
- **And** each row includes the application name, bundle identifier when available, icon when resolvable, size when available, and source location category
- **And** unreadable scan locations are shown as unavailable without blocking readable locations

### Requirement: Protected Application Degradation

App Uninstaller MUST identify applications that should not be deleted by Omnipo and prevent destructive actions for them.

#### Scenario: Application is system protected

- **Given** a discovered application is located in a protected system location or is otherwise marked non-removable
- **When** the user selects that application
- **Then** the app shows the protection reason
- **And** the app does not allow uninstall execution for that application

### Requirement: Uninstall Mode Selection

App Uninstaller MUST allow the user to choose between removing only the application bundle and fully removing the application plus associated files.

#### Scenario: User chooses application-only uninstall

- **Given** the user selects a removable application
- **When** the user chooses application-only uninstall
- **Then** the uninstall preview includes the application bundle
- **And** the preview does not include caches, preferences, logs, containers, or other associated files

#### Scenario: User chooses full removal

- **Given** the user selects a removable application
- **When** the user chooses full removal
- **Then** the uninstall preview includes the application bundle
- **And** the app scans for safely attributable associated files
- **And** the preview groups associated files by category
- **And** each category explains the consequence of deleting files in that category

### Requirement: Full Removal Associated Files

Full removal MUST include the selected application and safely attributable associated files such as cache files, support files, preferences, logs, saved state, and containers.

#### Scenario: Full removal preview finds associated files

- **Given** an application has associated cache, application support, preferences, logs, saved state, or container files
- **When** the app builds a full removal preview
- **Then** the preview includes the application bundle
- **And** the preview includes high-confidence associated files by default
- **And** the preview may include medium-confidence or low-confidence associated files as optional, not-default-selected items
- **And** the preview shows unavailable or risky associated locations without silently selecting them

#### Scenario: Associated file is a cache

- **Given** the selected application has a cache directory that is safely attributable to its bundle identifier or exact application identity
- **When** the user builds a full removal preview
- **Then** the cache directory is included in the full removal preview
- **And** it is eligible for deletion when selected by the user

### Requirement: Categorized Full Removal Consequences

App Uninstaller MUST show full removal preview files by category and MUST explain the consequence of deleting each category.

#### Scenario: Full removal preview is displayed

- **Given** the user builds a full removal preview
- **When** associated files are shown
- **Then** files are grouped by category
- **And** each visible category includes a user-readable deletion consequence
- **And** the consequence text is visible in the preview, not only in external documentation

#### Scenario: Cache category is shown

- **Given** the full removal preview includes cache files
- **When** the preview renders the cache category
- **Then** the category explains that deleting cache files usually frees space but the application may rebuild them and may open more slowly next time

#### Scenario: Preferences category is shown

- **Given** the full removal preview includes preferences files
- **When** the preview renders the preferences category
- **Then** the category explains that deleting preferences may reset application settings, window layout, recent items, or local state

#### Scenario: Application support category is shown

- **Given** the full removal preview includes application support files
- **When** the preview renders the application support category
- **Then** the category explains that these files may contain local databases, downloaded resources, plugins, offline data, or account-related local state
- **And** the category explains that selected data may not be recoverable by Omnipo after deletion

#### Scenario: Container category is shown

- **Given** the full removal preview includes container or group container files
- **When** the preview renders the container category
- **Then** the category explains that containers may include sandboxed local data, caches, and settings
- **And** group containers explain that deleting them may affect related applications from the same developer

### Requirement: User Selection in Full Removal Preview

App Uninstaller MUST allow the user to control which associated files are removed during full removal.

#### Scenario: User excludes an associated file

- **Given** the full removal preview contains selectable associated files
- **When** the user deselects one associated file
- **Then** that file is excluded from the execution plan
- **And** the total selected size and selected item count update accordingly

### Requirement: Conservative Ownership and Risk Handling

App Uninstaller MUST avoid automatically selecting files whose ownership is ambiguous or risky.

#### Scenario: Associated file ownership is ambiguous

- **Given** a candidate file is matched only by fuzzy name matching or is located in a shared container
- **When** the app builds a full removal preview
- **Then** the file is not selected by default
- **And** the UI explains that ownership is uncertain or shared

#### Scenario: Candidate file is high risk

- **Given** a candidate file is a user document, keychain item, chat database, browser profile, protected system item, or otherwise high-risk file
- **When** the app builds a full removal preview
- **Then** the app excludes it from automatic deletion
- **And** the app either omits it or displays it as not removable with a reason

### Requirement: Explicit Confirmation Before Deletion

App Uninstaller MUST require explicit confirmation before deleting any application or associated file.

#### Scenario: User starts uninstall

- **Given** the user has selected an uninstall mode and reviewed the plan
- **When** the user clicks the uninstall action
- **Then** the app shows a confirmation prompt
- **And** the prompt states whether the operation is application-only uninstall or full removal
- **And** the prompt summarizes the selected item count and total selected size
- **And** deletion does not begin until the user confirms

### Requirement: Permission Architecture

App Uninstaller MUST build previews and execute deletion only within the capabilities actually granted to the app. It MUST prefer user-authorized directories and security-scoped access for associated file scanning, MAY use Full Disk Access as a supplemental protected-path read authorization, and MAY use Finder automation to move user-confirmed items to Trash. It MUST NOT bypass SIP, TCC, sandbox, or file-system permissions.

#### Scenario: Associated file scan lacks required access

- **Given** the user has not authorized a directory and the app cannot read an associated-file location
- **When** the app scans for associated files
- **Then** the app reports associated files as unavailable
- **And** the app explains whether the missing access is a directory authorization, Full Disk Access, TCC, sandbox, or file-system limitation when known
- **And** the app guides the user to the relevant authorization path when one is available
- **And** the app does not present the absence as "no associated files"

#### Scenario: Deletion requires Finder automation authorization

- **Given** the user has not authorized Omnipo to control Finder
- **When** the user attempts to execute an uninstall plan
- **Then** the app does not perform Finder-based deletion
- **And** the app explains that Finder automation authorization is required
- **And** the app guides the user to grant automation permission
- **And** items inside already authorized writable directories may still be moved to Trash without Finder automation

#### Scenario: Application bundle in /Applications is removable via Finder

- **Given** the user has authorized Finder automation
- **When** the user confirms uninstall of an application in `/Applications`
- **Then** the app instructs Finder to delete the application bundle
- **And** the bundle is moved to Trash by Finder
- **And** the result marks the bundle as removed

### Requirement: Trash-First Deletion

App Uninstaller MUST move selected items to the system Trash and MUST NOT provide application-internal permanent deletion in the first implementation.

#### Scenario: Selected items can be moved to Trash

- **Given** the user confirms an uninstall plan
- **When** selected files are removable through an authorized directory or Finder automation
- **Then** the app moves the selected files to Trash
- **And** the result marks those files as removed from their original locations

#### Scenario: Trash deletion fails

- **Given** the user confirms an uninstall plan
- **When** one or more selected files cannot be moved to Trash
- **Then** the app reports the failure
- **And** the app does not automatically permanently delete those files
- **And** the app does not offer application-internal permanent deletion in the first implementation
- **And** the app may guide the user to handle the remaining files manually in Finder

### Requirement: Partial Failure Results

App Uninstaller MUST report per-item results so that partial success does not hide failed or skipped files.

#### Scenario: Some selected files fail to delete

- **Given** the user confirms an uninstall plan with multiple selected items
- **When** some items are removed and others fail or are skipped
- **Then** the final result shows success, failure, and skipped counts
- **And** failed or skipped items include user-readable reasons
- **And** successfully removed items remain marked as removed

### Requirement: Running Application Handling

App Uninstaller MUST avoid forcefully terminating applications in the first implementation.

#### Scenario: Selected application is running

- **Given** the user selects an application that is currently running
- **When** the user attempts to uninstall it
- **Then** the app warns that the application is running
- **And** the app asks the user to quit the application before retrying
- **And** the app does not force quit the application

### Requirement: Uninstaller Privacy in Logs

App Uninstaller MUST NOT include user paths, file names, associated file lists, or application private data in logs.

#### Scenario: App Uninstaller logs operation results

- **Given** the app discovers applications, builds an uninstall plan, or executes deletion
- **When** the app writes operational logs
- **Then** logs contain only stable codes, sanitized context, and aggregate counts
- **And** logs do not contain user paths, file names, selected associated file details, or application private data
