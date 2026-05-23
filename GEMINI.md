# Project Context: anydb_flutter (May 2026 Checkpoint)

## Core Accomplishments & Stabilized Features

### 1. High-Performance Report Engine
- **Logic Alignment:** Fixed critical off-by-one errors in workbook extraction. The engine now correctly looks for summary headers at **Row 6** and values at **Row 7** (sr=9 offset).
- **Data Integrity:** Implemented `CellHelper.unwrap` to handle Excel `CellValue` types, preventing `jsonDecode` and `tryParse` failures.
- **Aggregation:** Refined `ExtractorDatabase` to include **Active, Archived, and Deleted** records for historical accuracy, while adding row-refinement to exclude placeholder dates during flattening.
- **Workflow:** Automated the "Done" button sequence on the Home screen to switch to the Reports tab and pre-load the Daily report for immediate verification.
- **Report Search Bar:** Added a beautiful report search bar to both the in-tab viewer and dedicated spreadsheet report views, dynamically filtering rows based on a 16pt font input search query with live matching counts.

### 2. Google Sign-In & Drive Integration (Android)
- **Plugin Migration:** Fully aligned with `google_sign_in` **7.x API**, separating identity (authentication) from permissions (authorization).
- **Technical Fixes:** Added `com.google.gms.google-services` Gradle plugin and `INTERNET` permission. Implemented explicit `authorizeScopes` calls to resolve **403 Forbidden** errors.
- **UX Fix:** Introduced a persistent `was_logged_in` flag to ensure users stay signed in across sessions while preventing automatic account selection modals on initial app startup.
- **Cloud Backup:** Implemented a manual backup flow to upload database JSONs to a structured `/xyz.maya/anydb/Database` folder on Google Drive.
- **Drawer Autoclose:** Programmed the navigation drawer to close automatically upon successful Google Drive authorization or successful manual backup completion.

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

### 3. Database Overhaul & Dynamic Archiving Specifications (Roadmap)
- **Bottleneck Diagnosis:** Mobile `SharedPreferences` keys cause severe Platform Channel choking (10+ minute imports for 3,000+ entries) and eager main-thread component instantiations (30,000+ dynamic widgets loaded simultaneously at startup).
- **SQLite Overhaul:** Port `SqliteHelper` globally to mobile via `sqlite3_flutter_libs` to utilize B-tree key-value JSON string storage with transactional writes, speeding up batch-imports to **under 300ms** and startup loading to **under 50ms**.
- **Key Separation & Indexing:** 
  - **SQLite Primary Key:** Unique auto-generated physical identifier (e.g. UUID) allowing active and archived rows to coexist on disk without conflicts.
  - **Business Unique Key:** User-configured dynamic schema field (e.g., `Card Number`, `Patient ID`, `Phone`) selected from the drawer to act as the business identifier.
  - **Active Partial Index:** A SQLite index (`WHERE is_active = 1`) that validates incoming duplicates against active records in microseconds, keeping all archived records completely off-memory on disk.
- **Interactive UI & Prioritization Heuristics:** Dropdown in `drawer_content.dart` allows users to change their active Business Unique Key at any time. The options list dynamically bubbles likely unique identifiers (matching keywords like `id`, `number`, `code`, `key`, `phone`, `card`, `sku`, `serial`, `barcode`) to the top.

## Current State
- **Branch:** `dev`
- **Last Stable Commit:** `c6af06d` (Report Search Bar & Drawer Autoclose: Added full-text report search filtering and automated drawer pop on successful login or backup completion)
- **Analysis:** Clean `flutter analyze` with 0 compilation errors.
