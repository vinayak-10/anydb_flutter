# Database Overhaul & Dynamic Archiving Implementation Plan

This document details the full, phased implementation plan to overhaul AnyDb's local storage and lifecycle validation pipelines, transitioning mobile devices to transactional SQLite, separating business keys from database primary keys, and dynamically auto-archiving expiring duplicates.

---

## 1. Goal Description

Migrate mobile platforms (Android/iOS) from high-overhead, sequential `SharedPreferences` writes to transactional, B-tree indexed **SQLite** document storage. 
Separate the physical **Database Primary Key** from the user-selected **Business Unique Key**, allowing active and archived duplicates to coexist safely. 
Implement **Lazy Model Instantiation** to keep memory low and ensure sub-50ms screen loading.

---

## 2. User Review Required

> [!IMPORTANT]
> - **Dependency Additions:** We will add `sqlite3_flutter_libs` to `pubspec.yaml` to bundle the native SQLite shared library binaries on Android and iOS.
> - **Database Schema Migration:** The existing `SharedPreferences` keys will be seamlessly imported into SQLite during the first schema load after the update, ensuring zero data loss for existing users.
> - **Custom Key Selector in Drawer:** Adds an interactive dropdown in the drawer (`drawer_content.dart`) allowing users to change the Business Unique Key at runtime, with candidate fields automatically prioritised at the top of the list.

---

## 3. Proposed Changes (Phased Roadmap)

### Phase 1: Storage Overhaul & Cross-Platform SQLite Integration
#### [MODIFY] [pubspec.yaml](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/pubspec.yaml)
- Add `sqlite3_flutter_libs` under dependencies.

#### [MODIFY] [sqlite_helper.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/sqlite_helper.dart)
- Remove `!isLinux()` guards inside `initTable`, `getAll`, `get`, `update`, `updateAll`, `remove`, and `clear`.
- Ensure directory resolution (`getInternalRoot`) works correctly across mobile platforms.

#### [MODIFY] [async_store.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/async_store.dart)
- Remove `SharedPreferences` usage entirely on Android/iOS.
- Direct all static calls (`getAll`, `get`, `update`, `updateAll`, `remove`, `clear`) to use `SqliteHelper` methods globally.

---

### Phase 2: Schema Configuration & Priority Unique Key Selector UI
#### [MODIFY] [sqlite_helper.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/sqlite_helper.dart)
- Create a dedicated configuration table `schema_configurations` (storing `schema_name` and `business_unique_key`) to preserve user validation key choices.

#### [MODIFY] [drawer_content.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/components/drawer_content.dart)
- Add a dropdown under a new "Schema Configuration" section in the drawer.
- Implement the sorting heuristic algorithm to dynamically push likely unique fields (containing keywords like `id`, `number`, `code`, `key`, `phone`, `card`, `sku`, `serial`, `barcode`) to the top of the option list.
- On dropdown selection change, instantly update the configuration table and trigger a database reload.

---

### Phase 3: SQLite Query-Level Validation & Transactional Auto-Archiving
#### [MODIFY] [sqlite_helper.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/sqlite_helper.dart)
- Overhaul `initTable` schema for element record tables:
  ```sql
  CREATE TABLE IF NOT EXISTS "TableName" (
    id TEXT PRIMARY KEY,
    schema_name TEXT,
    business_key_value TEXT,
    is_active INTEGER DEFAULT 1,
    value TEXT
  );
  ```
- Add the active partial B-tree index:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_active_business_key ON "TableName" (schema_name, business_key_value) WHERE is_active = 1;
  ```

#### [MODIFY] [element_db.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/element_db.dart)
- Update `addRecord` to perform the microsecond duplicate validation query in SQLite:
  ```sql
  SELECT * FROM "records" WHERE business_key_value = ? AND is_active = 1 LIMIT 1
  ```
- If an active duplicate exists:
  - Parse the dynamic date field from its JSON payload.
  - **Expiring (<= 30 days remaining):** Execute a single SQLite Transaction block:
    1. `UPDATE "records" SET is_active = 0 WHERE id = ?` (soft-archives old record).
    2. `INSERT INTO "records" ... is_active = 1` (saves new active record with a new unique physical `id` UUID).
  - **Not Expiring (> 30 days remaining):** Block the save action and pass an explicit validation warning to the UI.

---

### Phase 4: Lazy Model Instantiation & Memory Optimizations
#### [MODIFY] [element_db.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/element_db.dart)
- Overhaul `initDb` to load database entries directly into an in-memory cache of raw JSON maps (`List<Map<String, dynamic>> _rawRecords`), rather than pre-instantiating 3,000 `ElementModel` instances.

#### [MODIFY] [collection_view.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/screens/collection_view.dart) & [element_editor.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/screens/element_editor.dart)
- Modify lists and editors to instantiate and populate an `ElementModel` **lazily/on-demand** only when a record card is rendered in the `ListView.builder` or opened in the editor view.

---

## 4. Verification Plan

### Automated Tests
- Run `flutter analyze` to ensure zero compilation or layout issues.
- Build and run unit tests validating SQLite transaction success and index query performance.

### Manual Verification
- **Import Speed Test:** Trigger a fresh database import of 3,000+ records and verify that it completes in **under 300ms** (sub-second) instead of 10 minutes.
- **Drawer Configuration:** Open the drawer, verify the prioritized dropdown options match the schema, and change the unique key. Verify that duplicate check validations immediately adapt.
- **Auto-Archiving Validation:** Add a new record with an existing card/unique key:
  - Confirm duplicate validation blocks the save if the active card has > 30 days left.
  - Confirm the old record is auto-archived and the new record takes effect if the active card has <= 30 days left.
- **Scroll & Loading Fluidity:** Verify that database startup loads in under **50ms** and scrolling through thousands of records remains at 60fps with zero rendering lag.
