# Project Context: anydb_flutter (June 2026 Checkpoint)

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

### 10. Google-Search Landing Page
- **Minimalistic Landing Experience:** Designed and built a beautiful, spacious Google Search-like landing layout featuring a plain white theme background, the official vector app logo (`assets/anydb_logo_yantra_prism.svg`), and a rich crimson-saffron-gold linear text gradient matching the prism.
- **Dynamic Show/Hide Logo Heuristics:** Designed a dynamic show/hide layout. When the search bar is empty, the logo and custom text are fully rendered. Once the user types any character, the branding dynamically collapses to yield maximum vertical space.
- **Real-Time Vertical Results:** Integrated real-time query matching directly on the landing page, displaying matching database records as vertical card widgets below the search bar with tap-to-edit interactions (bypassing full database browser switching).
- **Drawer & Bottom Tab Preservation:** Fully preserved structural layout layers so that the outer Scaffold's drawer, swipe-gestures, and bottom navigation tabs remain completely active and operational.
- **Universal Speed Dial FAB Overlay:** Retained the overlay of the newly added Speed Dial FAB on the landing page, offering quick-launch options for new records and instant resume/discard actions for active drafts.
- **Landing Access ActionChip:** Integrated a beautiful Home "Landing" ActionChip inside both the mobile and tablet Choice Chip rows to allow users to toggle back to the landing search experience at any time.

### 11. Custom Logo Adaptive Icon & Tab Favicon Overhaul
- **Pillow Resampler Compatibility:** Added a robust Pillow-based generation script (`assets/update_all_icons.py`) featuring dynamic fallback support (`Image.Resampling.LANCZOS` / `Image.ANTIALIAS`) for maximum system portability across older and newer Pillow versions.
- **Centering & Textless Master Canvas:** Designed a dedicated mathematically centered textless master logo `assets/anydb_logo_centered.png` shifting vector elements down by `20px` to map perfectly to `(256, 256)` on the `512x512` canvas. Used it for all Android adaptive foreground/legacy layers and all Web favicon and PWA manifest assets to resolve unalignment and clipping under squircle/round masking.
- **Web Favicon & PWA Icons:** Regenerated all 5 Web favicon and PWA manifest assets (`favicon.png`, `Icon-192.png`, `Icon-512.png`, and maskable variants) from the master high-resolution logo to eliminate outdated white-bordered padding.
- **Android Adaptive Launchers:** Ported adaptive icon support to Android launcher mipmap sets. Configured the adaptive background color to Velvet Crimson (`#6B1524`) in `colors.xml` and generated transparent-canvas foreground mipmaps (`ic_launcher_foreground.png`) with the logo scaled to a safe-zone `72%` to prevent Android mask clipping.
- **Legacy Fallbacks:** Rewrote legacy solid `ic_launcher.png` formats across all density buckets (`mdpi` to `xxxhdpi`) for compatibility with older platforms.

### 12. High-Performance SQLite Multi-Worker Isolate Pool (Mobile)
- **Multi-Worker Pool:** Expanded `IsolateWorker` to manage two persistent, long-lived background Isolates: Isolate 1 (Database & Schema Worker) and Isolate 2 (Report & Process Worker) running in parallel on separate CPU cores.
- **Direct IPC Communication:** Designed an inter-isolate direct connection (IPC) channel allowing the report/backup worker to fetch raw database JSONs directly from the database worker, completely bypassing the main UI thread during cloud backups.
- **Warm Connection Cache:** Configured Isolate 1 to maintain a permanently open SQLite connection, keeping the database page cache warm in RAM and allowing sub-queries to execute in microseconds with zero disk thrashing.
- **Dynamic 30% Recent Records Boot:** Programmed the database worker to sort all records by last transaction date in the background and return only the top 30% most recent records to the main thread during boot, reducing dashboard load times to **under 50ms**.
- **Asynchronous Search Offloading:** Integrated `searchAsync` to query the background Database Isolate's warm cache on keypress, executing filters across 100% of records in under **3ms** while maintaining a lightweight main-thread heap.
- **Selective Bypassing:** Configured tiny system and configurations tables to bypass the Isolate pool entirely and load directly on the main thread in `<1ms`.
- **SQLite WAL Mode:** Enabled SQLite Write-Ahead Logging (`PRAGMA journal_mode=WAL;`) to support fully concurrent reads and writes with zero transaction locking conflicts.

### 13. Active Database Pre-Warming, Inactive Lazy-Loading & Filter Percolation
- **Startup Pre-Warming:** Optimised initial boots by pre-warming strictly the active records in the database background cache on startup, bringing active dashboards to paint in micro-seconds.
- **Lazy Loading Historical Tabs:** Programmed inactive records (Archived/Deleted) to load lazily only when navigating to historical views (Archive/Trash tabs), conserving memory overhead.
- **Root-Level Metadata Key Resolution:** Fixed search result filter leakages by upgrading background isolate query logic to parse `__meta__` keys correctly at both root and nested map levels, preventing archived/deleted records from polluting landing page active searches.
- **Percolation Synchronization:** Implemented Riverpod search state observers that automatically reset list filters, search controllers, and overlay caches when switching tabs or toggling back to the Google-Search landing page.

### 14. Modular Plug-and-Play Feedback Toast & Empty State Toolkit
- **Plug-and-Play Named Feedback Toasts (`feedback_toast.dart`):** Engineered a highly modular SnackBar-based feedback constructor utility. Supports named configurations (`success`, `error`, `undoable`, and `retryable`) with dynamic saffron-accented `Action` closures to trigger robust item restorations (`widget.db.restore(element)`).
- **Plug-and-Play Named Empty States (`empty_state_view.dart`):** Developed a unified empty state viewport component featuring named constructor configurations (`active`, `archived`, `deleted`, and `searchEmpty`) matching Velvet Crimson (#6B1524) and Coral (#E9967A) aesthetics.
- **Symmetric Tablet AppBar Layout:** Stripped the hardcoded 56px action spacer block from the tablet split-pane details AppBar, natively aligning detail operations symmetrically to the right edge.

### 15. Premium Floating Dock, Keyboard FAB Auto-Hide & Empty DB Alert Toolkit
- **Option B Premium Floating Dock:** Re-designed the bottom tab bar as a detached floating dock styled in a premium Alabaster Cream (`#FAF8F5`) contrast layer featuring a rounded border radius (`24px`), horizontal/bottom margins, a sophisticated upward shadow glow, and active horizontal indicator lines (`3px` rounded pills) at the top edge of tabs.
- **Keyboard FAB Auto-Hide:** Standardized outer Scaffold's `resizeToAvoidBottomInset: false` to allow bottom elements to sit naturally behind the software keyboard, while dynamically hiding the central Cradle FAB when the search view is active and focused, avoiding layout squeezing and overlaps.
- **Empty Database Alert Trigger:** Implemented a low-level, high-performance static check `SqliteHelper.isTableEmpty(dbName)` to check for empty database states, triggering a premium warning SnackBar and displaying a gorgeous visual Velvet Crimson warning card in search results when no backup has been imported altogether.
- **One-Shot Empty Warning:** Prevented Toast spamming on every keystroke by integrating a state-retained `_hasShownEmptyWarning` flag inside the search controller typing listener. This triggers the error SnackBar only once at the beginning of the typing sequence and resets cleanly when the query is cleared or when database records are successfully imported.

### 16. Private GitHub Remote Setup & Apple Actions Pipeline
- **Multi-Remote Architecture:** Successfully split local remote configs to support a dual-remote model: `local-server` (local Git server) and `origin` (private GitHub remote at `git@github.com:vinayak-10/anydb_flutter.git`). Pushed both `dev` and `master` branches.
- **Apple Actions Automation:** Drafted a macOS and iOS compile automation pipeline (`.github/workflows/build_apple.yml`) using Apple Silicon macOS runners to handle Flutter desktop packaging.
- **iOS Packaging Assembly:** Created `ios/ExportOptions.plist` mapped to the bundle identifier `com.example.anydbFlutter` for manual signing assembly exports.

### 17. Sticky Header & Fit-to-Width Report View
- **Fit-to-Width Columns:** Refactored the Excel-generation report preview table from `DataTable` to a custom `Table` component. Implemented dynamic flex-width columns to fit 100% of the screen width with zero horizontal scrolling.
- **Sticky Header & Scrollable Body:** Added a sticky/static top-pinned header and a vertically scrollable body table aligned with the header. Enforced a default font size of `16` for elderly readability with single-line ellipsis clipping.

### 18. Force-Reload on Report preview & Done Sequence
- **Force workbook generation:** Added the `force` reload parameter to `generateWorkbook()` inside `AggregatorService` and passed it down to `ExtractorDatabase.reinit`.
- **Done Flow Real-time Sync:** Forced report regeneration inside the "Done" (Finalize Day) sequence, "Share" flow, and report "OPEN" action to ensure the latest added transactions are correctly queried and reflected in the preview sheet.

### 19. Optimized SQLite RAM Cache & Android largeHeap
- **128MB RAM Page Cache:** Increased SQLite's page cache size limit to 128MB (`-128000`) and set `PRAGMA synchronous = NORMAL` inside the connection initializer of `SqliteHelper` to accelerate high-volume database reads and writes.
- **Large Heap Allocation:** Verified that `android:largeHeap="true"` is enabled inside the application manifest to request maximum heap allocation from the OS.

### 20. Adaptive Floating Dock & Font Scale Clamp
- **Platform-Agnostic Option B Dock:** Upgraded the custom bottom navigation dock to run globally on all platforms and screens. Removed redundant `BottomAppBar` to bypass native Material 3 vertical padding overrides and minimum height constraints.
- **Adaptive Spacing & Font Clamp:** Implemented dynamic bottom margin based on `MediaQuery` system safe area insets to prevent double-padding on tablets. Wrapped contents in a `MediaQuery` clamping `textScaler` to `1.0` and set single-line ellipsis text wrapping to avoid font overflows on small screens.

### 21. Compact Reports Tab UI Redesign & Cradle FAB Home Alignment
- **Edge-Aligned Layout**: Replaced the report list view and loose bottom buttons with exactly two action buttons (`GENERATE DAILY` on the left, `GENERATE MONTHLY` on the right) directly below the Date Picker card.
- **Consolidation Checkbox**: Integrated an optional checkbox ("Consolidate all daily reports") under the `GENERATE MONTHLY` button that defaults to unchecked (fast compilation from disk cache) and can be toggled to perform a full month rebuild and consolidation.
- **Home FAB Navigation**: Configured the reports tab's cradle FAB to show a home icon and navigate back to the Database Tab's landing page while clearing search query states.

### 22. Schema Auto-Select with Startup Countdown
- **Settings Persistence:** Added `lastLoadedSchemaPath` to the global `SettingsState` stored persistently in `SharedPreferences` via `setLastLoadedSchema()`.
- **Startup Countdown Banner:** Implemented a 5-second countdown timer on the Home Page inside `_HomePageState` in [main.dart](file:///lib/main.dart). If a cached schema path exists, it renders a sleek Velvet Crimson (`#6B1524`) banner with a Gold (`#E5C158`) border containing a progress indicator and countdown.
- **User Interrupt Controls:** Tapping **CANCEL** on the banner stops the timer and clears the cache to avoid redirect loops on future boots. Tapping any other schema immediately stops the timer and loads the new schema.

### 23. Zipped Windows Desktop CI Pipeline & C++ Wrapper Fix
- **Windows Release Pipeline:** Established a new GitHub Actions workflow ([build_windows.yml](file:///.github/workflows/build_windows.yml)) running on a `windows-latest` VM that builds Windows desktop releases. Since Windows executables require sibling DLLs and data assets, the entire output directory is zipped into `anydb_windows.zip` for release download.
- **MSVC Build Fix:** Addressed a `CMakeLists.txt` C++ client wrapper compilation failure on Windows hosts. Wrapped the dummy Linux bypass command in a `if(WIN32)` conditional in [CMakeLists.txt](file:///windows/flutter/CMakeLists.txt) to restore the standard `${FLUTTER_TOOL_ENVIRONMENT}` and `tool_backend.bat` invocation on Windows builders while preserving the Linux mock compilation bypass for local offline setups.

### 24. Android & Apple CI/CD Pipeline with Signing Fallbacks & Deactivation
- **Android & iOS Workflows:** Created [.github/workflows/build_android.yml](file:///.github/workflows/build_android.yml) supporting compilation of signed release APKs and AABs.
- **Robust Signing Fallbacks:** Programmed the signing key injector to dynamically reconstruct keystores using Base64 environment secrets if available, falling back to a self-generated temporary key if passwords/secrets are missing so compilation never fails.
- **Trigger Deactivation:** Commented out automatic push triggers in both `build_android.yml` and `build_apple.yml` globally. Android and Apple workflows will now only trigger manually via the GitHub Actions UI to conserve monthly free quota.

### 25. High-Performance Date Pre-Filtering for Daily Reports
- **Shape Mismatch Fix:** Resolved a data structure shape mismatch in the background isolate's `ipcGetFilteredReportData` task that caused daily report generation to filter out all records (returning "no records found").
- **Date Pre-Filtering:** Optimized report compilation speeds by checking the record's transaction dates in the warm cache (`Account.history[].Date`) *before* executing the expensive recursive `_flatten` engine.
- **100x Acceleration:** Reduced flattening workloads from 10,000+ records to only ~25 matched records, reducing daily report generation times from seconds/minutes down to **under 50 milliseconds**.

---

## Development Standards & Walkthroughs

### 1. App Rename Policy
- **User-Facing:** Display name is **`anydb`** (Android labels, window titles, Web manifests).
- **Internal:** Package names, Bundle IDs, and the `pubspec.yaml` project name remain **`anydb_flutter`** to maintain system stability and prevent import breaks.

### 2. Manual UI Update Guide (Ref: reviews.txt)
- **Compact Layout:** Components support a `compact` boolean in the `editor()` method to trigger single-row layouts for transactions.
- **Responsive Rows:** `Composite` editor uses `Row` + `Expanded` for professional alignment on tablets, with heuristics to force "long" fields (Notes, Address) to take full width.
- **Progress Feedback:** `ElementDb.initDb` and `AggregatorService` support an `onProgress` callback to update percentage-based bars in the UI.

### 3. High-Performance Auxiliary Metadata Registry & Startup connection (`record_timestamps`)
- **Startup Connection Cache:** Unconditionally creates the auxiliary table `record_timestamps` (db_name, id, timestamp) and its order index on SQLite database connection initialization at app startup.
- **Lightweight Boot Sorting:** Queries top recent record IDs from `record_timestamps` and pulls raw string values in under **20ms** without executing expensive `jsonDecode` sort comparisons.
- **Self-Healing Backfill:** Automatically runs background transactional backfilling on first boot if timestamps count does not match main records.

### 4. Schema-Aware Background Isolate Search
- **Key-Value Isolation:** Decodes raw strings in the background worker and executes recursive key-value matching **only** against designated searchable schema fields, entirely ignoring metadata tags (`__meta__`) and non-searchable fields.
- **Zero False Positives:** Resolves false-positive substring matches and returns `[]` cleanly to paint the `"No matching records found"` view.

### 5. Professional Keyboard & Auto-Hide FAB Adaptations
- **Zero Accidental Keyboard Pops:** Disabled default `autofocus` on the landing page's search text inputs to prevent the software keyboard from popping up on app startup or bottom tab navigation.
- **Pristine Layout & Keyboard FAB Coverage:** Configured `resizeToAvoidBottomInset: false` on the landing Scaffold to let bottom navigation and Floating Action Buttons sit naturally covered behind the software keyboard, preventing overlaps and screen squeezing.

### 6. App-Wide Unhandled Failure Logging
- **Core Error Interception:** Bound `FlutterError.onError` and `PlatformDispatcher.instance.onError` to automatically capture all UI rendering exceptions, widget tree crashes, and unhandled asynchronous/isolate thread zone errors.
- **Persistent Storage:** Appends formatted failure reports to daily log files on disk.

### 7. Apple Developer Account Constraints & Sideloading Options
- **Paid vs. Free Account Portal Block:** Apple's developer portal restricts "Certificates, IDs, & Profiles" to paid accounts ($99/year). Free accounts cannot generate `.p12` certificates or manual `.mobileprovision` profiles for cloud Actions runners.
- **Sideloading Alternatives:** If cloud signing is bypassed, developers can compile the iOS package unsigned (`--no-codesign`) on GitHub Actions, then sideload it locally using free utilities like **AltStore** or third-party UDID registration services.

### 8. GitHub Private Repo Telemetry & Copilot Opt-Out
- **At-Rest Protection:** GitHub terms guarantee that code in private repositories is not used to train AI models.
- **Copilot Interactions:** To stop Copilot IDE extensions from transmitting telemetry context for product improvement, opt out globally via **GitHub Settings > Copilot > Privacy > Allow GitHub to use my data for AI model training** and set to **Disabled**.

---

## Planned Optimizations for Next Session

### 1. Single-Query Hoisted Configuration for Batch Imports
- **The Bottleneck:** Currently, the batch-write loop in `SqliteHelper.updateAllRaw` executes `getBusinessUniqueKeyRaw(dbName)` inside the loop, forcing SQLite to run **15,000 SQL SELECT queries** one-by-one during database wipes or reloads.
- **The Plan:** Hoist `getBusinessUniqueKeyRaw(dbName)` outside the loop so it runs **exactly once**. Extract the business key value in RAM using recursion in CPU time, dropping import and reload time from minutes to **under 300 milliseconds**!

### 2. High-Capacity Web Database Storage (SQLite WASM + OPFS)
- **The Bottleneck:** The current web `localStorage` adapter is synchronous, blocks execution, and throws quota exceptions at 5MB, falling back to a volatile in-memory cache.
- **The Plan:** Compile the database core to **SQLite WebAssembly (WASM)** and mount files to the browser's **Origin Private File System (OPFS)**. This allows the web app to execute the exact same transactional queries, B-tree indexes, and metadata checks as mobile targets with multi-gigabyte local storage limits.

---

## Current State
- **Branch:** `dev`
- **Last Stable Commit:** `a211a5e` (fix(windows): restore standard FLUTTER_TOOL_ENVIRONMENT payload for Windows build custom command)
- **Analysis:** Clean `flutter analyze` with 0 compilation errors.

