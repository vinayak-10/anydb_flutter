# Database Overhaul & Dynamic Archiving Architecture Spec

This document records the comprehensive research, diagnostic findings, architectural evaluations, and feature designs developed after the May 2026 Checkpoint (Commit `c6af06d` / `c0ae3db`).

---

## 1. Diagnostics & Root Cause Analysis

We investigated the local database import and loading pipelines, locating two critical chokepoints that cause a database of ~3,000 records to take **10+ minutes** to load/import:

1. **SharedPreferences I/O & Channel Choking (Write/Read Choke):**
   - On mobile, `AsyncStore` saves records as individual keys in `SharedPreferences` (e.g. `dbName:recordKey`).
   - Saving 3,000 records requires **3,000 separate native calls** across Flutter's `MethodChannel`.
   - On Android/iOS, this causes massive XML/Plist serialization overhead and synchronous disk writing blocks, freezing the UI.
2. **Eager Instantiation of Dynamic Components (CPU/Memory Choke):**
   - Inside `ElementDb.initDb()`, the app eagerly populates all 3,000 records at startup by instantiating an `ElementModel` for each.
   - Each `ElementModel` creates a new instance of all fields in its schema (e.g., 10 columns = **30,000 component objects** created simultaneously in a synchronous loop on the main thread), freezing the UI for 10–20 seconds.

---

## 2. Evaluation of Database Solutions

We evaluated three potential remedies for long-term scalability and generic architecture:

* **Option A: Lazy Loading / UI Pagination Only**
  - *Verdict:* Insufficient. While it speeds up the initial screen load, it **does not solve the 10-minute fresh import write bottleneck**.
* **Option B: Pure Dart NoSQL Document DB (Hive / Isar)**
  - *Verdict:* High performance (under 50ms batch writes), but introduces new dynamic package dependencies.
* **Option C (Recommended): Cross-Platform SQLite Overhaul (`sqlite3_flutter_libs`)**
  - *Verdict:* The most robust, clean, and minimally disruptive solution. By adding `sqlite3_flutter_libs`, we extend our existing Linux `SqliteHelper` to mobile globally. Transactional SQLite batch writes (`BEGIN TRANSACTION ... COMMIT`) insert 3,000 dynamic records in **under 300 milliseconds**.

---

## 3. Dynamic Record Archiving & Soft-Lifecycle

The app implements a metadata-driven lifecycle:
- **Archive:** Appends a millisecond timestamp `'a'` inside the record's `__meta__['time']` payload.
- **Soft-Delete:** Appends a millisecond timestamp `'d'` inside the record's `__meta__['time']` payload.
- **Auto-Purge:** Records with the `'d'` flag older than 72 hours are permanently deleted at startup.
- **Optimization:** To keep archived/deleted records off Dart RAM, SQLite will query **only active records** using a B-tree partial index:
  ```sql
  CREATE INDEX IF NOT EXISTS idx_active_business_key 
  ON "records" (schema_name, business_key_value) 
  WHERE is_active = 1;
  ```

---

## 4. Key Separation: Business vs. Physical Database Key

To allow active and archived duplicates (e.g. historical cards) to coexist in SQLite while remaining schema-agnostic, we split keys into two layers:

1. **Database Primary Key (SQLite level):** A generated unique UUID or composite ID for physical SQLite rows.
2. **Business Unique Key (User-Configured level):** A dynamic field selected by the user to serve as the business unique validator (e.g. `Card Number`, `Patient ID`, `Phone`).
   - SQLite queries only active indexes for duplicates at runtime in **microseconds**, keeping archived records off-memory:
     ```sql
     SELECT * FROM "records" WHERE business_key_value = ? AND is_active = 1 LIMIT 1
     ```

---

## 5. Drawer Selection UI & Heuristic Prioritization

To provide a flawless user experience, we designed an interactive dropdown selector inside the navigation drawer (`drawer_content.dart`):

* **Inspect & Modify:** Users can change their schema's Business Unique Key at any time.
* **Dynamic Prioritization:** The dropdown automatically prioritizes the most likely unique identifiers at the very top of the list using a smart text heuristic:
  - *Keywords:* `id`, `number`, `code`, `key`, `phone`, `card`, `sku`, `serial`, `barcode`.
  - *Sorting:* Bubble-sorts fields matching these keywords to the top, appending generic descriptive fields (Name, Age, Address) below.
* **Instant Sync:** Changing the selection immediately updates the SQLite configurations table, instantly adapting validation queries.
