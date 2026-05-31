# Implementation Plan: High-Performance Hoisted Business Unique Key for Batch Imports

This document details the step-by-step implementation specifications to hoist the User-Selected **Business Unique Key** configuration check during batch writes (`updateAllRaw`) on native targets. By using Isolate payload parameter transfers and in-memory synchronous extraction, we reduce SQLite transaction roundtrips to **exactly one query** and eliminate 100% of event-loop yield delays.

---

## 📂 Affected Files & Architecture Map

We will modify two core system files:
1. **`lib/services/sqlite_helper_native.dart`**
   * Introduce a synchronous, pure-CPU data extraction helper: `_extractBusinessKeyValueSync`.
   * Update the single-record `_extractBusinessKeyValue` helper to delegate to this synchronous block.
   * Modify the batch import `updateAllRaw` signature to accept a pre-resolved `businessKeyName` and call the synchronous helper in its loop.
   * Refactor the main-thread `updateAll` dispatch call to fetch the business key name **once** and pass it to the Isolate.
2. **`lib/services/isolate_worker.dart`**
   * Update the background database worker isolate (`dbUpdateAll` task) to unpack the business key name from the parameter payload and feed it into `SqliteHelper.updateAllRaw`.

```
[Main Thread: SqliteHelper.updateAll]
                 │
                 │ 1. Awaits businessKeyName ONCE from DB (or RAM cache)
                 ▼
     [Isolate IPC Port Payload]  <--- Passes: {'dbName', 'items', 'businessKeyName'}
                 │
                 ▼
[Background Isolate: dbUpdateAll Task]
                 │
                 ▼
[SqliteHelper.updateAllRaw(dbName, items, businessKeyName)]
                 │
                 ├─► BEGIN TRANSACTION
                 ├─► Loop (15,000 items):
                 │     └─► _extractBusinessKeyValueSync(...) (Pure RAM, 0 Queries, 0 Yields)
                 └─► COMMIT
```

---

## 🛠️ Step-by-Step Code Specifications

### Step 1: Update `sqlite_helper_native.dart`

We will implement the following changes in `lib/services/sqlite_helper_native.dart`:

#### A. Add `_extractBusinessKeyValueSync` and Update `_extractBusinessKeyValue`
```dart
  static String? _extractBusinessKeyValueSync(String? businessKeyName, Map<String, dynamic> val, String fallbackId) {
    if (businessKeyName != null) {
      final res = _findValueRecursively(val, businessKeyName);
      if (res != null && res.isNotEmpty) {
        return res;
      }
    }
    return fallbackId;
  }

  static Future<String?> _extractBusinessKeyValue(String dbName, Map<String, dynamic> val, String fallbackId) async {
    final businessKeyName = await getBusinessUniqueKeyRaw(dbName);
    return _extractBusinessKeyValueSync(businessKeyName, val, fallbackId);
  }
```

#### B. Update `updateAllRaw` Signature and Loop
We'll update `updateAllRaw` to accept an optional `String? businessKeyName` parameter, bypassing any internal SQL lookups in the loop:
```dart
  static Future<void> updateAllRaw(String dbName, Map<String, dynamic> items, [String? businessKeyName]) async {
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);
    await initTimestampsTable();

    db.execute('BEGIN TRANSACTION');
    try {
      final stmt = db.prepare('INSERT OR REPLACE INTO "$tableName" (id, business_key_value, is_active, value) VALUES (?, ?, ?, ?)');
      final stmtTs = db.prepare('INSERT OR REPLACE INTO "record_timestamps" (db_name, id, timestamp) VALUES (?, ?, ?)');
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        final Map<String, dynamic> recordVal = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : {};
        
        // ⚡ OPTIMIZED: Synchronous RAM-based key extraction
        final businessKeyVal = _extractBusinessKeyValueSync(businessKeyName, recordVal, id);
        
        int isActive = 1;
        final meta = recordVal['__meta__'];
        if (meta is Map) {
          final time = meta['time'];
          if (time is Map) {
            if (time.containsKey('a') || time.containsKey('d')) {
              isActive = 0;
            }
          }
        }

        stmt.execute([id, businessKeyVal, isActive, jsonEncode(entry.value)]);

        final int ts = _getLatestDateStatic(recordVal);
        stmtTs.execute([dbName, id, ts]);
      }
      stmt.dispose();
      stmtTs.dispose();
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
```

#### C. Hoist Configuration Fetch in Main-Thread `updateAll` Dispatch
We'll update the `updateAll` dispatch method to load the unique key name once on the main thread and supply it inside the Isolate payload:
```dart
  static Future<void> updateAll(String dbName, Map<String, dynamic> items) async {
    if (kIsWeb) return;
    
    // ⚡ Fetch configuration key ONCE before spawning the background task
    final businessKeyName = await getBusinessUniqueKey(dbName);

    try {
      await IsolateWorker.instance.execute(
        'dbUpdateAll',
        {
          'dbName': dbName, 
          'items': items,
          'businessKeyName': businessKeyName, // ⚡ Transferred directly in payload!
        },
      );
    } catch (e) {
      debugPrint("SqliteHelper.updateAll Isolate error, falling back to local raw update: $e");
      await updateAllRaw(dbName, items, businessKeyName);
    }
  }
```

---

### Step 2: Update `isolate_worker.dart`

We will modify `lib/services/isolate_worker.dart` inside the `'dbUpdateAll'` task block to extract the pre-resolved key and supply it to the background call:

```dart
    case 'dbUpdateAll':
      final String dbName = params['dbName'];
      final Map<String, dynamic> items = Map<String, dynamic>.from(params['items']);
      final String? businessKeyName = params['businessKeyName']; // ⚡ Unpacked from payload
      
      // Synchronous batch transaction on warm SQLite connection with pre-hoisted key name
      await SqliteHelper.updateAllRaw(dbName, items, businessKeyName);
      
      // Sync cache as raw strings
      final tableCache = bgCache[dbName] ??= {};
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        tableCache[id] = jsonEncode(entry.value);
      }
      return null;
```

---

## 🧪 Verification Plan

1. **Static Analysis Check:** Run `flutter analyze` to ensure there are no compilation breaks, type mismatches, or missing parameters across the calling pipeline.
2. **Platform Compatibility Verification:** Confirm that stub methods in `sqlite_helper_web.dart` do not need modifications (their signatures do not intersect directly with these internal native methods).

---

## 📈 Expected Performance Gains

* **SQL SELECT Queries:** Slashed from $N$ (where $N = \text{number of items}$) down to **exactly 1** (or 0 if cached).
* **Asynchronousyields (`await` context switches):** Slashed from $N$ down to **exactly 1** (pre-hoisted).
* **Execution Time (15,000 Records):** Anticipated speedup from several minutes to **under 300 milliseconds**.
