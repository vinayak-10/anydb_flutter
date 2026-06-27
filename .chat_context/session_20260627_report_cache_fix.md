# Session Context — 2026-06-27 (Report Cache Fix & UI Hardening)

## Session Overview

Two major work streams completed this session:
1. **Five UI/UX feature implementations** (approved via implementation plan)
2. **Root cause analysis + fix of the report cache staleness bug** (new records not appearing in reports for 60+ seconds)

---

## Work Stream 1 — UI/UX Feature Implementations

Approved plan lived in session artifact `implementation_plan.md`. All five items implemented.

### 1. Purge Data — Moved to Deleted Tab Only
- **File:** `lib/screens/collection_view.dart`
- **Change:** Removed the "Purge Data" menu option from the Active records list. Purge is now exclusively available in the Deleted tab, where it is semantically appropriate (permanently remove already-soft-deleted records).
- **Rationale:** Prevents accidental permanent deletion from the primary active records view.

### 2. Schema Editor `defaultValue` Fix
- **Files:** Schema editor/builder screens
- **Change:** Fixed the schema builder so that field-level configuration properties like `defaultValue`, `placeholder`, `required`, etc. are correctly serialized into the raw JSON schema when saving. Previously these UI-configured values were not being written to the JSON schema definition.
- **Root Cause:** The schema editor's save path was shallow-copying the field map without persisting widget-specific config keys.

### 3. Mark-for-Delete Grace Period Extended to 5 Days
- **File:** `lib/services/element_db.dart` (or lifecycle constants)
- **Change:** Extended the soft-delete retention window to **5 days** before permanently eligible for purge.
- **Rationale:** Gives users more time to recover accidentally deleted records.

### 4. Edit FAB on Element Entry Cards
- **File:** `lib/widgets/element_card.dart` (or equivalent card widget)
- **Change:** The "Edit" action on individual database record cards was changed from a small icon button in the top-right to a **FAB at the bottom of each card** with "EDIT" label below the icon.
- **Clarification:** This applies to the record card in the list view. The AppBar edit button inside ElementView detail pane remains unchanged.

### 5. Schema Change Auto-Reload
- **Files:** `lib/screens/schema_editor.dart`, `lib/main.dart`
- **Change:** After a schema is saved/edited, the app now automatically reloads to apply schema changes (Navigator pop-to-root + re-init of schema-dependent providers).

---

## Work Stream 2 — Report Cache Staleness: Root Cause Analysis

### Problem Statement
After adding a new record, it took **60+ seconds** (sometimes never, without "Force rebuild") for the record to appear in generated reports.

### Architecture
- **Isolate 1** (Database Worker): `SqliteHelper` + warm `bgCache` — all SQLite writes.
- **Isolate 2** (Process Worker): Report pipeline — queries Isolate 1 for `latestDbTs`, compares with cached `.xlsx` OS modification time to decide if cache is stale.

### Root Cause Chain (4 compounding bugs)

**Bug 1 (Primary):** `sqlite_helper_native.dart` `_getLatestDateStatic()` returns `0` for plain form records (no Account history, no MetaDefault component). `record_timestamps.timestamp = 0`.

**Bug 2:** When Account history exists, `DateTime.tryParse("2026-06-27")` returns midnight, not the actual write time. Any report cached earlier the same day has a later OS mtime → cache always wins.

**Bug 3:** `ElementDb.addRecord()` never fires `onDbEntryAdd`/`onDbEntryUpdate` events that would inject `__meta__.time.u` via `EventActionMeta`. The event pipeline is defined but never triggered for normal saves.

**Bug 4:** `MetaDefault.fetch()` correctly computes `time.c`/`time.u` but MetaDefault is absent from most schemas.

**Final Gate** (`isolate_worker.dart`, Process Isolate):
```dart
if (fileModifiedMs >= latestDbTs) {  // 11:05 AM >= 0 → ALWAYS TRUE
    return cachedExcelFile;           // stale report served
}
```

---

## Work Stream 2 — Fix Implementation

### Files Changed (3 total — NO hard-locked files touched)

#### `lib/services/element_db.dart` · `addRecord()` L368–L384 (PRIMARY FIX)
Injects `__meta__.time.u` and `__meta__.time.c` before every `storage.add()` call — same pattern as `markArchive`/`markDelete`/`restore`.

```dart
final nowMs = DateTime.now().millisecondsSinceEpoch;
if (recordVal is Map) {
  final rv = recordVal as Map<String, dynamic>;
  rv['__meta__'] ??= <String, dynamic>{};
  rv['__meta__']['time'] ??= <String, dynamic>{};
  final timeMap = rv['__meta__']['time'] as Map<String, dynamic>;
  if (!timeMap.containsKey('c')) timeMap['c'] = nowMs;
  timeMap['u'] = nowMs;
}
await storage.add(recordKey, recordVal);
```

#### `lib/services/sqlite_helper_native.dart` · `_getLatestDateStatic()` L555 (SAFETY NET)
```dart
return maxDate > 0 ? maxDate : DateTime.now().millisecondsSinceEpoch;
```

#### `lib/services/storage_service.dart` · `_getLatestDateStatic()` L206 (MIRROR FIX)
```dart
return maxDate > 0 ? maxDate : DateTime.now().millisecondsSinceEpoch;
```

### Formula Engine Safety Audit — CONFIRMED SAFE

| Gate | Location | Effect on `__meta__` |
|------|----------|----------------------|
| `_recordMatchesDatePredicate` | `isolate_worker.dart` | Explicitly `continue`-d |
| `_segregate` | `extractor_service.dart` L241 | Only reads `time.a`/`time.d` — `time.u`/`time.c` ignored |
| `_filter` | `extractor_service.dart` L317 | Schema column whitelist drops `c`/`u` |
| Formula pipeline | Hard-locked files | Reads `.xlsx` cell refs only — no SQLite fields ever reach here |

The monthly report formula engine is **100% unaffected**.

---

## Hard-Lock Rule (CRITICAL — carry forward to ALL future sessions)

The following files are **PERMANENTLY HARD-LOCKED**. Under no circumstances should they be modified:
- `aggregator_service.dart`
- `excel_binary_helper.dart`
- `excel_generation_service.dart`
- `extractor_service.dart`
- `report_formula_service.dart`
- `workbook_service.dart`
- All related reporting models/services

If any planned change has a cascading effect on these files or their data structures, **STOP immediately, notify the user, and revert to the nearest safe code state.**

---

## Pending Items for Next Session
- **Git commit & push** for this session's changes (3 files: `element_db.dart`, `sqlite_helper_native.dart`, `storage_service.dart`)
- **Device test:** Add a record → immediately generate a daily report (no "Force rebuild") → confirm the new record appears.
- **Planned Optimization (deferred):** Hoist `getBusinessUniqueKeyRaw(dbName)` outside the `updateAllRaw` batch loop to eliminate ~15,000 SELECT queries during DB reload.
- **Planned Optimization (deferred):** SQLite WASM + OPFS for high-capacity web database storage.
