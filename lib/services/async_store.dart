import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'platform_check.dart';
import 'sqlite_helper.dart';

class AsyncStore {
  static final Map<String, String> _webCache = {};
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<List<Map<String, dynamic>>> getAll(String dbName) async {
    if (isLinux()) {
      return await SqliteHelper.getAll(dbName);
    }

    final prefs = await _getPrefs();
    final keys = prefs.getKeys().where((k) => k.startsWith('$dbName:'));
    
    // Combine persistent keys and web cache keys
    final allKeys = {...keys, ..._webCache.keys.where((k) => k.startsWith('$dbName:'))};
    
    List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (var key in allKeys) {
      final String? data = _webCache[key] ?? prefs.getString(key);
      if (data != null) {
        try {
          final decoded = jsonDecode(data);
          items.add({key: decoded is Map ? Map<String, dynamic>.from(decoded) : decoded});
        } catch (e) {
          debugPrint("AsyncStore.getAll error decoding $key: $e");
        }
      }
    }
    return items;
  }

  static Future<Map<String, dynamic>?> get(String key) async {
    if (isLinux()) {
      // Key format on Linux is expected to be 'dbName:recordKey' 
      // but SqliteHelper expects dbName and recordKey separately.
      final parts = key.split(':');
      if (parts.length >= 2) {
        return await SqliteHelper.get(parts[0], parts.sublist(1).join(':'));
      }
    }

    if (kIsWeb && _webCache.containsKey(key)) {
      final decoded = jsonDecode(_webCache[key]!);
      return <String, dynamic>{key: decoded is Map ? Map<String, dynamic>.from(decoded) : decoded};
    }
    
    final prefs = await _getPrefs();
    final data = prefs.getString(key);
    if (data != null) {
      if (kIsWeb) _webCache[key] = data;
      try {
        final decoded = jsonDecode(data);
        return <String, dynamic>{key: decoded is Map ? Map<String, dynamic>.from(decoded) : decoded};
      } catch (e) {
        debugPrint("AsyncStore.get error decoding $key: $e");
        return null;
      }
    }
    return null;
  }

  static Future<void> update(String key, dynamic val) async {
    if (isLinux()) {
      final parts = key.split(':');
      if (parts.length >= 2) {
        await SqliteHelper.update(parts[0], parts.sublist(1).join(':'), val);
        return;
      }
    }

    final jsonStr = jsonEncode(val);
    if (kIsWeb) _webCache[key] = jsonStr;

    final prefs = await _getPrefs();
    try {
      await prefs.setString(key, jsonStr);
    } catch (e) {
      if (e.toString().contains("QuotaExceededError")) {
        debugPrint("AsyncStore: Quota Exceeded.");
      } else {
        rethrow;
      }
    }
  }

  static Future<void> updateAll(String dbName, Map<String, dynamic> items) async {
    if (isLinux()) {
      await SqliteHelper.updateAll(dbName, items);
      return;
    }

    final prefs = await _getPrefs();
    
    int count = 0;
    for (var entry in items.entries) {
      final jsonStr = jsonEncode(entry.value);
      if (kIsWeb) _webCache[entry.key] = jsonStr;
      
      // Periodically await to keep the event loop responsive
      if (count % 100 == 0) {
        await prefs.setString(entry.key, jsonStr);
      } else {
        prefs.setString(entry.key, jsonStr);
      }
      count++;
    }
    
    if (items.isNotEmpty) {
       await prefs.setString(items.keys.last, jsonEncode(items.values.last));
    }
  }

  static Future<void> remove(String key) async {
    if (isLinux()) {
      final parts = key.split(':');
      if (parts.length >= 2) {
        await SqliteHelper.remove(parts[0], parts.sublist(1).join(':'));
        return;
      }
    }

    if (kIsWeb) _webCache.remove(key);
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  static Future<void> clear(String dbName) async {
    if (isLinux()) {
      await SqliteHelper.clear(dbName);
      return;
    }

    final prefs = await _getPrefs();
    final keys = prefs.getKeys().where((k) => k.startsWith('$dbName:'));
    for (var key in keys) {
      if (kIsWeb) _webCache.remove(key);
      prefs.remove(key);
    }
    if (keys.isNotEmpty) {
      await prefs.remove(keys.first);
    }
  }

  static Future<void> clearAll() async {
    if (isLinux()) {
      // clearAll for SQLite would mean dropping everything, 
      // but usually we just want to clear per-db.
      // For now, we leave it as per-db clear via clear(dbName).
    }
    final prefs = await _getPrefs();
    await prefs.clear();
    _webCache.clear();
  }
}
