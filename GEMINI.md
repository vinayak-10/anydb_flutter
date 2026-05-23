# Project Context: anydb_flutter (May 2026 Checkpoint)

## Core Accomplishments & Stabilized Features

### 1. High-Performance Report Engine
- **Logic Alignment:** Fixed critical off-by-one errors in workbook extraction. The engine now correctly looks for summary headers at **Row 6** and values at **Row 7** (sr=9 offset).
- **Data Integrity:** Implemented `CellHelper.unwrap` to handle Excel `CellValue` types, preventing `jsonDecode` and `tryParse` failures.
- **Aggregation:** Refined `ExtractorDatabase` to include **Active, Archived, and Deleted** records for historical accuracy, while adding row-refinement to exclude placeholder dates during flattening.
- **Workflow:** Automated the "Done" button sequence on the Home screen to switch to the Reports tab and pre-load the Daily report for immediate verification.

### 2. Google Sign-In & Drive Integration (Android)
- **Plugin Migration:** Fully aligned with `google_sign_in` **7.x API**, separating identity (authentication) from permissions (authorization).
- **Technical Fixes:** Added `com.google.gms.google-services` Gradle plugin and `INTERNET` permission. Implemented explicit `authorizeScopes` calls to resolve **403 Forbidden** errors.
- **UX Fix:** Introduced a persistent `was_logged_in` flag to ensure users stay signed in across sessions while preventing automatic account selection modals on initial app startup.
- **Cloud Backup:** Implemented a manual backup flow to upload database JSONs to a structured `/xyz.maya/anydb/Database` folder on Google Drive.

### 3. Security & Build Optimizations
- **Secrets Management:** Replaced hardcoded OAuth secrets with **compile-time definitions** using `--dart-define-from-file=secrets.json`. Added `secrets.template.json` for developers.
- **Gradle Stability:** Optimized `android/gradle.properties` memory limits (`-Xmx4G`) to prevent "daemon disappeared" crashes on tablets and suppressed obsolete Java 8 warnings.
- **Universal Safe Areas:** Wrapped bottom navigation, drawer elements, and main content in `SafeArea` to fix UI obscuring issues on Lenovo tablets with taskbars.

### 4. Storage Resilience & Corruption Fixes
- **JSON Protection:** Fixed `FormatException` crashes in `FileStore` by implementing **Atomic Writes** (writing to `.tmp` then renaming) and an **Asynchronous Write Lock (Mutex)** per file.
- **Self-Healing:** Added automatic corruption detection that backs up damaged files (`*.json.corrupted_[ts]`) instead of crashing the app.
- **Performance:** Implemented in-memory caching and parallelized disk reads in the storage layer to handle 20k+ records smoothly.

## Development Standards & Walkthroughs

### 1. App Rename Policy
- **User-Facing:** Display name is **`anydb`** (Android labels, window titles, Web manifests).
- **Internal:** Package names, Bundle IDs, and the `pubspec.yaml` project name remain **`anydb_flutter`** to maintain system stability and prevent import breaks.

### 2. Manual UI Update Guide (Ref: reviews.txt)
- **Compact Layout:** Components support a `compact` boolean in the `editor()` method to trigger single-row layouts for transactions.
- **Responsive Rows:** `Composite` editor uses `Row` + `Expanded` for professional alignment on tablets, with heuristics to force "long" fields (Notes, Address) to take full width.
- **Progress Feedback:** `ElementDb.initDb` and `AggregatorService` support an `onProgress` callback to update percentage-based bars in the UI.

## Current State
- **Branch:** `dev`
- **Last Stable Commit:** `cb44f99` (Tablet fixes: Added bottom SafeArea wrappers and centered scrollable TabBar to resolve taskbar obscuring and horizontal overflows)
- **Analysis:** Clean `flutter analyze` with 0 compilation errors.
