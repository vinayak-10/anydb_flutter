# Session Context: Report Cache Write Timestamp Fix (2026-06-27)

## Problem Statement
The daily and monthly report cache-invalidation pipeline was not catching database changes instantly, and occasionally failing to pick up changes entirely.

## Root Cause Analysis
1. **The Staleness Check:**
   The Process Isolate (`Isolate 2`) decides if a report's cache is valid by comparing the workbook file's disk modification time (`fileModifiedMs`) with the latest database update timestamp (`latestDbTs`).
2. **Domain vs. Wall-Clock Timestamps:**
   Previously, `latestDbTs` was retrieved via `SqliteHelper.getLatestTimestamp(dbName)`, which queried `MAX(timestamp)` in the `record_timestamps` table.
   However, `record_timestamps.timestamp` stores the chronological **domain** date of the record (e.g., patient transaction date or registration date), which is normalized to midnight of that day (e.g., `2026-06-27 00:00:00`).
3. **The Logical Flaw:**
   When a report file is written at (for example) `11:00 AM`, its `fileModifiedMs` is greater than `latestDbTs` (midnight of the same day).
   If a user subsequently edits or adds a transaction on the same day, its domain timestamp (still at midnight) is less than the file's modification time (`11:00 AM`). As a result, `fileModifiedMs >= latestDbTs` evaluates to `true`, causing the generator to serve the stale cached Excel file instead of rebuilding it.

## Remediation Details

### 1. Database Metadata Table (`database_metadata`)
Created a dedicated `database_metadata` table to track the actual wall-clock write timestamp (`latest_write_ts`) per database, completely decoupling cache invalidation checks from domain/chronological transaction dates.
```sql
CREATE TABLE IF NOT EXISTS "database_metadata" (
  db_name TEXT PRIMARY KEY,
  latest_write_ts INTEGER
);
```

### 2. Write Hook Integration
Added calls to `updateLatestWriteTimestamp` inside:
* `SqliteHelper.updateRaw`
* `SqliteHelper.updateAllRaw`
* `SqliteHelper.remove`
* `SqliteHelper.clear`

Whenever any record is saved, batched, removed, or cleared, `latest_write_ts` is instantly updated to the current wall-clock epoch ms (`DateTime.now().millisecondsSinceEpoch`).

### 3. Updated Freshness Resolution
Modified `getLatestTimestamp` to query `database_metadata` first to fetch the actual write timestamp, falling back to the `record_timestamps` table only if no metadata is found.

### 4. Parity Stubs
Updated [sqlite_helper_web.dart](file:///home/ruggedcoder/softwares/fresh/anydb_flutter/lib/services/sqlite_helper_web.dart) to define an empty `updateLatestWriteTimestamp` stub method, maintaining exact web/native interface parity.

## Impact & Results
* **Instant Invalidation:** Every database write now instantly invalidates the report cache, causing the report generator to accurately pick up and compile the new data.
* **Backward Compatibility:** Handled fallback to existing `record_timestamps` data to guarantee a seamless transition.
* **Testing:** Ran the complete test suite and confirmed all 15 tests pass successfully.
