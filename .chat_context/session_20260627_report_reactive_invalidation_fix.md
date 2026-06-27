# Session Context: Report Reactive Invalidation Fix (2026-06-27)

## Problem Statement
The daily and monthly reports were not reactively updating/re-rendering in the UI when new database records were added, modified, or deleted, even though the database cache invalidation logic was updated to use wall-clock timestamps.

## Root Cause Analysis
1. **The Riverpod Watcher:**
   `reportDataProvider` watches the mutation counters for database updates:
   ```dart
   ref.watch(databaseUpdateProvider.select((m) => m[params.dbKey]));
   ```
2. **Key Mismatch:**
   * `params.dbKey` is set to the **schema title** (e.g., `xyz.maya`).
   * When database records are modified, `ElementDb` fires `onChanged` triggers which increment the mutation count using the **database table key** (e.g., `"Patients"`):
     ```dart
     ref.read(databaseUpdateProvider.notifier).increment(db.key); // db.key = "Patients"
     ```
   * Since `databaseUpdateProvider` mapping for `xyz.maya` never changed, Riverpod never detected the update, and the report view was never invalidated or rebuilt.

## Remediation Details

### 1. Dynamic Key Resolution
Updated `reportDataProvider` in `collection_view.dart` to dynamically extract all unique source database table names that the report depends on via the report's extractor configurations:
```dart
final report = params.report;
final Set<String> sourceDbKeys = {};
if (report.extractor.isNotEmpty) {
  for (var extIntf in report.extractor) {
    final name = extIntf.extractor?.source['name'];
    if (name != null) {
      sourceDbKeys.add(name);
    }
  }
}
if (sourceDbKeys.isEmpty) {
  sourceDbKeys.add(params.dbKey);
}
```

### 2. Multi-Key Watching
Registered a Riverpod watch selector on `databaseUpdateProvider` for each resolved source database key:
```dart
for (final sourceKey in sourceDbKeys) {
  ref.watch(databaseUpdateProvider.select((m) => m[sourceKey]));
}
```

## Impact & Results
* **Reactive Updates:** The daily and monthly reports now immediately refresh in the UI when database records are added, soft-archived, soft-deleted, or restored.
* **Testing:** All 15 automated tests passed cleanly.
