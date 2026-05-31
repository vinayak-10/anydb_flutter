# Database Loading Performance Analysis & Active Timestamps Indexing Spec

This document records the deep root cause analysis of the 1.5-minute database loading bottleneck and outlines the architectural remediation plan to isolate permanent delete vs. soft-archiving lifecycles, and introduce an active-status column index in the auxiliary `record_timestamps` table.

---

## 🔍 Deep Root Cause Analysis of the 1.5-Minute Bottleneck

Whenever the application boots or reloads the database (`initDb`), the background Database Isolate runs the `'dbGetAll'` task. The very first step of this task is to ensure the chronological timestamps index is up-to-date by calling:
```dart
await SqliteHelper.backfillTimestamps(dbName);
```

### The Checkpoint Check
Inside `backfillTimestamps`, the database helper queries the record counts of the main table and the timestamps index table:
```dart
final mainCount = db.select('SELECT COUNT(*) as count FROM "$tableName"').first['count'] as int;
final stampCount = db.select('SELECT COUNT(*) as count FROM "record_timestamps" WHERE db_name = ?', [dbName]).first['count'] as int;

if (mainCount != stampCount) {
  // 🛑 HEAVY 1.5-MINUTE RE-PARSING ENGINE TRIGGERED
}
```

### The Structural Life-Cycle Bugs
The backfill was designed to be a one-time self-healing operation on first startup. However, due to two major omissions in the data lifecycle paths, **the counts are permanently out of sync, forcing the app to run this heavy backfill on every single boot**:

1. **Bug A: Deletions do not update the auxiliary table**
   When a record is deleted from the database (manually or automatically via startup auto-purge), the system calls `SqliteHelper.remove`. This executes `DELETE FROM "$tableName" WHERE id = ?` but **never deletes** the record's timestamp entry from `record_timestamps`. 
   * **The Penalty:** The main table count drops, but the stamps count remains the same. The mismatch instantly triggers a full-table re-parse (`jsonDecode` of all 15,000 JSON payloads to extract dates) on the very next launch.
2. **Bug B: Table wipes/clears do not clear the auxiliary table**
   When importing data or wiping a table, the system calls `SqliteHelper.clear`. This clears the main table using `DELETE FROM "$tableName"` but **never deletes** the corresponding timestamps from `record_timestamps`.
   * **The Penalty:** The main count goes to 0 but the stamps count stays at 15,000, creating a permanent mismatch on subsequent reloads.

---

## 🛠️ Remediation Plan: Synchronizing Table Counts

To resolve this permanently and ensure database loading drops to **under 50 milliseconds**, the following lifecycle methods will be synchronized:

1. **Synchronize `remove`:** When a record is deleted, delete its entry from `record_timestamps` as well:
   ```sql
   DELETE FROM "record_timestamps" WHERE db_name = ? AND id = ?
   ```
2. **Synchronize `clear`:** When a database table is cleared, clear all its corresponding entries from `record_timestamps`:
   ```sql
   DELETE FROM "record_timestamps" WHERE db_name = ?
   ```
3. **One-Time Self-Healing Clean:** The very first time the app launches after these fixes, it will run the backfill once to clean up any orphaned timestamps. On all subsequent launches, `mainCount == stampCount` will be **perfectly equal**, bypassing the backfill entirely and loading the database in **microseconds**!

---

## 🚀 Future Performance Plan: Active Timestamps Indexing

To further optimize chronological data loading, we isolate **Permanent Delete** from **Archiving/Soft-Deletions** and introduce an active status index to `record_timestamps`.

### 1. Operations Isolation

* **Archive / Soft-Delete (Historical Preservation):**
  * **Rule:** The record **must never** be physically deleted from the disk.
  * **Mechanism:** We update its `is_active` flag to `0` in both the main table and `record_timestamps`. The full JSON payload remains permanently intact on disk. 
  * **Benefit:** It is excluded from active indexes (making boots and searches instantaneous) but remains fully searchable in the "Archived" or "Deleted" lists and reports.
* **Permanent Delete (Physical Purge):**
  * **Rule:** The record is physically destroyed (manual wipe, or auto-purging soft-deleted items older than 72 hours).
  * **Mechanism:** We execute a physical `DELETE FROM` on both tables.
  * **Benefit:** Stale or purged data is removed completely, freeing up hardware space and keeping the table synchronization counts (`mainCount == stampCount`) in perfect alignment.

---

### 2. Table Schemas with `is_active` Flag

To implement this, both tables will track the dynamic lifecycle state.

#### A. The Auxiliary `record_timestamps` Table
We add an `is_active` column and build a composite index prioritizing active state and chronological sorting:

```sql
CREATE TABLE IF NOT EXISTS "record_timestamps" (
  db_name TEXT,
  id TEXT,
  is_active INTEGER DEFAULT 1,  -- ⚡ 1 = Active, 0 = Archived/Deleted
  timestamp INTEGER,
  PRIMARY KEY (db_name, id)
);

-- ⚡ COMPOSITE INDEX: Optimizes chronological queries of active entries
CREATE INDEX IF NOT EXISTS "idx_record_timestamps_active_order" 
ON "record_timestamps" (db_name, is_active, timestamp DESC);
```

#### B. The Main Table (Parity Schema)
The main table already has these columns, backed by its active partial index:
```sql
CREATE INDEX IF NOT EXISTS "idx_active_business_key_$tableName" 
ON "$tableName" (business_key_value) 
WHERE is_active = 1;
```

---

### 3. Monitoring & Update Synchronization Matrix

To ensure both tables are rightfully updated and kept in perfect harmony, the four lifecycle transactions are aligned:

| Transaction Flow | Main Table (`$tableName`) Action | Timestamps Table (`record_timestamps`) Action | Safety Check |
| :--- | :--- | :--- | :--- |
| **New Entry / Save (`update`)** | `INSERT OR REPLACE` with `is_active = 1` | `INSERT OR REPLACE` with `is_active = 1` and new timestamp | Safe |
| **Soft-Archive / Soft-Delete** | `UPDATE is_active = 0` | `UPDATE is_active = 0` (preserves existing timestamp) | Wanted historical entries are safely kept in both tables. |
| **Auto-Purge / Physical Delete** | `DELETE FROM` (purges old record) | `DELETE FROM` (purges orphaned timestamp) | Mismatch is prevented. `mainCount == stampCount` is preserved. |
| **Full Wipe / Clear** | `DELETE FROM` (clears all) | `DELETE FROM WHERE db_name = ?` (clears all timestamps) | Both counts drop to `0` simultaneously. |

---

### 4. Dynamic Boot Optimization (`dbGetAll`)
With `is_active` indexed inside `record_timestamps`, we can now load the top 30% **recent active** records directly during boot:
```sql
SELECT id FROM "record_timestamps" 
WHERE db_name = ? AND is_active = 1 
ORDER BY timestamp DESC LIMIT ?
```
* **Performance Gain:** The main thread gets only active, relevant records on launch, reducing memory usage and eliminating any post-boot segregation loops!
