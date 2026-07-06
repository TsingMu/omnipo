## ADDED Requirements

### Requirement: Read-Only Permission Audit

Permission Audit MUST read permission authorization state in a read-only manner and MUST NOT read the protected private content behind those permissions.

#### Scenario: User opens Permission Audit

- **Given** the user opens the Permission Audit page
- **When** the app performs a local permission audit
- **Then** the app reads only authorization state or availability state
- **And** the app does not read camera frames, microphone audio, contacts entries, calendar events, reminder items, photo library contents, or other protected private content

### Requirement: No TCC Mutation

Permission Audit MUST NOT modify any TCC authorization record or system permission state.

#### Scenario: Permission Audit completes

- **Given** the app runs a permission audit
- **When** the audit finishes
- **Then** no authorization record has been written, reset, or modified by the app

### Requirement: Unavailable Is Not Denied

Permission Audit MUST explicitly distinguish unavailable or unreadable permission state from denied permission state.

#### Scenario: Audit cannot read a permission category

- **Given** a permission category cannot be read because of system version, sandbox, data-source access, or unsupported platform behavior
- **When** the app renders the audit result
- **Then** the app shows that category as unavailable or unreadable
- **And** the app does not present it as denied or not granted

### Requirement: Filterable Permission Results

Permission Audit MUST allow users to filter results by permission category and application identity.

#### Scenario: User filters audit results

- **Given** the app has loaded permission audit results
- **When** the user selects a permission category or enters an application search query
- **Then** the app shows matching local audit results

### Requirement: Partial Category Degradation

Permission Audit MUST support partial degradation so that unreadable categories do not block readable categories from being shown.

#### Scenario: Some permission providers succeed and others fail

- **Given** one or more permission categories are readable and one or more categories are unavailable
- **When** the app aggregates the audit result
- **Then** the readable categories remain visible
- **And** the unavailable categories show explicit unavailability reasons

### Requirement: Permission Audit Privacy In Logs

Permission Audit MUST NOT include app path lists, raw database rows, or other sensitive permission metadata in logs.

#### Scenario: Permission Audit logs internal events

- **Given** the app performs a permission audit
- **When** the app writes operational logs
- **Then** the logs contain only stable codes or sanitized context
- **And** the logs do not contain app path lists, raw database rows, or protected private content
