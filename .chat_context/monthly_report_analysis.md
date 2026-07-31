# Technical Analysis: Empty Monthly Report Generation Root Cause

This document provides a technical analysis of the changes responsible for generating empty monthly reports in the current codebase when compared to commit `a211a5e`.

---

## 1. Root Cause 1: Missing Extractor Reinitialization in `generateMonthlyBatch`

The primary cause of the empty monthly reports is a missing initialization call in the monthly batch generation sequence on the main thread.

### Comparison of `generateMonthlyBatch` in `lib/services/aggregator_service.dart`

* **In Commit `a211a5e`:**
  Before entering the loop that processes each day of the month, the aggregator service explicitly reinitialized the daily report's database extractor to fetch, segregate, flatten, and filter the raw records:
  ```dart
  await dailyReport.extractor[0].reinit(true);
  ```

* **In the Current Code:**
  This initialization call was removed. The daily loop begins without populating the database extractor:
  ```dart
  for (int d = 1; d <= daysInMonth; d++) {
    ...
    final dailyData = await dailyReport.extractor[0].extractor!
        .applyPredicate(
          dailyReport.extractor[0].extractor!.predicates[0],
          data: date,
          ...
        );
  ```

### Impact
1. Because `reinit()` is never called on the daily report's `ExtractorDatabase` instance, its internal record collections (`_rows` and `_data`) remain completely empty.
2. In the daily loop, `applyPredicate` is executed on this empty collection, returning `0` matched records for every day of the target month.
3. The workbook writes daily sheets that contain headers but have `0` data rows.
4. When the final monthly summary sheet is generated at the end of the batch, it runs the `ExtractorReport` to aggregate the data from these daily sheets. Because every daily sheet contains `0` data rows, the aggregated monthly values and formulas evaluate to `0` or empty results.

---

## 2. Root Cause 2: Namespace/Collection Override in `getFileName`

A secondary issue occurs when the report-generation pipeline is offloaded to the background isolate (`runReportGenerationPipeline` case in `lib/services/isolate_worker.dart`).

### File Name Resolution Mechanics

When the monthly report (`ExtractorReport`) aggregates daily sheets, it needs to locate the source workbook file containing those sheets. It calls the `getFileName` closure:

```dart
final fileMeta = getFileName != null
    ? getFileName({
        "collection": source['name'] ?? "", // Typically "Daily"
        "entry": formattedName,
        "predicate": {...pred, "value": date},
      }, timestamp: timestamp)
    : null;
```

* **In the Isolate Pipeline (`lib/services/isolate_worker.dart`):**
  The `getFileName` closure is passed to the extractor without specifying the `sourceReport` parameter:
  ```dart
  getFileName: (meta, {DateTime? timestamp}) =>
      agg.getFileName(meta, timestamp: timestamp),
  ```

* **In `lib/services/aggregator_service.dart`:**
  Because `sourceReport` is null, the `getFileName` method defaults to the monthly report (`reports.last`):
  ```dart
  final report = sourceReport ?? reports.last;
  Map<String, dynamic> nmeta = report.applyMeta(meta);
  ```
  When the monthly report's `applyMeta` runs, it overrides the `collection` key to its own key (`"Monthly"`):
  ```dart
  String n = "${key}_$formattedName"; // key is "Monthly"
  nmeta['collection'] = n.replaceAll(' ', '_');
  ```

### Impact
Instead of looking for the daily report file (e.g. `Daily_Jun_2026_[timestamp].xlsx`) or the consolidated aggregator file, the extractor resolves the target filename as `Monthly_Jun_2026_[timestamp].xlsx`. If this file does not exist or contains only empty sheets, the extraction fails to retrieve any data rows, producing an empty report.

---

## 3. Recommended Resolution Path

To restore functional monthly report generation without breaking the background isolate architecture:

1. **Re-introduce Daily Extractor Reinitialization:**
   Add `await dailyReport.extractor[0].reinit(true, force: force);` before the daily loop in `generateMonthlyBatch` inside `lib/services/aggregator_service.dart`.

2. **Align `getFileName` Parameters in Isolate Tasks:**
   In `lib/services/isolate_worker.dart` under the `runReportGenerationPipeline` case, ensure that the `getFileName` callback correctly forwards the `sourceReport` context, matching the pattern established in the main thread:
   ```dart
   getFileName: (meta, {DateTime? timestamp}) =>
       agg.getFileName(meta, timestamp: timestamp, sourceReport: report),
   ```

---

## 4. Root Cause 3: Warm In-Memory Cache Returns Formula Strings Instead of Numbers (2026-07-31)

### Symptom
Monthly report totals in the app viewer are **wrong numbers** (not zero/empty), even though
all daily reports were generated correctly each day via "Finalize Day." Force-rebuilding with
"Consolidate All Days" produces correct results.

### Root Cause

`generateMonthlyBatch` writes all daily sheets sequentially via `workbook.write`, which
keeps `ExcelGenerationService.cachedExcel` warm (the live in-memory Excel object).

When `generate(monthlyReport, ...)` runs immediately after, `ExtractorReport._prepare` calls
`workbook.read` for each daily sheet to extract the per-day summary total. Because the cache
is warm and `cachedExcelPath == targetPath`, `WorkbookService.read` returns via
`readSheetFromCache`:

```dart
// ExcelGenerationService.readSheetFromCache (LOCKED file)
return sheet.rows
    .map((row) => row.map((cell) => CellHelper.unwrap(cell?.value)).toList())
    .toList();
```

`CellHelper.unwrap` for a `FormulaCellValue` (line 14 of `cell_helper.dart`) returns:
```dart
if (val is FormulaCellValue) return val.formula;  // e.g. "SUM(I10:I45)"
```

The in-memory Excel object holds formula cells as `FormulaCellValue` objects — there is no
pre-calculated numeric result stored on them (that lives only in the `<v>` XML tags in the
raw file bytes). So every daily sheet's summary total is extracted as a formula string.

`ExtractorReport._prepare` stores these strings as row values. `FormulaEngine` then tries
to sum them → wrong/zero totals. These wrong totals get baked into the monthly summary
sheet's `<v>` tags by `postProcessBytes`. The viewer reads those `<v>` tags and faithfully
displays the wrong numbers.

The non-cache path (`readSheetInIsolate → extractCachedValues`) correctly reads `<v>` tags
from raw bytes and returns real numbers — which is why Force Rebuild worked.

### Fix Applied (commit `922ff7b`)

Added `workbook.clearCache()` in `aggregator_service.dart` immediately before
`generate(monthlyReport, ...)`. Clearing the cache forces `WorkbookService.read` to fall
through to `readSheetInIsolate` → `extractCachedValues`, which correctly parses the `<v>`
XML tags from the file bytes and returns numeric values.

```dart
// aggregator_service.dart — inside generateMonthlyBatch, before monthly summary step
workbook.clearCache();  // ← FIX: force disk path so formula cells resolve to numbers
final monthlyDataFull = await generate(monthlyReport, date: monthDate, ...);
```

This is safe: the cache is repopulated correctly by the subsequent `generateReport` write
of the monthly summary sheet, and is cleared again at the end of the batch.

### Why It Wasn't Caught Earlier

The bug is session-state dependent. In dev/test, the monthly report was typically viewed
after an app restart (cold cache) or via the isolate pipeline (always reads from disk).
Both paths use `readSheetInIsolate` which correctly resolves formula cells. The warm-cache
path only triggers when the batch runs and the report is viewed in the same session —
exactly the production usage pattern ("Finalize Day" then check the monthly summary).
