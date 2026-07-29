## ADDED Requirements

### Requirement: Clipboard Image Thumbnail Preview

Clipboard MUST show a small local thumbnail for valid image history items in both the main Clipboard page and the Clipboard floating panel. Thumbnail loading MUST remain local, bounded, asynchronous, and non-blocking.

#### Scenario: User views an image record with a valid payload

- **Given** a visible clipboard history item has content type `image`
- **And** its local image payload is valid and readable
- **When** the main Clipboard page or Clipboard floating panel presents the item
- **Then** the row shows a small thumbnail generated from the local image payload
- **And** the thumbnail preserves the image aspect ratio without cropping its primary content
- **And** the main page and floating panel use consistent preview and fallback behavior
- **And** no image data is sent to a network service

#### Scenario: Thumbnail is still loading

- **Given** a visible image record has started an asynchronous thumbnail request
- **When** the request has not completed
- **Then** the row remains responsive and keeps a stable layout
- **And** the row shows a generic image placeholder in the thumbnail area
- **And** scrolling, selection, search, copy, favorite, and delete actions remain available

#### Scenario: Image payload cannot produce a thumbnail

- **Given** an image record has a missing, unreadable, corrupted, or unsupported local payload
- **When** the app attempts to load its thumbnail
- **Then** the row shows a generic image placeholder instead of a broken or blank preview
- **And** the failure does not remove the history item
- **And** the failure does not disable copy, auto-paste, favorite, or delete actions
- **And** the UI does not expose a payload path or raw decoder error

#### Scenario: User views a non-image record

- **Given** a visible clipboard history item is not an image
- **When** the main Clipboard page or Clipboard floating panel presents the item
- **Then** the row keeps its existing content-type icon and layout
- **And** the app does not request an image thumbnail for that item

#### Scenario: Thumbnail processing handles a large source image

- **Given** an image record contains a source image larger than the row preview area
- **When** the app generates its thumbnail
- **Then** thumbnail decoding is bounded to an implementation-defined maximum pixel dimension appropriate for the preview
- **And** full-size image decoding does not block the main thread
- **And** repeated visible requests may reuse a bounded in-memory cache without creating persistent thumbnail files

#### Scenario: Thumbnail activity is logged

- **Given** thumbnail loading or generation emits an operational log
- **When** the event is recorded
- **Then** the log contains only a stable event name, error code, or sanitized content type
- **And** the log does not contain image data, content hashes, record identifiers, payload file names, or local paths
