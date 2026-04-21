import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AsyncStore {
  static final Map<String, String> _webCache = {};

  static Future<List<Map<String, dynamic>>> getAll(String dbName) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('$dbName:'));
    
    // Merge keys from preferences and web cache
    final allKeys = {...keys, ..._webCache.keys.where((k) => k.startsWith('$dbName:'))};
    
    List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (var key in allKeys) {
      try {
        final data = await get(key);
        if (data != null) {
          items.add(data);
        }
      } catch (e) {
        debugPrint("AsyncStore.getAll error for key $key: $e");
      }
    }
    return items;
  }

  static Future<Map<String, dynamic>?> get(String key) async {
    if (kIsWeb && _webCache.containsKey(key)) {
      final decoded = jsonDecode(_webCache[key]!);
      return <String, dynamic>{key: decoded is Map ? decoded.cast<String, dynamic>() : decoded};
    }
    
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(key);
    if (data != null) {
      if (kIsWeb) _webCache[key] = data; // Populate cache
      try {
        final decoded = jsonDecode(data);
        final Map<String, dynamic> record = decoded is Map ? decoded.cast<String, dynamic>() : decoded;
        return <String, dynamic>{key: record};
      } catch (e) {
        debugPrint("AsyncStore.get error decoding $key: $e");
        return null;
      }
    }
    return null;
  }

  static Future<void> update(String key, dynamic val) async {
    final jsonStr = jsonEncode(val);
    if (kIsWeb) {
      _webCache[key] = jsonStr;
    }

    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString(key, jsonStr);
    } catch (e) {
      if (e.toString().contains("QuotaExceededError") || e.toString().contains("NS_ERROR_DOM_QUOTA_REACHED")) {
        debugPrint("AsyncStore: Quota Exceeded on Web. Data persisted in memory only for this session.");
      } else {
        rethrow;
      }
    }
  }

  static Future<void> remove(String key) async {
    if (kIsWeb) _webCache.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> clear(String dbName) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('$dbName:'));
    for (var key in keys) {
      await prefs.remove(key);
    }
    if (kIsWeb) {
      _webCache.removeWhere((key, _) => key.startsWith('$dbName:'));
    }
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (kIsWeb) _webCache.clear();
  }
}
