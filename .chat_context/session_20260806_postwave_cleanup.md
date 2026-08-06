# Session 2026-08-06 — Post-Wave Lint & Build Cleanup

## Overview
After completing all 6 waves of the 15-item implementation plan, a full `flutter analyze` and CI release build were run. This session resolved all remaining static analysis warnings and a release-mode `kernel_snapshot_program` compilation failure introduced by the Wave 6 `MonthlyReportProgressButton` component.

---

## Issues Found & Fixed

### 1. Static Analysis Cleanup (`aa7db4e`)
Files: `isolate_worker.dart`, `storage_service.dart`, `schema_field_editor.dart`, `test_filtering_discrepancy.dart`

| Warning | Fix |
|---------|-----|
| `unnecessary_non_null_assertion` — `dbSendPort!.send` | Changed to `dbSendPort.send` |
| `unnecessary_cast` — `item as Map` | Removed redundant cast (guarded by `is! Map` check above) |
| `unused_import` — `dart:io` in test file | Removed unused import |
| `unused_element` — `_addElement`, `_removeElement`, `_moveElement`, `_addSummary`, `_removeSummary`, `_createDefaultSummary` in schema editor | Removed dead code methods |
| `unused_local_variable` — `isGroup` | Removed unused variable |
| `unnecessary_cast` — `(c as Map)['type']` in firstWhere | Replaced with `c is Map && c['type']` |

### 2. CI Release Build Failure — `const` on `ConsumerWidget` (`9c05e34` → `d70a6d5`)

**Root Cause:**
`MonthlyReportProgressButton extends ConsumerWidget` was placed inside `actions: const [...]` in `main.dart`. The Dart release kernel snapshot compiler (`kernel_snapshot_program`) enforces that all elements inside a `const []` list must be const-constructable at compile time. `ConsumerWidget` subclasses are **not const-constructable** — their initialisation chain includes Riverpod's runtime `WidgetRef` binding.

**Error cascade:**
- `actions: const [..., MonthlyReportProgressButton()]` → `Not a constant expression`
- `actions: [..., const MonthlyReportProgressButton()]` → Same error, shifted to `const` keyword
- **Correct fix:** `actions: [..., MonthlyReportProgressButton()]` with no `const` constructor on the class

**Files Fixed:**
- `lib/components/monthly_report_progress_button.dart` — Removed `const` from constructor declaration
- `lib/main.dart` — Changed to `actions: [ MonthlyReportProgressButton(), const GoogleDriveAuthButton() ]`
- `lib/screens/collection_view.dart` — Removed `const` from `MonthlyReportProgressButton()` call site

---

## Final Commit Log (This Session)

| Commit | Summary |
|--------|---------|
| `aa7db4e` | `fix(linter): address and resolve all static analysis warnings across lib and test` |
| `9c05e34` | `fix(build): add explicit const to MonthlyReportProgressButton in main.dart actions list` (interim, later superseded) |
| `d70a6d5` | `fix(build): remove const from MonthlyReportProgressButton - ConsumerWidget subclass does not support const construction in release kernel compilation` |

---

## Rule Learned
**`ConsumerWidget` subclasses must NEVER use `const` constructors in Flutter release builds.** They must not be placed inside `const []` list literals. Always instantiate as `MonthlyReportProgressButton()` (non-const) when embedding in AppBar actions or any const context.
