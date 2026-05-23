import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:path/path.dart' as p;
import 'file_service.dart';
class SqliteHelper {
  static sql.Database? _db;
  static final FileService _fileService = FileService();

  static Future<sql.Database> get _database async {
    if (_db != null) return _db!;
    
    final root = await _fileService.getInternalRoot();
    final dbPath = p.join(root, 'anydb_storage.db');
    await _fileService.ensureDir(root);
    
    _db = sql.sqlite3.open(dbPath);
    return _db!;
  }

  static Future<void> initTable(String dbName) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    db.execute('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        id TEXT PRIMARY KEY,
        business_key_value TEXT,
        is_active INTEGER DEFAULT 1,
        value TEXT
      )
    ''');
    
    db.execute('''
      CREATE INDEX IF NOT EXISTS "idx_active_business_key_$tableName" 
      ON "$tableName" (business_key_value) 
      WHERE is_active = 1
    ''');
  }

  static Future<List<Map<String, dynamic>>> getAll(String dbName) async {
    if (kIsWeb) return [];
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

  static Future<Map<String, dynamic>?> get(String dbName, String key) async {
    if (kIsWeb) return null;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select('SELECT value FROM "$tableName" WHERE id = ?', [key]);
    if (results.isNotEmpty) {
      final value = jsonDecode(results.first['value'] as String);
      return {key: value is Map ? Map<String, dynamic>.from(value) : value};
    }
    return null;
  }

  static Future<String?> _extractBusinessKeyValue(String dbName, Map<String, dynamic> val, String fallbackId) async {
    final businessKeyName = await getBusinessUniqueKey(dbName);
    if (businessKeyName != null) {
      for (var entry in val.entries) {
        if (entry.key.toLowerCase() == businessKeyName.toLowerCase()) {
          return entry.value?.toString();
        }
      }
    }
    return fallbackId;
  }

  static Future<void> update(String dbName, String key, dynamic val) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final Map<String, dynamic> recordVal = val is Map ? Map<String, dynamic>.from(val) : {};
    final businessKeyVal = await _extractBusinessKeyValue(dbName, recordVal, key);
    
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
  }

  static Future<void> updateAll(String dbName, Map<String, dynamic> items) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    db.execute('BEGIN TRANSACTION');
    try {
      final stmt = db.prepare('INSERT OR REPLACE INTO "$tableName" (id, business_key_value, is_active, value) VALUES (?, ?, ?, ?)');
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        final Map<String, dynamic> recordVal = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : {};
        final businessKeyVal = await _extractBusinessKeyValue(dbName, recordVal, id);
        
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
      }
      stmt.dispose();
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  static Future<void> remove(String dbName, String key) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    db.execute('DELETE FROM "$tableName" WHERE id = ?', [key]);
  }

  static Future<void> clear(String dbName) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    db.execute('DROP TABLE IF EXISTS "$tableName"');
    await initTable(dbName);
  }

  static Future<Map<String, dynamic>?> getActiveByBusinessKey(String dbName, String businessKeyValue) async {
    if (kIsWeb) return null;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select(
      'SELECT id, value FROM "$tableName" WHERE business_key_value = ? AND is_active = 1 LIMIT 1',
      [businessKeyValue]
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
    final db = await _database;
    await initConfigurationsTable();
    final results = db.select('SELECT business_unique_key FROM "schema_configurations" WHERE schema_name = ?', [schemaName]);
    if (results.isNotEmpty) {
      return results.first['business_unique_key'] as String?;
    }
    return null;
  }

  static Future<void> setBusinessUniqueKey(String schemaName, String keyName) async {
    if (kIsWeb) return;
    final db = await _database;
    await initConfigurationsTable();
    db.execute(
      'INSERT OR REPLACE INTO "schema_configurations" (schema_name, business_unique_key) VALUES (?, ?)',
      [schemaName, keyName],
    );
  }
}
