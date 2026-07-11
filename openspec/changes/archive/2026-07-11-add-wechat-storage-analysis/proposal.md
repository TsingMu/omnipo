# Proposal: Add WeChat Storage Analysis

## Summary

Replace the WeChat Manager placeholder with a local, read-only WeChat storage analysis workflow. The first implementation will discover likely WeChat data roots, show explicit permission/availability status, compute category-level size summaries from file metadata, and present large storage groups without reading chat content or deleting data.

## Motivation

Omnipo already exposes a WeChat Manager entry and Launcher command, but the page is still a placeholder. Users can navigate to "微信管理" yet cannot see where WeChat uses local disk space or why data cannot be read. Because WeChat data can include highly sensitive chats, files, media, contacts, accounts, and device identifiers, this capability needs a conservative first version with clear privacy boundaries before any cleanup action is introduced.

## Goals

- Discover likely local WeChat storage locations without scanning the whole disk.
- Show readable, unavailable, and permission-limited states without treating unreadable data as zero usage.
- Categorize storage into cache, media/files, logs, databases/local state, backups, and other app data using paths and metadata only.
- Compute sizes from file-system metadata without opening or parsing message databases, chat content, contacts, media content, or account data.
- Present category totals, top storage groups, last modified time where available, and clear privacy notices.
- Keep all processing local and exclude paths, file names, account identifiers, and chat-derived data from logs.

## Non-Goals

- No deletion or cleanup execution in this change.
- No parsing SQLite databases, message records, contacts, account profiles, media thumbnails, or file contents.
- No network upload, cloud sync, remote rule download, or telemetry of WeChat paths.
- No bypassing TCC, App Sandbox, SIP, file-system permissions, or WeChat app protections.
- No claim that unavailable roots contain zero bytes.
- No support for Windows, mobile WeChat, or non-macOS WeChat storage.

## Scope

This change covers:

- `wechat-storage` OpenSpec capability.
- Models for roots, categories, storage groups, scan results, and unavailable reasons.
- `WeChatStorageService` protocol and default local implementation.
- A conservative scanner for known macOS WeChat root candidates and user-authorized roots.
- A real WeChat Manager page showing summary, categories, unavailable states, and refresh.

## User Value

- Users can understand WeChat local disk usage without exposing message content.
- Users can distinguish "not scanned / no permission / unreadable" from "no data".
- Future cleanup can build on a categorized, audited, read-only foundation.

## Risks

- WeChat storage paths vary by version, channel, and user setup.
- Some roots may be protected by App Sandbox, TCC, or Full Disk Access behavior.
- File and directory names may contain private information and must not enter logs.
- Category inference from paths can be imperfect; UI must present it as storage analysis, not semantic chat analysis.

## Success Criteria

- Opening WeChat Manager does not read chat contents or trigger deletion.
- Readable test roots produce deterministic category totals.
- Unreadable roots show explicit unavailable reasons.
- Logs contain only stable codes and aggregate counts.
- Full project verify passes.
