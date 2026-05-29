import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'file_service.dart';

class SqliteHelper {
  static final FileService _fileService = FileService();

  static Future<void> initTable(String dbName) async {
    return;
  }

  static Future<List<Map<String, dynamic>>> getAll(String dbName) async {
    return [];
  }

  static Future<Map<String, dynamic>?> get(String dbName, String key) async {
    return null;
  }

  static Future<void> update(String dbName, String key, dynamic val) async {
    return;
  }

  static Future<void> updateAll(String dbName, Map<String, dynamic> items) async {
    return;
  }

  static Future<void> remove(String dbName, String key) async {
    return;
  }

  static Future<void> clear(String dbName) async {
    return;
  }

  static Future<Map<String, dynamic>?> getActiveByBusinessKey(String dbName, String businessKeyValue) async {
    return null;
  }

  static Future<void> initConfigurationsTable() async {
    return;
  }

  static Future<String?> getBusinessUniqueKey(String schemaName) async {
    return null;
  }

  static Future<void> setBusinessUniqueKey(String schemaName, String keyName) async {
    return;
  }
}
