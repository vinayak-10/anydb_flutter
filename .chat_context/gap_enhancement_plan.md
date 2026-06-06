# AnyDb Gap Analysis & Future Enhancement Plan

This document details the identified architectural gaps, deferred optimizations, and recommended enhancements for the **anydb_flutter** codebase. These items are structured to guide future development iterations once core platform deployments are complete.

---

## 1. Schema Evolution & Self-Healing Migrations

### Current Limitation
* The application builds UI forms and compiles record structures dynamically based on JSON schemas. 
* Stored records on disk do not contain versioning tags. If a developer alters a schema (e.g., adding a mandatory field, removing a field, or changing a component type), old records are loaded as-is.
* This can lead to rendering issues, validation exceptions, or app crashes when the lazy model shell attempts to hydrate older payloads.

### Recommended Implementation
1. **Schema Versioning:** Add a `version` integer to the root of the database schema JSON.
2. **Migration Hook:** Introduce a migration pipeline inside `ElementDb` that runs during database boot (`initDb`).
3. **Data Hydration:** If a record's version is lower than the current schema version, auto-inject default values for new fields or convert legacy data formats on the fly before adding them to the memory collection.

---

## 2. Google Drive Sync & Conflict Resolution

### Current Limitation
* The current Google Drive synchronization system is a manual file overwrite flow (`xyz.maya/anydb/Database`). 
* If a user makes changes on Device A, backs up, and then runs a backup from Device B (which has different local changes), Device B's file overwrites Device A's backup entirely, resulting in silent data loss.

### Recommended Implementation
1. **Physical ID Tracking:** Ensure every record contains a unique physical primary key (`id`) alongside any business unique keys.
2. **Timestamp Merging:** Leverage the existing `__meta__.time.u` (updated time) and `__meta__.time.d` (deleted time) timestamps.
3. **Delta Merge Algorithm:** When importing a backup, compare local and remote lists:
   * If a record exists on both with different contents, compare the `u` timestamp and keep the one that is newer.
   * If a record exists on only one side, merge/append it to the other.

---

## 3. Dynamic Filter & Query Engine

### Current Limitation
* Database searches are limited to flat substring matches on designated schema fields or tab segregations (Active/Archived/Deleted).
* Users cannot perform complex, conditional, or range queries (e.g., finding records created in a specific date range or filtering by numeric values).

### Recommended Implementation
1. **Metadata Query Interface:** Create a dynamic visual query builder UI that populates fields based on the database schema.
2. **Dynamic SQL Generation:** Map the query constraints to SQLite JSON queries (utilizing `json_extract(value, '$.fieldName')` in SQLite queries).
3. **Isolate Processing:** Offload complex evaluation routines to the background Database Isolate worker to maintain a responsive 60fps main UI thread.

---

## 4. Local & Cloud Storage Encryption

### Current Limitation
* Database records are stored as raw JSON strings in local SQLite databases (mobile) and local SharedPreferences (web).
* Backup archives pushed to Google Drive are standard, unencrypted JSON files. Sensitive user data (notes, transactions, clinical records) is exposed in plain text.

### Recommended Implementation
1. **SQLCipher Integration:** Transition mobile SQLite storage to an encrypted database format (like SQLCipher).
2. **Payload Cryptography:** For platform-agnostic storage, encrypt the record payloads before write operations using AES-256 (deriving the key from a passcode, biometric credentials, or secure device storage).
3. **Encrypted Backups:** Encrypt the backup ZIP/JSON file locally before executing the Google Drive upload channel.

---

## 5. Hoisted Unique Key Configurations (Batch Imports)

### Current Limitation
* During database wipes or bulk imports, `SqliteHelper.updateAllRaw` runs `getBusinessUniqueKeyRaw(dbName)` inside the iteration loop.
* This forces SQLite to execute a separate `SELECT` query for every single record in the batch (up to 15,000 queries), severely slowing down imports.

### Recommended Implementation
1. **Hoist Configuration Fetching:** Move `getBusinessUniqueKeyRaw` outside the batch write loop so it executes exactly once.
2. **RAM Extraction:** Pass the resolved key name into the loop and extract the business key value in CPU memory via recursive map traversal, bypassing database query overhead.
3. **Target Performance:** Reduce batch-import and sync time from minutes to under 300 milliseconds.
