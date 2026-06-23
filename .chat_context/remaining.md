# Remaining Fixes for Report Generation Engine

## Summary of Completed Fixes
- ✅ **Fix 1 (Partial - Root Cause Identified)**: Monthly report shows empty sheet with zero totals - root cause is formula cache not written during generation. Need to implement writing calculated values to `<v>` elements in Excel XML.
- ✅ **Fix 2 COMPLETED**: ExcelBinaryHelper injection error - Fixed by using `v.innerText = calculatedVal` (xml v6.x API)
- ✅ **Fix 3 COMPLETED**: Force rebuild ignored - Added `force` parameter to `workbook_service.read()` and propagated through extractor_service
- 🔄 **Fix 4 IN PROGRESS**: Riverpod disposal error in drawer_content.dart - File corrupted, needs repair

## Fix 1: Write Formula Calculated Values to Excel XML Cache

### Root Cause
When generating monthly reports, formulas are evaluated and stored in `FormulaCalculationResult.formulaValuesCache`, but these calculated values are NOT written to the Excel XML `<v>` (value) elements. Excel shows) elements. The formulas exist in `<f>` elements but without cached values in `<v>`, Excel shows 0/blank until recalculated.

### Files to Modify
1. **`lib/services/excel_generation_service.dart`** - Add XML post-processing to inject calculated values
2. **`lib/services/workbook_service.dart`** - Call the post-processing in `write()` method

### Implementation Plan
In `excel_generation_service.dart`:
- Add a static method `injectCalculatedValues()` that takes the generated Excel bytes and `formulaValuesCache`, uses `ExcelBinaryHelper.postProcessBytes()` to inject values
- This reuses the already-fixed ExcelBinaryHelper logic

In `workbook_service.dart`:
- In `write()` method, after getting `fileBytes` from isolate, call `ExcelGenerationService.injectCalculatedValues(fileBytes, formulaRegistry)` where `formulaRegistry` is passed from the isolate

## Fix 4: Repair drawer_content.dart

### Current State
The file has:
1. A method `_showAdvancedModal` defined inside `_DrawerContentState` class (lines 500-730) - with incorrect signature using `widget.onBackToHome` in parameter list
2. A duplicate `_showAdvancedModal` function defined OUTSIDE the class (lines 796-1176) - with same syntax error
3. Missing imports and broken class structure

### Required Fix
1. Remove the duplicate external function (lines 796-1176)
2. Fix the internal method signature: change `VoidCallback? widget.onBackToHome` to `VoidCallback? onBackToHome`
3. Fix all call sites to pass `onBackToHome: widget.onBackToHome` instead of `widget.onBackToHome`
4. Ensure proper imports are present

## Verification Steps
1. Run `flutter analyze` - should have 0 errors
2. Run `flutter test` - all tests pass
3. Manual test: Generate monthly report → verify totals show calculated values (not 0)
4. Manual test: Open drawer → no Riverpod disposal errors