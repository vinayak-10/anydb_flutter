# Session 2026-08-05 — 15-Item Feature Planning & Grilling Session

## Overview
1. Received 12 user review comments from `reviews.txt` plus 3 new requests (keyboard auto-capitalization, disable auto-focus, drawer login button anchoring).
2. Organized into a logical 15-item execution plan grouped into 7 thematic waves (A through G).
3. Conducted a `/grill-me` alignment session to resolve ambiguities (F2 background generation flow, G1 list refresh display bug, D1 AppBar auth button, D2 drawer bottom dock, Manual Backup placement).
4. Recorded commit hash `23e3472f0a739bbbf6133c26428826d317599ee7` in `session_20260805_implementation_plan.md` as the official rollback checkpoint before code execution.

---

## Feature Master List & Status Summary

| # | Item | Group | Status | Key Files |
|---|------|-------|--------|-----------|
| **A1** | Keyboard auto-capitalization on text fields | Input UX | ✅ **COMPLETED** (`d84cc29`) | `text_ascii.dart`, `formatted_text.dart`, `element_editor.dart` |
| **A2** | Disable auto-focus on New Entry page | Input UX | ✅ **COMPLETED** (`d84cc29`) | `element_editor.dart` |
| **B1** | Remove extra padding app-wide (screen-proportional) | Form Layout | ✅ **COMPLETED** (`d84cc29`) | `text_ascii.dart`, `element_editor.dart`, `collection_view.dart` |
| **B2** | Single-line layout for date/period fields (YY/MM + Registered On) | Form Layout | 🚫 **BACKLOGGED** | `simple_account.dart` |
| **C1** | Last transaction text → Edit button on record card | Record UX | Ready for Exec (Wave 5) | `element_model.dart`, `simple_account.dart`, `collection_view.dart` |
| **C2** | Unseen record badge / indicator | Record UX | 🚫 **BACKLOGGED** (Source comment #7 was G1 refresh bug duration) | N/A |
| **D1** | Google Drive auth button in AppBar with status color + menu | Auth UI | Ready for Exec (Wave 3) | `google_drive_service.dart`, `collection_view.dart` |
| **D2** | Drawer login/logout conditional bottom dock + top Manual Backup | Auth UI | ✅ **COMPLETED** (`cbdb045`) | `drawer_content.dart` |
| **E1** | Move DB upload to background (non-blocking) | Automation | Ready for Exec (Wave 3) | `collection_view.dart` |
| **E2** | Automatic report upload to Drive (Done sequence only) | Automation | Ready for Exec (Wave 4) | `collection_view.dart`, `google_drive_service.dart` |
| **F1** | Monthly report fill-to-width + horizontal scroll | Report View | Ready for Exec (Wave 4) | `collection_view.dart` (`_buildTable` pattern) |
| **F2** | Monthly report generation as non-blocking background task | Report View | Ready for Exec (Wave 6) | `collection_view.dart`, `isolate_worker.dart` |
| **G1** | New entry duplicate display bug (list refresh race condition) | Data Integrity | Ready for Exec (Wave 5) | `collection_view.dart` (`onAdd` / `_drafts` timing) |
| **G2** | Silent Google login retry on internet reconnect | Data Integrity | ✅ **COMPLETED** (`cbdb045`) | `google_drive_service.dart` (`connectivity_plus`) |

---

## Detailed Resolved Requirements (from Grilling Session)

### 1. F2 — Monthly Report Generation as Background Task
- **Background operation**: Generation does not lock UI; user can navigate, make entries, or edit transactions freely while it runs in the background.
- **Progress indicator**: Circular spinner in `AppBar` actions with an embedded ✕ button for instant cancellation without dialogs.
- **Completion behaviour**:
  - If user is mid-entry (New Entry screen open) → show a persistent snackbar notifying report readiness; navigate to report view after entry completes.
  - Otherwise → navigate directly to `AggregatorReportView`.
- **Cancellation**: Implemented via IPC signal in `isolate_worker.dart`. `aggregator_service.dart` remains strictly hard-locked.

### 2. G1 — New Entry Duplicate Display Bug
- **Source comment clarification**: Comment #6/7 described a display artifact where a newly added record appears duplicated in the list until tapped.
- **Fix strategy**: Fix race condition in `collection_view.dart` between `_drafts.remove(newElement)` and `_init(forced: true)` list re-fetching.

### 3. D1 & D2 — Auth UI Overhaul
- **D1 (AppBar)**: Dedicated auth icon in `AppBar` — **Red** when logged out (tap to log in), **Green** when logged in (tap for popup menu with backup timestamps & logout), **Blue** when a Drive upload occurred within 1 hour.
- **D2 (Drawer)**: Single conditional bottom dock in `drawer_content.dart` switching between Login (green) and Logout (red). "Manual Backup to Drive" moved to the top of `ListView` (above Preferences) in the drawer, plus a "Backup Now" shortcut added to the D1 AppBar menu.

---

## Execution Schedule (6 Waves)

1. **Wave 1 (Input & Spacing)**: A1 + A2 + B1 (Isolated commit for B1 padding revertability).
2. **Wave 2 (Auth Drawer & Network)**: D2 + G2 (Drawer bottom dock + `connectivity_plus` reconnect).
3. **Wave 3 (Auth AppBar & Background Upload)**: D1 + E1 (AppBar auth button + `unawaited` DB upload).
4. **Wave 4 (Reports Automation & Scroll)**: E2 + F1 (Auto report upload in Done + monthly table scroll reuse).
5. **Wave 5 (Record UX & List Refresh)**: G1 + C1 (Draft duplicate display fix + last transaction edit button).
6. **Wave 6 (Isolate Background Task & Backlog)**: F2 (Background monthly generation via IPC). B2 & C2 deferred to future backlog.

---

## Rollback & Integrity Constraints

- **Rollback Commit Hash:** `23e3472f0a739bbbf6133c26428826d317599ee7`
- **Locked Files (PERMANENT):**
  `aggregator_service.dart` · `excel_binary_helper.dart` · `excel_generation_service.dart` · `extractor_service.dart` · `report_formula_service.dart` · `workbook_service.dart`
