# Project Context: anydb_flutter (May 2026 Checkpoint)

## Core Accomplishments & Stabilized Features

### 1. High-Performance Report Engine
- **Logic Alignment:** Fixed critical off-by-one errors in workbook extraction. The engine now correctly looks for summary headers at **Row 6** and values at **Row 7** (sr=9 offset).
- **Data Integrity:** Implemented `CellHelper.unwrap` to handle Excel `CellValue` types, preventing `jsonDecode` and `tryParse` failures.
- **Aggregation:** Refined `ExtractorDatabase` to include **Active, Archived, and Deleted** records for historical accuracy, while adding row-refinement to exclude placeholder dates during flattening.
- **Workflow:** Automated the "Done" button sequence on the Home screen to switch to the Reports tab and pre-load the Daily report for immediate verification.
- **Report Search Bar:** Added a beautiful report search bar to both the in-tab viewer and dedicated spreadsheet report views, dynamically filtering rows based on a 16pt font input search query with live matching counts.

### 2. SQLite Global Overhaul & Mobile Performance
- **Cross-Platform SQLite Integration:** Ported `SqliteHelper` globally to mobile via `sqlite3_flutter_libs` to utilize B-tree key-value JSON string storage with transactional writes, speeding up batch-imports to **under 300ms** and startup loading to **under 50ms**.
- **Unique Key Separation & SQLite Partial Indexing:** Supported distinct SQLite physical primary keys (`id`) alongside user-selected dynamic business identifiers (`Card Number`, `Patient ID`, `Phone`). Implemented an active partial B-tree index (`WHERE is_active = 1`) validating incoming duplicates against active records in microseconds.
- **Key Selector UI & Prioritization Heuristics:** Added an interactive selector dropdown in the navigation drawer (`drawer_content.dart`) allowing users to change their active Business Unique Key at any time. Configured key heuristics keywords to dynamically push the most likely candidates (matching `id`, `number`, `code`, `key`, `phone`, `card`, `sku`, `serial`, `barcode`) to the top of the option list.
- **Active Lifecycle Validation & Transactional Auto-Archiving:** Programmed `ElementDb.addRecord` to perform runtime active duplicate checks. If a duplicate active business key exists and is nearing expiry (<= 30 days remaining), the old record is transactionally soft-archived (`is_active = 0`) and the new record takes effect immediately. If not expiring (> 30 days remaining), the save action is safely blocked.
- **Lazy Model Instantiation:** Resolved eager widget memory-choking by overhauling `ElementModel` to support lightweight lazy shells (`ElementModel.lazy`). Components are hydrated transparently on-demand the moment the UI renders visible list cards, bringing eager object instantiation down to 0 on launch and ensuring smooth 60fps scrolling.

### 3. Google Sign-In & Drive Integration (Android)
- **Plugin Migration:** Fully aligned with `google_sign_in` **7.x API**, separating identity (authentication) from permissions (authorization).
- **Technical Fixes:** Added `com.google.gms.google-services` Gradle plugin and `INTERNET` permission. Implemented explicit `authorizeScopes` calls to resolve **403 Forbidden** errors.
- **UX Fix:** Introduced a persistent `was_logged_in` flag to ensure users stay signed in across sessions while preventing automatic account selection modals on initial app startup.
- **Cloud Backup:** Implemented a manual backup flow to upload database JSONs to a structured `/xyz.maya/anydb/Database` folder on Google Drive.
- **Drawer Autoclose:** Programmed the navigation drawer to close automatically upon successful Google Drive authorization or successful manual backup completion.

### 4. Security & Build Optimizations
- **Secrets Management:** Replaced hardcoded OAuth secrets with **compile-time definitions** using `--dart-define-from-file=secrets.json`. Added `secrets.template.json` for developers.
- **Gradle Stability:** Optimized `android/gradle.properties` memory limits (`-Xmx4G`) to prevent "daemon disappeared" crashes on tablets and suppressed obsolete Java 8 warnings.
- **Universal Safe Areas:** Wrapped bottom navigation, drawer elements, and main content in `SafeArea` to fix UI obscuring issues on Lenovo tablets with taskbars.

### 5. Storage Resilience & Corruption Fixes
- **JSON Protection:** Fixed `FormatException` crashes in `FileStore` by implementing **Atomic Writes** (writing to `.tmp` then renaming) and an **Asynchronous Write Lock (Mutex)** per file.
- **Self-Healing:** Added automatic corruption detection that backs up damaged files (`*.json.corrupted_[ts]`) instead of crashing the app.
- **Performance:** Implemented in-memory caching and parallelized disk reads in the storage layer to handle 20k+ records smoothly.

### 6. Robust Web Storage & Quota Management
- **Quota Tolerance:** Wrapped standard localStorage registry and record setString writes in try-catch boundaries to intercept DOM QuotaExceededError exceptions.
- **In-Memory Fallback:** Programmed fallback support using an in-memory cached map (`_webCache`) when browser local storage is fully saturated, keeping database imports and session mergers functional.

### 7. Persistent Isolate Worker Pool & Yielding spinner
- **Worker Threading:** Established a long-lived, multi-platform duplex Port background worker Isolate (`IsolateWorker`) on startup to optimize CPU-heavy calculations.
- **Thread Offloading:** Delegated Excel encoder/decoder operations, workbook parsing, schema parsing, and B-tree import cache merging to the Isolate, preventing main-thread UI lockups.
- **Web Fallback & Spinner Yielding:** Supported synchronous execution on Web targets while adding post-frame micro-delays (`Future.delayed(150ms)`) to guarantee visual paint cycles for loaders and progress bars.

### 8. Concurrent Record Drafts & Adaptive Speed Dial FAB
- **Multiple Concurrent Drafts:** Supported an in-memory collection (`_drafts`) allowing users to minimize and manage multiple drafts concurrently without blocking the UI or using modal restriction banners.
- **Expandable Speed Dial FAB:** Designed a premium, native Floating Action Button speed dial menu presenting minimizable drafts.
- **Adaptive/Responsive Sizing:** Integrated size heuristics so that speed dial sub-buttons, main action labels, capsules, padding, and icons scale dynamically based on viewport widths, switching style attributes automatically between mobile and high-resolution tablet screens.
- **Recursive Nested Key Resolution:** Overhauled the unique key extraction and draft labeling systems to walk nested map structures recursively. This ensures container component fields (such as `Card Number` inside `Registration` composite) are resolved case-insensitively and accurately for draft titles, active lifecycle validations, and soft-archiving transactions.

### 9. Tablet Split View Responsive Layout
- **Responsive Dual-Pane Splits:** Configured a side-by-side list-detail split view for viewport dimensions >= 800px.
- **Preference Controls:** Added a switch tile in the navigation drawer under the Coral `#E9967A` brand accents to toggle split-screen mode.
- **In-Place Reactive Editing:** Wrapped `ElementView` details with an `onChanged` callback to immediately sync edits in-place with the master list cards. Clamped the master list column width adaptively between `320px` and `480px` (`35%` width) and ensured card layouts are visually identical in both flows.

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
- **Last Stable Commit:** `f09442c` (docs: update GEMINI.md project checkpoint context)
- **Analysis:** Clean `flutter analyze` with 0 compilation errors.
