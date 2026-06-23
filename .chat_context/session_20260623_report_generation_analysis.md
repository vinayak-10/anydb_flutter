# Report Generation Engine Analysis — Root Cause Diagnosis (2026-06-23)

## Session Summary
Analyzed the report generation engine to diagnose three issues reported after recent changes:
1. **Monthly report shows empty sheet** — only dates visible, all values blank, totals = 0
2. **Date picker shows month only** — not day/month/year
3. **Documents directory hierarchy not maintained** on Android

---

## Issue 1: Monthly Report Empty (Critical Bug)

### Root Cause Location
**File:** `lib/services/aggregator_service.dart`  
**Line:** 407  
**Method:** `generateMonthlyBatch()`

### The Bug
```dart
// Line 402-409 in generateMonthlyBatch()
final dailyData = await dailyReport.extractor[0].extractor!
    .applyPredicate(
      dailyReport.extractor[0].extractor!.predicates[0],
      data: date,
      getFileName: (meta, {DateTime? timestamp}) =>
          getFileName(meta, timestamp: timestamp ?? batchTimestamp, sourceReport: monthlyReport),  // BUG: monthlyReport
      force: force,
    );
```

**Problem:** During the daily loop in monthly batch generation, `sourceReport: monthlyReport` is passed to `getFileName()`. This causes:
1. `monthlyReport.applyMeta()` formats dates as `MMM_yyyy` (e.g., "Feb_2026")
2. **All daily sheets get the SAME collection name** `Monthly_Feb_2026` and SAME sheet name `Feb_2026`
3. Each day **overwrites** the previous day's sheet
4. Only the last day's data survives in the workbook

### Why Totals Are 0
In `ExtractorReport._prepare()` (extractor_service.dart:614-645), formulas reference sheets by the **daily report's source name** (e.g., "Daily"):
```dart
final refRegex = RegExp(r"(?:'([^']+)'|([^!]+))!([A-Z]+)([0-9]+)");
```
But sheets were written with monthly-formatted names. Coordinate lookup fails → defaults to 0.

### The Complete Fix (Two Locations)

**Fix 1: Line 407** - `getFileName` callback in `applyPredicate`:
```dart
getFileName: (meta, {DateTime? timestamp}) =>
    getFileName(meta, timestamp: timestamp ?? batchTimestamp, sourceReport: dailyReport),
```

**Fix 2: Line 418** - `sourceReport` in `generateReport` call (THE CRITICAL ONE):
```dart
final result = await generateReport(
  reportData,
  timestamp: batchTimestamp,
  sourceReport: dailyReport,  // CHANGE FROM monthlyReport
);
```

The comment at lines 468-471 explicitly documents this:
> // Pass the DAILY report when writing individual daily sheets so that they are stored under the daily collection name (Bug 6 fix).

But the code passes `monthlyReport` - this is the bug.

### Why Both Fixes Are Needed

| Location | Purpose | If Wrong |
|----------|---------|----------|
| Line 407 (`getFileName` callback) | Used by extractor to build return metadata (`extra.name`, `extra.header`, etc.) | Extractor metadata wrong, but may be overridden |
| Line 418 (`generateReport` call) | **Determines actual workbook write metadata** via `applyMeta` → `workbook.write` | **All daily sheets written with monthly collection/sheet names → overwrite each other** |

The line 418 fix is the critical one because `generateReport` calls `sourceReport.applyMeta()` which formats the date as `MMM_yyyy` and creates collection name `"Monthly_Feb_2026"`, causing all 30 days to write to the same sheet.

---

## Issue 2: Date Picker Shows Month Only

### Current Code (collection_view.dart:4580)
```dart
final picked = await showDatePicker(
  context: context,
  initialDate: widget.selectedDate,
  firstDate: DateTime(2000),
  lastDate: DateTime(2100),
);
```

This **correctly uses `showDatePicker`** (not `showMonthPicker`). Commit `e4f0463` ("revert: display date only during date picker selection") reverted a prior incorrect change.

### Why It Might Still Appear Month-Only
1. **Flutter/platform behavior**: On some versions/platforms, `showDatePicker` may default to month/year view
2. **`widget.selectedDate` value**: If it comes from a different flow using `date_time.dart` component
3. **Display format**: The subtitle (line 4576) uses `DateFormat.yMMMMd()` showing "June 23, 2026" — this is correct

### Verification Needed
Add debug logging to confirm:
- `showDatePicker` is actually called
- `widget.selectedDate` value passed
- Platform-specific behavior

---

## Issue 3: Documents Directory Hierarchy Not Maintained (Android)

### Current Code (file_service.dart:256-291)
```dart
Future<void> copyToPublicDocuments(
  String sourcePath,
  String displayName, {
  required String relativePath,  // e.g., "xyz.maya/anydb/schema/MySchema/reports"
}) async {
  if (isAndroid()) {
    await _fileSaverChannel.invokeMethod('saveFileToDocuments', {
      'sourcePath': sourcePath,
      'displayName': displayName,
      'relativePath': relativePath,
      'mimeType': ...,
    });
  }
  ...
}
```

### Root Cause
The **Flutter code correctly passes `relativePath`**. The issue is in the **native Android implementation** (Kotlin/Java handler for `com.example.anydb_flutter/file_saver` MethodChannel).

On Android 11+ (Scoped Storage), the native handler must:
1. Parse `relativePath` 
2. Recursively create directory hierarchy via MediaStore API
3. Insert file with proper `MediaColumns.RELATIVE_PATH`

**If the native handler doesn't create parent directories**, files are saved flat in `Documents/` root.

### Required Native Fix (Not in Flutter Code)
```kotlin
// In native Android handler
val relativePath = call.argument<String>("relativePath")
// Must create: Documents/xyz.maya/anydb/schema/MySchema/reports/
// Using MediaStore with RELATIVE_PATH
```

---

## Related Files Analyzed

| File | Purpose |
|------|---------|
| `lib/services/aggregator_service.dart` | Report orchestration, monthly batch logic |
| `lib/services/extractor_service.dart` | `ExtractorDatabase` (flattens DB), `ExtractorReport` (reads Excel) |
| `lib/services/workbook_service.dart` | Facade for I/O, caching, isolate delegation |
| `lib/services/excel_generation_service.dart` | Builds Sheet: headers (Row 0-5), summary (Row 6-7), data (Row 8+) |
| `lib/services/report_formula_service.dart` | Pre-calculates formulas, translates to Excel ranges |
| `lib/services/excel_binary_helper.dart` | ZIP/XML post-process: injects values, sorts sheets |
| `lib/services/file_service.dart` | Path management, Android MediaStore copy |
| `lib/screens/collection_view.dart` | UI: date picker, report view, batch buttons |
| `lib/core/formula_engine.dart` | AST evaluator (SUMIF/COUNTIF support) |
| `lib/core/cell_helper.dart` | Unwraps Excel CellValue types |

---

## Architecture Flow (Monthly Batch)

```
User taps "GENERATE MONTHLY" (+ "Consolidate all daily reports")
         │
         ▼
AggregatorService.generateMonthlyBatch(monthDate)
         │
         ├─► Creates placeholder monthly workbook (empty summary sheet)
         │
         ├─► Loop days 1..N:
         │     ├─► dailyReport.extractor.applyPredicate(date)
         │     │     └─► Date filters DB records in isolate (100x speedup)
         │     │
         │     ├─► dailyReport.generateReport(dailyData)
         │     │
         │     └─► generateReport(reportData, sourceReport: monthlyReport)  ← BUG HERE
         │           └─► getFileName() uses monthlyReport.applyMeta()
         │                 └─► All days → same sheet name "Feb_2026"
         │
         └─► Final: generate(monthlyReport, force: true)
               └─► ExtractorReport._prepare() reads daily sheets by "Daily" name
                     └─► Fails to find → defaults 0
```

---

## Test Verification

After fix (line 407: `monthlyReport` → `dailyReport`):
1. Run `flutter test` — all 15 tests should pass
2. Manual test: Generate monthly report with "Consolidate all daily reports" checked
3. Verify:
   - Multiple daily sheets created (01/02/2026, 02/02/2026, etc.)
   - Monthly summary sheet has calculated totals (not 0)
   - Excel file opens correctly in spreadsheet apps

---

## Commit Reference

This analysis relates to commits:
- `0a7c356` — Fix monthly view raw formulas display, totals ribbon layout
- `c93bd9a` — Refactor WorkbookService into decoupled services
- `612da78` — Fix report amount totals with schema title-to-key translation
- `d32d69b` — 100x date pre-filtering speedup
- `e4f0463` — Revert month-only date picker

---

## Next Steps

1. **Immediate**: Fix line 407 in `aggregator_service.dart`
2. **Verify**: Run `flutter analyze` and `flutter test`
3. **Test**: Generate monthly report with consolidation
4. **Date picker**: Add debug logging if issue persists
5. **Documents hierarchy**: Fix native Android MethodChannel handler (separate task)