import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class StorageInterface {
  String getType();
  Future<void> init(String dbName, Map<String, dynamic> config);
  Future<List<Map<String, dynamic>>> fetch();
  Future<void> add(String key, Map<String, dynamic> val);
  Future<void> remove(String key);
  Future<Map<String, dynamic>?> get(String key);
}

class LocalStore extends StorageInterface {
  late String _dbName;

  @override
  String getType() => 'local';

  @override
  Future<void> init(String dbName, Map<String, dynamic> config) async {
    _dbName = dbName;
  }

  @override
  Future<List<Map<String, dynamic>>> fetch() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('$_dbName:'));
    
    List<Map<String, dynamic>> results = [];
    for (var key in keys) {
      final val = prefs.getString(key);
      if (val != null) {
        final shortKey = key.replaceFirst('$_dbName:', '');
        results.add({shortKey: jsonDecode(val)});
      }
    }
    return results;
  }

  @override
  Future<void> add(String key, Map<String, dynamic> val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_dbName:$key', jsonEncode(val));
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_dbName:$key');
  }

  @override
  Future<Map<String, dynamic>?> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('$_dbName:$key');
    return val != null ? jsonDecode(val) : null;
  }
}

class StorageService {
  final List<StorageInterface> _storages = [];

  Future<void> init(String database, List<dynamic> config) async {
    _storages.clear();
    for (var entry in config) {
      StorageInterface? storage;
      if (entry['type'] == 'local') {
        storage = LocalStore();
      }
      // Add FileStore here later
      
      if (storage != null) {
        await storage.init(database, entry);
        _storages.add(storage);
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetch() async {
    if (_storages.isEmpty) return [];
    // Just like your code, default to the first storage for fetch
    return await _storages.first.fetch();
  }

  Future<void> add(String key, Map<String, dynamic> val) async {
    for (var s in _storages) {
      await s.add(key, val);
    }
  }

  Future<void> remove(String key) async {
    for (var s in _storages) {
      await s.remove(key);
    }
  }
}
