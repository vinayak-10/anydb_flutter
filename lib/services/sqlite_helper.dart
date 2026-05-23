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
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<List<Map<String, dynamic>>> getAll(String dbName) async {
    if (kIsWeb) return [];
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select('SELECT key, value FROM "$tableName"');
    return results.map((row) {
      final key = row['key'] as String;
      final value = jsonDecode(row['value'] as String);
      return {key: value is Map ? Map<String, dynamic>.from(value) : value};
    }).toList();
  }

  static Future<Map<String, dynamic>?> get(String dbName, String key) async {
    if (kIsWeb) return null;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    final results = db.select('SELECT value FROM "$tableName" WHERE key = ?', [key]);
    if (results.isNotEmpty) {
      final value = jsonDecode(results.first['value'] as String);
      return {key: value is Map ? Map<String, dynamic>.from(value) : value};
    }
    return null;
  }

  static Future<void> update(String dbName, String key, dynamic val) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    db.execute(
      'INSERT OR REPLACE INTO "$tableName" (key, value) VALUES (?, ?)',
      [key, jsonEncode(val)],
    );
  }

  static Future<void> updateAll(String dbName, Map<String, dynamic> items) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    await initTable(dbName);

    // Use a transaction for high-performance batch updates
    db.execute('BEGIN TRANSACTION');
    try {
      final stmt = db.prepare('INSERT OR REPLACE INTO "$tableName" (key, value) VALUES (?, ?)');
      for (var entry in items.entries) {
        stmt.execute([entry.key.replaceFirst('$dbName:', ''), jsonEncode(entry.value)]);
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

    db.execute('DELETE FROM "$tableName" WHERE key = ?', [key]);
  }

  static Future<void> clear(String dbName) async {
    if (kIsWeb) return;
    final db = await _database;
    final tableName = _fileService.sanitizeName(dbName);
    db.execute('DROP TABLE IF EXISTS "$tableName"');
    await initTable(dbName);
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
