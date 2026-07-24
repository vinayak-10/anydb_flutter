# anydb_flutter — Project Context Index

> [!CAUTION]
> **CRITICAL STABILITY RULE — REPORTING ENGINE IS PERMANENTLY HARD-LOCKED**
>
> Under **no circumstances** should any changes be made to the reporting engine, formula parsing, aggregation, XML post-processing, or any related files:
> `aggregator_service.dart` · `excel_binary_helper.dart` · `excel_generation_service.dart` · `extractor_service.dart` · `report_formula_service.dart` · `workbook_service.dart` · related models/services
>
> If **any planned change** has a potential cascading effect on these files or their data structures: **STOP immediately, notify the user explicitly, and revert to the nearest safe code state before proceeding.**

---

## How to Use This File

This file is the **summary and index**. Each session's full details live in `.chat_context/` as one file per session.

- **Quick orientation** → read the sections below.
- **Deep context on any feature** → open the linked session file.
- **Codebase map** → see [`.chat_context/codebase_index.md`](.chat_context/codebase_index.md).

---

## Current State

| Item | Value |
|------|-------|
| **Branch** | `dev` |
| **Last stable commit** | `3c7087c` (batch `<v>` tag preservation fix) → merged to `master` via `ccb61da` |
| **Pending commit** | Session 2026-06-27: `element_db.dart`, `sqlite_helper_native.dart`, `storage_service.dart` (report cache fix + UI features) |
| **Flutter analyze** | 0 errors |
| **Git remotes** | `local-server` (local) + `origin` (`git@github.com:vinayak-10/anydb_flutter.git`) |

---

## Session History (newest first)

| Date | File | What Happened |
|------|------|---------------|
| 2026-07-23 | [session_20260723_feedback_fixes.md](.chat_context/session_20260723_feedback_fixes.md) | Save/action text labels, tablet ribbon scroll padding fix, and Google auto-login retry on internet reconnect. |
| 2026-07-06 | [session_20260704_payment_mode_validation_analysis.md](.chat_context/session_20260704_payment_mode_validation_analysis.md) | Payment mode validation, custom ribbon ordering, and adaptive spacing layout. Implemented. |

---

## Stabilized Feature Map

Full details for each feature are in the session files above. This table is a quick reference.

| # | Feature | Key Files | Session |
|---|---------|-----------|---------|
| 1 | High-performance report engine (formula alignment, `<v>` tag preservation, namespace-insensitive XML) | `excel_binary_helper.dart` ⚠️ · `excel_generation_service.dart` ⚠️ · `extractor_service.dart` ⚠️ | 2026-06-26 Parts 1–4 |
| 2 | SQLite global overhaul (B-tree, partial index, business key, lazy model) | `sqlite_helper_native.dart` · `element_db.dart` · `element_model.dart` | Various |
| 3 | Google Sign-In + Drive backup (7.x API, `authorizeScopes`, `was_logged_in`) | `google_sign_in_service.dart` · `drawer_content.dart` | Early sessions |
| 4 | Security: compile-time secrets, Gradle memory, universal safe areas | `secrets.json` · `android/gradle.properties` | Early sessions |
| 5 | Storage resilience: atomic writes, mutex, self-healing JSON | `file_store.dart` · `storage_service.dart` | Early sessions |
| 6 | Web quota management: DOM QuotaExceededError catch, in-memory fallback | `web_store.dart` | Early sessions |
| 7 | Persistent isolate worker pool (dual isolates, IPC, spinner yielding) | `isolate_worker.dart` | Multi-session |
| 8 | Concurrent record drafts + adaptive speed dial FAB | `element_editor.dart` · `home_page.dart` | Early sessions |
| 9 | Tablet split-view responsive layout | `collection_view.dart` · `element_view.dart` | Early sessions |
| 10 | Google-Search landing page (dynamic logo, live search, speed dial overlay) | `landing_page.dart` · `main.dart` | Early sessions |
| 11 | Custom logo adaptive icon + Web favicon/PWA overhaul | `assets/` · `android/res/` · `web/` | Early sessions |
| 12 | Multi-worker SQLite isolate pool (direct IPC, warm cache, 30% boot, WAL) | `isolate_worker.dart` · `sqlite_helper_native.dart` | Multi-session |
| 13 | Active pre-warming, inactive lazy-load, filter percolation | `isolate_worker.dart` · Riverpod providers | Multi-session |
| 14 | Feedback toast + empty state toolkit | `feedback_toast.dart` · `empty_state_view.dart` | Early sessions |
| 15 | Premium floating dock, keyboard FAB auto-hide, empty DB alert | `main.dart` · `home_page.dart` | Early sessions |
| 16 | Private GitHub remote + Apple Actions pipeline | `.github/workflows/` | Early sessions |
| 17 | Sticky header + fit-to-width report view | `collection_view.dart` (report view) | Mid sessions |
| 18 | Force-reload on report preview + Done sequence | `collection_view.dart` · `aggregator_service.dart` ⚠️ | Mid sessions |
| 19 | SQLite 128MB RAM page cache + Android `largeHeap` | `sqlite_helper_native.dart` · `AndroidManifest.xml` | Mid sessions |
| 20 | Adaptive floating dock + font scale clamp | `main.dart` | Mid sessions |
| 21 | Compact reports tab UI + cradle FAB home alignment | `collection_view.dart` | Mid sessions |
| 22 | Schema auto-select + startup countdown banner | `main.dart` · `settings_state.dart` | Mid sessions |
| 23 | Windows CI pipeline + CMakeLists C++ wrapper fix | `.github/workflows/build_windows.yml` · `windows/flutter/CMakeLists.txt` | Mid sessions |
| 24 | Android + Apple CI/CD pipeline with signing fallbacks | `.github/workflows/build_android.yml` · `build_apple.yml` | Mid sessions |
| 25 | High-performance date pre-filtering for daily reports | `isolate_worker.dart` | Mid sessions |
| 26 | **[2026-06-27]** Report cache staleness fix (4-bug root cause, 3-file fix) | `element_db.dart` · `sqlite_helper_native.dart` · `storage_service.dart` | 2026-06-27 (Part 1) |
| 27 | **[2026-06-27]** Edit FAB on record cards, schema `defaultValue` fix, purge → deleted only, 5-day grace, schema auto-reload | Various UI/schema files | 2026-06-27 (Part 1) |
| 28 | **[2026-06-27]** Wall-clock write timestamps for report cache invalidation | `sqlite_helper_native.dart` · `sqlite_helper_web.dart` | 2026-06-27 (Part 2) |
| 29 | **[2026-06-27]** Report reactive invalidations key mismatch fix | `collection_view.dart` | 2026-06-27 (Part 3) |
| 30 | **[2026-07-06]** Transaction validation, custom ribbon ordering, and responsive layout spacing | `simple_account.dart` · `collection_view.dart` | 2026-07-04/06 |
| 31 | **[2026-07-23]** Save/action text labels, tablet ribbon scroll padding fix, and Google auto-login retry on reconnect | `element_editor.dart` · `collection_view.dart` · `google_drive_service.dart` | 2026-07-23 |

⚠️ = Hard-locked file (never modify without explicit user approval and notification)

---

## Development Standards (Quick Reference)

- **App display name:** `anydb` — package/bundle names stay `anydb_flutter`
- **Brand colors:** Velvet Crimson `#6B1524` · Coral `#E9967A` · Saffron · Gold `#E5C158` · Alabaster Cream `#FAF8F5`
- **Build command (Android):** `flutter build apk --dart-define-from-file=secrets.json`
- **Android DB path (internal):** `/data/user/0/com.example.anydbFlutter/app_flutter/xyz.maya/anydb/anydb_storage.db`
- **Public export path:** `/storage/emulated/0/Android/data/com.example.anydbFlutter/files/xyz.maya/anydb/`
- **Cloud backup path:** Google Drive `/xyz.maya/anydb/Database/`
- **record_timestamps table:** Auxiliary SQLite table tracking write timestamps per record for report cache invalidation. NEVER remove.

---

## Planned Optimizations (Deferred)

1. **Hoisted business key query in `updateAllRaw`:** Move `getBusinessUniqueKeyRaw(dbName)` outside the batch loop — eliminates ~15,000 sequential SELECT queries during DB reload. Drops import time from minutes to under 300ms.
2. **SQLite WASM + OPFS for Web:** Replace `localStorage` adapter with WebAssembly SQLite + Origin Private File System. Eliminates 5MB quota cap and synchronous blocking; brings web to feature parity with mobile.

---

## Reference Files in `.chat_context/`

| File | Purpose |
|------|---------|
| [codebase_index.md](.chat_context/codebase_index.md) | Full lib/ directory map with file purposes |
| [android_backup_location_context.md](.chat_context/android_backup_location_context.md) | Android storage path guide |
| [timestamps_indexing_plan.md](.chat_context/timestamps_indexing_plan.md) | `record_timestamps` design rationale |
| [monthly_report_analysis.md](.chat_context/monthly_report_analysis.md) | Monthly report bug analysis archive |
| [windows_build_guide.md](.chat_context/windows_build_guide.md) | Windows build + signing walkthrough |
| [oauth_verification_guide.md](.chat_context/oauth_verification_guide.md) | Google OAuth + Drive setup guide |
