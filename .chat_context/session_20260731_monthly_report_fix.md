# Session 2026-07-31 — Monthly Report Wrong Totals Fix

## Summary
Root-cause investigation and fix for wrong monthly report totals shown in the app viewer.
All daily reports were generating correctly; only the monthly summary totals were mismatched.

## Commit
`922ff7b` — pushed to `local-server/dev` and `origin/dev`

## Files Changed
| File | Change |
|------|--------|
| `lib/services/aggregator_service.dart` ⚠️ | Added `workbook.clearCache()` before monthly summary generation in `generateMonthlyBatch` |
| `.chat_context/monthly_report_analysis.md` | Appended Root Cause 3 analysis |

---

## Root Cause (Full Analysis)

### The bug path

`generateMonthlyBatch` (called via "Finalize Day") runs entirely on the main thread:

1. `workbook.clearCache()` at the start of the batch — cache cold.
2. Day loop: for each day, `generateReport(dailyData, sourceReport: dailyReport)` calls
   `workbook.write(...)` → `IsolateWorker.execute('writeExcel', ...)` → bytes returned →
   `ExcelGenerationService.setCacheFromBytes(fileBytes, targetPath)` warms the cache with
   the live in-memory Excel object containing the just-written sheet.
3. After all days: `generate(monthlyReport, date: monthDate, force: true)` is called.
4. Inside `generate` → `ExtractorReport.applyPredicate` → `_prepare`:
   - calls `workbook.getSheetNames(fileMeta, 'Daily')` → finds all daily sheet names
   - for each daily sheet: `workbook.read(fileMeta, sheetName)` → checks cache →
     `cachedExcelPath == targetPath` → **hits `readSheetFromCache`**
5. `readSheetFromCache` maps cells via `CellHelper.unwrap(cell?.value)`.
6. Daily sheet summary rows contain `FormulaCellValue` cells (e.g. `=SUM(I10:I45)`).
   `CellHelper.unwrap` line 14: `if (val is FormulaCellValue) return val.formula;`
   → returns `"SUM(I10:I45)"` — a string, not a number.
7. `_prepare` stores the string as the per-day total: `row[title] = "SUM(I10:I45)"`.
8. `FormulaEngine` in `generateData` tries to sum these strings → produces 0/garbage.
9. Wrong totals are stored in `monthly_data['summary']` and baked into the monthly
   summary sheet's `<v>` tags via `postProcessBytes`.
10. The app viewer reads those `<v>` tags and displays the wrong values.

### Why "Force Rebuild + Consolidate All Days" worked
That path bypasses the cache entirely — it reads from the SQLite DB (`ipcGetFilteredReportData`)
for each day and does not use `ExtractorReport._prepare` at all. No formula cells involved.

### Why it wasn't caught in testing
Session-state dependent. Dev testing typically involves an app restart between "Finalize Day"
and viewing the monthly report — which clears the static cache. With a cold cache,
`workbook.read` falls through to `readSheetInIsolate → extractCachedValues` which correctly
reads `<v>` tag numeric values from raw bytes. Only the warm-cache path (same session) fails.

---

## Fix

```dart
// aggregator_service.dart — generateMonthlyBatch, line ~524
if (generatedDays > 0) {
    logger.log("AggregatorService: Finished processing $generatedDays days. Generating final monthly summary...");
    // FIX: Clear the in-memory Excel cache before reading daily sheets back for the monthly
    // summary. Without this, WorkbookService.read hits readSheetFromCache which returns
    // FormulaCellValue as a formula string (e.g. "SUM(I10:I45)") via CellHelper.unwrap
    // instead of the computed numeric value. Clearing forces the disk path
    // (readSheetInIsolate → extractCachedValues) which correctly reads the <v> tag values.
    workbook.clearCache();
    final monthlyDataFull = await generate(monthlyReport, date: monthDate, ...);
```

The single `workbook.clearCache()` call forces `WorkbookService.read` to read the daily
sheet bytes from disk. `readSheetInIsolate` then calls `extractCachedValues` which parses
the raw XML `<v>` tags and returns correct numeric values for formula cells.

The cache is repopulated immediately after by `generateReport(monthlyDataFull, ...)`.
