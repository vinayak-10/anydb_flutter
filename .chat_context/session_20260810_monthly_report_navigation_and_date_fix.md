# Session: 2026-08-10 — Monthly Report Background Navigation & Date Column Fix

## Commit
`b6b6093` — fix: resolve monthly report background navigation and date overwrite in isolate worker

---

## Problem Statement

Two related bugs surfaced after Wave 6 introduced background monthly report generation:

1. **Silent navigation death** — after `generateMonthlyBatch` completed in the background isolate, the `Navigator.push` call that should navigate the user to the generated report was silently swallowed. `if (!mounted) return` (our prior fix to prevent a `Bad state` crash) inadvertently killed navigation when the generating widget unmounted during the long async wait.

2. **Empty monthly report** — when the user manually re-opened a just-generated monthly report (e.g., June 2026), the report showed all zeros. `COUNTIF($Date.START:$Date.END, "*")` returned 0.0 despite 27 rows being present.

---

## Root Cause Analysis

### Bug 1 — Navigation silently killed

In `_runMonthlyBatch` (`collection_view.dart`), after the `await IsolateWorker.runWithInactivityTimeout(...)` gap (≈90 seconds for a 30-day month), Flutter had long since unmounted `_AggregatorViewState`. The `!mounted` guard before `Navigator.push` correctly prevented a crash — but also prevented navigation. The user was left stranded with no report and no indication of success.

`FeedbackToast.success(context, ...)` and `FeedbackToast.error(context, ...)` also silently failed because `ScaffoldMessenger.of(context)` throws on an unmounted widget. `ref.read(monthlyReportTaskProvider).isGenerating` similarly crashed after unmount.

### Bug 2 — COUNTIF(Date) = 0 with 27 rows

The regeneration path in `runReportGenerationPipeline` (`isolate_worker.dart`) builds `monthlyRow` per working day:

```dart
monthlyRow['Date'] = DateFormat('dd/MM/yyyy').format(date);  // "01/06/2026"

for (final col in monthlyColumns) {
  final String title = col['title']?.toString() ?? '';
  // ... formula → colIdx → dailySummaryKeys[colIdx]
  monthlyRow[title] = daySummary[dailySummaryKeys[colIdx]] ?? 0;
}
```

The monthly schema has 'Date' as its first column (formula `='Daily'!A7`). The loop resolves this to `colIdx = 0`, maps to `dailySummaryKeys[0]` (e.g., 'Charges'), and **overwrites** `monthlyRow['Date']` with a float like `4190.0`.

`AggregatorReport.generateData()` then receives records where `'Date'` = float. `FormulaEngine.evaluate('COUNTIF($Date.START:$Date.END, "*")', ...)` uses `"*"` which matches only non-empty strings — floats don't match → returns 0 → all monthly summary formulas evaluate to 0.

**Why this was not seen before Wave 6:** Pre-Wave 6, batch was synchronous. On completion, the widget was still mounted, `Navigator.push` worked immediately, and `reportDataProvider` opened the viewer with the freshly-written Excel file taking the cache path (file timestamp >> DB timestamp). The regeneration path was never reached in normal flow.

---

## Files Changed

### 1. `lib/screens/collection_view.dart` — `_runMonthlyBatch`

**Before:**
- `if (!mounted) return;` guarded navigation → killed it post-async
- `ref.read(monthlyReportTaskProvider).isGenerating` called post-await → crash on unmount
- `Navigator.push(context, ...)` → crash on unmount
- `FeedbackToast.success/error(context, ...)` → crash on unmount

**After:**
- `navigatorState = Navigator.of(context)` captured **before** any `await`
- `messengerState = ScaffoldMessenger.of(context)` captured **before** any `await`
- `taskNotifier.state.isGenerating` used post-await (Notifier instance outlives widget)
- `navigatorState.push(...)` — safe, `NavigatorState` is owned by `MaterialApp`
- `forceRebuild: true` passed to `AggregatorReportView` — bypasses stale cache
- `FeedbackToast.successWithMessenger(messengerState, ...)` — context-free toast
- `FeedbackToast.errorWithMessenger(messengerState, ...)` — context-free toast
- All `if (!mounted) return` guards removed (no longer needed)

### 2. `lib/services/isolate_worker.dart` — monthly columns loop

Added one guard line at the top of the `monthlyColumns` loop:

```dart
if (title == 'Date') continue;
```

Prevents the monthly schema's 'Date' column formula (which resolves via column index to a daily numeric summary value) from overwriting the explicitly set date string. `monthlyRow['Date']` now always holds the correct `"dd/MM/yyyy"` string → `COUNTIF($Date, "*")` returns the correct working-day count.

### 3. `lib/utils/feedback_toast.dart` — context-free toast support

- Added `FeedbackToast.successWithMessenger(ScaffoldMessengerState, message)` — identical visual to `success()`, no `BuildContext` required.
- Added `FeedbackToast.errorWithMessenger(ScaffoldMessengerState, message)` — identical visual to `error()`, no `BuildContext` required.
- Refactored internal `_show(context, ...)` to delegate to new `_showWithMessenger(messenger, ...)` — zero visual regression, all existing callers unaffected.

---

## Behavioral Equivalence (Pre vs Post Wave 6)

| Moment | Pre-Wave 6 (sync) | Post-Fix (async) |
|--------|-------------------|------------------|
| UI during generation | Frozen ~90s | Interactive (background) |
| Auto-navigation on complete | `Navigator.push(context)` | `navigatorState.push()` — same screen |
| Report data on open | Cache path (fresh file) | `forceRebuild=true` → clean regeneration |
| COUNTIF(Date) | Correct (cache path) | Correct (Date not overwritten) |
| Success toast | FeedbackToast.success | FeedbackToast.successWithMessenger — same visual |
| Cancellation | Not possible | AppBar ✕ supported |

---

## flutter analyze
0 errors. 111 pre-existing info-level hints (Share deprecated, curly_braces, etc.) — none introduced by this session.

---

## Hard Locks Confirmed
- No locked files touched (`aggregator_service.dart`, `excel_binary_helper.dart`, `excel_generation_service.dart`, `extractor_service.dart`, `report_formula_service.dart`, `workbook_service.dart`)
- No `git push` until user explicitly says "push" in a message.
