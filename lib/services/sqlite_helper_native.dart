import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:path/path.dart' as p;
import 'file_service.dart';
import 'isolate_worker.dart';

class SqliteHelper {
  static sql.Database? _db;
  static final FileService _fileService = FileService();
  static String? databasePathOverride;

  static Future<sql.Database> get _database async {
    if (_db != null) return _db!;

    final root = databasePathOverride ?? await _fileService.getInternalRoot();
    final dbPath = p.join(root, 'anydb_storage.db');
    await _fileService.ensureDir(root);

    _db = sql.sqlite3.open(dbPath);
    _db!.execute('PRAGMA journal_mode=WAL;');
    _db!.execute('PRAGMA synchronous=NORMAL;');
    _db!.execute('PRAGMA cache_size = -128000;');
    _db!.execute('PRAGMA temp_store = MEMORY;');

    // DLQ: Dead-letter queue for corrupted records
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS corrupted_records (
        id TEXT NOT NULL,
        db_name TEXT NOT NULL,
        raw_value TEXT,
        error_msg TEXT,
        captured_at INTEGER DEFAULT (strftime('%s','now'))
      )
    ''');

    // Guaranteed creation of Auxiliary Registry on app start
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS "record_timestamps" (
        db_name TEXT,
        id TEXT,
        is_active INTEGER DEFAULT 1,
        timestamp INTEGER,
        PRIMARY KEY (db_name, id)
      )
    ''');

    // Add is_active column to record_timestamps if not present
    final columns = _db!.select('PRAGMA table_info("record_timestamps")');
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    if (!columnNames.contains('is_active')) {
      _db!.execute(
        'ALTER TABLE "record_timestamps" ADD COLUMN is_active INTEGER DEFAULT 1',
      );
    }

    _db!.execute('''
      CREATE INDEX IF NOT EXISTS "idx_record_timestamps_active_order" 
      ON "record_timestamps" (db_name, is_active, timestamp DESC)
    ''');

    return _db!;
  }

  static Future<void> initTable(String dbName) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);

    // Check if the table already exists
    final tableCheck = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );

    if (tableCheck.isEmpty) {
      // Fresh table — create with the new schema directly
      db.execute('''
        CREATE TABLE "$tableName" (
          id TEXT PRIMARY KEY,
          business_key_value TEXT,
          is_active INTEGER DEFAULT 1,
          value TEXT
        )
      ''');
    } else {
      // Table exists — check columns and migrate if needed
      final columns = db.select('PRAGMA table_info("$tableName")');
      final columnNames = columns.map((c) => c['name'] as String).toSet();

      // Migrate old `key` column to `id`
      if (columnNames.contains('key') && !columnNames.contains('id')) {
        db.execute('ALTER TABLE "$tableName" RENAME COLUMN "key" TO "id"');
      }

      // Add missing columns from the new schema
      if (!columnNames.contains('business_key_value')) {
        db.execute(
          'ALTER TABLE "$tableName" ADD COLUMN business_key_value TEXT',
        );
      }
      if (!columnNames.contains('is_active')) {
        db.execute(
          'ALTER TABLE "$tableName" ADD COLUMN is_active INTEGER DEFAULT 1',
        );
      }
    }

    db.execute('''
      CREATE INDEX IF NOT EXISTS "idx_active_business_key_$tableName" 
      ON "$tableName" (business_key_value) 
      WHERE is_active = 1
    ''');
  }

  static Future<List<Map<String, dynamic>>> getAll(
    String dbName, {
    String filter = 'Active',
    bool allRecords = false,
  }) async {
    if (kIsWeb) return [];

    // Delegate record reading and sorting to the background Database Isolate
    try {
      final List<dynamic> results = await IsolateWorker.instance
          .execute<List<dynamic>>('dbGetAll', {
            'dbName': dbName,
            'filter': filter,
            'allRecords': allRecords,
          });
      // Zero-copy port optimization: decode the raw JSON strings on the main thread
      return results.map((item) {
        final map = item as Map;
        final key = map['id'] as String;
        final decoded = jsonDecode(map['value'] as String);
        return {
          key: decoded is Map ? Map<String, dynamic>.from(decoded) : decoded,
        };
      }).toList();
    } catch (e) {
      debugPrint(
        "SqliteHelper.getAll Isolate error, falling back to local raw read: $e",
      );
      return await getAllRaw(dbName);
    }
  }

  static Future<Map<String, dynamic>?> get(String dbName, String key) async {
    if (kIsWeb) return null;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select('SELECT value FROM "$tableName" WHERE id = ?', [
      key,
    ]);
    if (results.isNotEmpty) {
      final value = jsonDecode(results.first['value'] as String);
      return {key: value is Map ? Map<String, dynamic>.from(value) : value};
    }
    return null;
  }

  static String? _findValueRecursively(
    Map<String, dynamic> map,
    String targetKey,
  ) {
    for (var entry in map.entries) {
      if (entry.key.toLowerCase() == targetKey.toLowerCase()) {
        final val = entry.value?.toString().trim();
        if (val != null && val.isNotEmpty) {
          return val;
        }
      }
      if (entry.value is Map) {
        final res = _findValueRecursively(
          Map<String, dynamic>.from(entry.value as Map),
          targetKey,
        );
        if (res != null && res.isNotEmpty) {
          return res;
        }
      }
    }
    return null;
  }

  static String? _extractBusinessKeyValueSync(
    String? businessKeyName,
    Map<String, dynamic> val,
    String fallbackId,
  ) {
    if (businessKeyName != null) {
      final res = _findValueRecursively(val, businessKeyName);
      if (res != null && res.isNotEmpty) {
        return res;
      }
    }
    return fallbackId;
  }

  static Future<void> update(String dbName, String key, dynamic val) async {
    if (kIsWeb) return;
    final businessKeyName = await getBusinessUniqueKey(dbName);
    try {
      await IsolateWorker.instance.execute('dbUpdateSingle', {
        'dbName': dbName,
        'id': key,
        'value': val,
        'businessKeyName': businessKeyName,
      });
    } catch (e) {
      debugPrint(
        "SqliteHelper.update Isolate error, falling back to direct update: $e",
      );
      await updateRaw(dbName, key, val, businessKeyName);
    }
  }

  static Future<void> updateRaw(
    String dbName,
    String key,
    dynamic val, [
    String? businessKeyName,
  ]) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final Map<String, dynamic> recordVal = val is Map
        ? Map<String, dynamic>.from(val)
        : {};
    final businessKeyVal = _extractBusinessKeyValueSync(
      businessKeyName,
      recordVal,
      key,
    );

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

    db.execute(
      'INSERT OR REPLACE INTO "$tableName" (id, business_key_value, is_active, value) VALUES (?, ?, ?, ?)',
      [key, businessKeyVal, isActive, jsonEncode(val)],
    );

    // Update Auxiliary timestamp table
    final int ts = _getLatestDateStatic(recordVal);
    await updateRecordTimestamp(dbName, key, isActive, ts);
  }

  static Future<void> updateAll(
    String dbName,
    Map<String, dynamic> items,
  ) async {
    if (kIsWeb) return;

    // Fetch configuration key ONCE before spawning the background task
    final businessKeyName = await getBusinessUniqueKey(dbName);

    // Delegate batch updates to the background Database Isolate transaction
    try {
      await IsolateWorker.instance.execute('dbUpdateAll', {
        'dbName': dbName,
        'items': items,
        'businessKeyName': businessKeyName,
      });
    } catch (e) {
      debugPrint(
        "SqliteHelper.updateAll Isolate error, falling back to local raw update: $e",
      );
      await updateAllRaw(dbName, items, businessKeyName);
    }
  }

  static Future<void> remove(String dbName, String key) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);
    await initTimestampsTable();

    db.execute('DELETE FROM "$tableName" WHERE id = ?', [key]);
    db.execute('DELETE FROM "record_timestamps" WHERE db_name = ? AND id = ?', [
      dbName,
      key,
    ]);
  }

  static Future<void> clear(String dbName) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    db.execute('DROP TABLE IF EXISTS "$tableName"');
    db.execute('DELETE FROM "record_timestamps" WHERE db_name = ?', [dbName]);
    await initTable(dbName);
  }

  static Future<Map<String, dynamic>?> getActiveByBusinessKey(
    String dbName,
    String businessKeyValue,
  ) async {
    if (kIsWeb) return null;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select(
      'SELECT id, value FROM "$tableName" WHERE business_key_value = ? AND is_active = 1 LIMIT 1',
      [businessKeyValue],
    );

    if (results.isNotEmpty) {
      final id = results.first['id'] as String;
      final value = jsonDecode(results.first['value'] as String);
      return {id: value is Map ? Map<String, dynamic>.from(value) : value};
    }
    return null;
  }

  static Future<void> initConfigurationsTable() async {
    if (kIsWeb) return;
    final db = await _database;
    db.execute('''
      CREATE TABLE IF NOT EXISTS "schema_configurations" (
        schema_name TEXT PRIMARY KEY,
        business_unique_key TEXT
      )
    ''');
  }

  static Future<String?> getBusinessUniqueKey(String schemaName) async {
    if (kIsWeb) return null;
    try {
      return await IsolateWorker.instance.execute<String?>(
        'dbGetBusinessUniqueKey',
        {'schemaName': schemaName},
      );
    } catch (e) {
      debugPrint(
        "SqliteHelper.getBusinessUniqueKey Isolate error, falling back to direct read: $e",
      );
      return await getBusinessUniqueKeyRaw(schemaName);
    }
  }

  static Future<void> setBusinessUniqueKey(
    String schemaName,
    String keyName,
  ) async {
    if (kIsWeb) return;
    try {
      await IsolateWorker.instance.execute('dbSetBusinessUniqueKey', {
        'schemaName': schemaName,
        'keyName': keyName,
      });
    } catch (e) {
      debugPrint(
        "SqliteHelper.setBusinessUniqueKey Isolate error, falling back to direct write: $e",
      );
      await setBusinessUniqueKeyRaw(schemaName, keyName);
    }
  }

  static Future<String?> getBusinessUniqueKeyRaw(String schemaName) async {
    if (kIsWeb) return null;
    final db = await _database;
    await initConfigurationsTable();
    final results = db.select(
      'SELECT business_unique_key FROM "schema_configurations" WHERE schema_name = ?',
      [schemaName],
    );
    if (results.isNotEmpty) {
      return results.first['business_unique_key'] as String?;
    }
    return null;
  }

  static Future<void> setBusinessUniqueKeyRaw(
    String schemaName,
    String keyName,
  ) async {
    if (kIsWeb) return;
    final db = await _database;
    await initConfigurationsTable();
    db.execute(
      'INSERT OR REPLACE INTO "schema_configurations" (schema_name, business_unique_key) VALUES (?, ?)',
      [schemaName, keyName],
    );
  }

  static Future<List<Map<String, dynamic>>> getAllRaw(String dbName) async {
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select('SELECT id, value FROM "$tableName"');
    return results.map((row) {
      final key = row['id'] as String;
      final value = jsonDecode(row['value'] as String);
      return {key: value is Map ? Map<String, dynamic>.from(value) : value};
    }).toList();
  }

  static Future<List<Map<String, String>>> getAllRawString(
    String dbName,
  ) async {
    if (kIsWeb) return [];
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select('SELECT id, value FROM "$tableName"');
    return results.map((row) {
      return {'id': row['id'] as String, 'value': row['value'] as String};
    }).toList();
  }

  static Future<List<Map<String, String>>> getActiveRecordsRawString(
    String dbName,
  ) async {
    if (kIsWeb) return [];
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select(
      'SELECT id, value FROM "$tableName" WHERE is_active = 1',
    );
    return results.map((row) {
      return {'id': row['id'] as String, 'value': row['value'] as String};
    }).toList();
  }

  static Future<List<Map<String, String>>> getInactiveRecordsRawString(
    String dbName,
  ) async {
    if (kIsWeb) return [];
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select(
      'SELECT id, value FROM "$tableName" WHERE is_active = 0',
    );
    return results.map((row) {
      return {'id': row['id'] as String, 'value': row['value'] as String};
    }).toList();
  }

  static Future<void> updateAllRaw(
    String dbName,
    Map<String, dynamic> items, [
    String? businessKeyName,
  ]) async {
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);
    await initTimestampsTable();

    db.execute('BEGIN TRANSACTION');
    try {
      final stmt = db.prepare(
        'INSERT OR REPLACE INTO "$tableName" (id, business_key_value, is_active, value) VALUES (?, ?, ?, ?)',
      );
      final stmtTs = db.prepare(
        'INSERT OR REPLACE INTO "record_timestamps" (db_name, id, is_active, timestamp) VALUES (?, ?, ?, ?)',
      );
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        final Map<String, dynamic> recordVal = entry.value is Map
            ? Map<String, dynamic>.from(entry.value as Map)
            : {};

        // ⚡ OPTIMIZED: Synchronous RAM-based key extraction
        final businessKeyVal = _extractBusinessKeyValueSync(
          businessKeyName,
          recordVal,
          id,
        );

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
        stmtTs.execute([dbName, id, isActive, ts]);
      }
      stmt.dispose();
      stmtTs.dispose();
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static int _getLatestDateStatic(Map<String, dynamic> record) {
    int maxDate = 0;
    try {
      final account = record['Account'];
      if (account is Map && account.isNotEmpty) {
        final history = account.values.first;
        if (history is List) {
          for (var tx in history) {
            if (tx is Map) {
              final d = tx['Date'] ?? tx['Transaction Date'] ?? tx['time'];
              if (d != null) {
                int dt = 0;
                if (d is int) {
                  dt = d;
                } else if (d is String) {
                  dt =
                      DateTime.tryParse(d)?.millisecondsSinceEpoch ??
                      int.tryParse(d) ??
                      0;
                }
                if (dt > maxDate) maxDate = dt;
              }
            }
          }
        }
      }

      final meta = record['__meta__'];
      if (meta is Map) {
        final time = meta['time'];
        if (time is Map) {
          final u = time['u'] ?? time['c'];
          if (u is int && u > maxDate) maxDate = u;
        }
      }
    } catch (_) {}
    // Fallback: if no domain timestamp resolved (no Account history, no __meta__.time),
    // return the current wall-clock time instead of 0. A zero timestamp causes
    // the report cache check (fileModifiedMs >= latestDbTs) to always evaluate as
    // true, permanently locking the pipeline into serving stale cached reports.
    return maxDate > 0 ? maxDate : DateTime.now().millisecondsSinceEpoch;
  }

  static Future<void> initTimestampsTable() async {
    if (kIsWeb) return;
    final db = await _database;
    db.execute('''
      CREATE TABLE IF NOT EXISTS "record_timestamps" (
        db_name TEXT,
        id TEXT,
        is_active INTEGER DEFAULT 1,
        timestamp INTEGER,
        PRIMARY KEY (db_name, id)
      )
    ''');

    // Add is_active column to record_timestamps if not present
    final columns = db.select('PRAGMA table_info("record_timestamps")');
    final columnNames = columns.map((c) => c['name'] as String).toSet();
    if (!columnNames.contains('is_active')) {
      db.execute(
        'ALTER TABLE "record_timestamps" ADD COLUMN is_active INTEGER DEFAULT 1',
      );
    }

    db.execute('''
      CREATE INDEX IF NOT EXISTS "idx_record_timestamps_active_order" 
      ON "record_timestamps" (db_name, is_active, timestamp DESC)
    ''');
  }

  static Future<void> backfillTimestamps(String dbName) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTimestampsTable();
    await initTable(dbName);

    final mainCountRes = db.select(
      'SELECT COUNT(*) as count FROM "$tableName"',
    );
    final mainCount = mainCountRes.first['count'] as int;

    final stampCountRes = db.select(
      'SELECT COUNT(*) as count FROM "record_timestamps" WHERE db_name = ?',
      [dbName],
    );
    final stampCount = stampCountRes.first['count'] as int;

    if (mainCount != stampCount) {
      debugPrint(
        "SqliteHelper: Backfilling timestamps for $dbName (main: $mainCount, stamps: $stampCount)",
      );
      final results = db.select('SELECT id, value FROM "$tableName"');

      db.execute('BEGIN TRANSACTION');
      try {
        final stmt = db.prepare(
          'INSERT OR REPLACE INTO "record_timestamps" (db_name, id, is_active, timestamp) VALUES (?, ?, ?, ?)',
        );
        for (var row in results) {
          final id = row['id'] as String;
          final valueStr = row['value'] as String;
          int ts = 0;
          int isActive = 1;
          try {
            final decoded = jsonDecode(valueStr);
            if (decoded is Map) {
              ts = _getLatestDateStatic(Map<String, dynamic>.from(decoded));
              final meta = decoded['__meta__'];
              if (meta is Map) {
                final time = meta['time'];
                if (time is Map) {
                  if (time.containsKey('a') || time.containsKey('d')) {
                    isActive = 0;
                  }
                }
              }
            }
          } catch (e) {
            _quarantineRecord(db, dbName, id, valueStr, e.toString());
          }
          stmt.execute([dbName, id, isActive, ts]);
        }
        stmt.dispose();
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        debugPrint("SqliteHelper: Backfill failed: $e");
      }
    }
  }

  static Future<void> updateRecordTimestamp(
    String dbName,
    String id,
    int isActive,
    int timestamp,
  ) async {
    if (kIsWeb) return;
    final db = await _database;
    await initTimestampsTable();
    db.execute(
      'INSERT OR REPLACE INTO "record_timestamps" (db_name, id, is_active, timestamp) VALUES (?, ?, ?, ?)',
      [dbName, id, isActive, timestamp],
    );
  }

  static Future<List<String>> getTopRecentIds(
    String dbName,
    int limit, {
    String filter = 'Active',
  }) async {
    if (kIsWeb) return [];
    final db = await _database;
    await initTimestampsTable();

    String query;
    List<dynamic> args;
    if (filter == 'Active') {
      query =
          'SELECT id FROM "record_timestamps" WHERE db_name = ? AND is_active = 1 ORDER BY timestamp DESC LIMIT ?';
      args = [dbName, limit];
    } else if (filter == 'Archived' || filter == 'Deleted') {
      query =
          'SELECT id FROM "record_timestamps" WHERE db_name = ? AND is_active = 0 ORDER BY timestamp DESC LIMIT ?';
      args = [dbName, limit];
    } else {
      query =
          'SELECT id FROM "record_timestamps" WHERE db_name = ? ORDER BY timestamp DESC LIMIT ?';
      args = [dbName, limit];
    }

    final results = db.select(query, args);
    return results.map((row) => row['id'] as String).toList();
  }

  static Future<List<Map<String, String>>> getRecordsByIds(
    String dbName,
    List<String> ids,
  ) async {
    if (kIsWeb) return [];
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    if (ids.isEmpty) return [];

    final placeholders = List.filled(ids.length, '?').join(',');
    final results = db.select(
      'SELECT id, value FROM "$tableName" WHERE id IN ($placeholders)',
      ids,
    );
    return results.map((row) {
      return {'id': row['id'] as String, 'value': row['value'] as String};
    }).toList();
  }

  static Future<bool> isTableEmpty(String dbName) async {
    if (kIsWeb) return true;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);
    final result = db.select('SELECT COUNT(*) as count FROM "$tableName"');
    if (result.isNotEmpty) {
      return (result.first['count'] as int) == 0;
    }
    return true;
  }

  static Future<int> getLatestTimestamp(String dbName) async {
    if (kIsWeb) return 0;
    final db = await _database;
    await initTimestampsTable();
    final result = db.select(
      'SELECT MAX(timestamp) as max_ts FROM "record_timestamps" WHERE db_name = ?',
      [dbName],
    );
    if (result.isNotEmpty && result.first['max_ts'] != null) {
      return result.first['max_ts'] as int;
    }
    return 0;
  }
  static Future<void> _quarantineRecord(
    sql.Database db,
    String dbName,
    String id,
    String rawValue,
    String errorMsg,
  ) async {
    try {
      db.execute(
        'INSERT OR REPLACE INTO corrupted_records (id, db_name, raw_value, error_msg) VALUES (?, ?, ?, ?)',
        [id, dbName, rawValue, errorMsg],
      );
      debugPrint(
        'SqliteHelper DLQ: Quarantined record id="$id" db="$dbName": $errorMsg',
      );
    } catch (e) {
      debugPrint('SqliteHelper DLQ insert failed: $e');
    }
  }
}
