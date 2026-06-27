import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'async_store.dart';
import 'file_service.dart';
import 'isolate_worker.dart';
import 'package:path/path.dart' as p;

abstract class StorageInterface {
  String getType();
  Future<void> init(String dbName, Map<String, dynamic> config);
  Future<List<Map<String, dynamic>>> fetch({
    String filter = 'Active',
    bool allRecords = false,
  });
  Future<void> add(String key, Map<String, dynamic> val);
  Future<void> remove(String key);
  Future<Map<String, dynamic>?> get(String key);
  Future<void> clear();
  Future<void> importData(List<dynamic> data);
  Future<List<dynamic>> exportData();
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
  Future<List<Map<String, dynamic>>> fetch({
    String filter = 'Active',
    bool allRecords = false,
  }) async {
    final results = await AsyncStore.getAll(
      _dbName,
      filter: filter,
      allRecords: allRecords,
    );
    return results.map((e) {
      final key = e.keys.first.replaceFirst('$_dbName:', '');
      return <String, dynamic>{key: e.values.first};
    }).toList();
  }

  @override
  Future<void> add(String key, Map<String, dynamic> val) async {
    await AsyncStore.update('$_dbName:$key', val);
  }

  @override
  Future<void> remove(String key) async {
    await AsyncStore.remove('$_dbName:$key');
  }

  @override
  Future<Map<String, dynamic>?> get(String key) async {
    final result = await AsyncStore.get('$_dbName:$key');
    if (result != null) {
      return {key: result.values.first};
    }
    return null;
  }

  @override
  Future<void> clear() async {
    await AsyncStore.clear(_dbName);
  }

  @override
  Future<void> importData(List<dynamic> data) async {
    if (kIsWeb) {
      final currentEntries = await fetch();
      final result = processImportLogic({
        'dbName': _dbName,
        'data': data,
        'currentEntries': currentEntries,
      });
      final Map<String, dynamic> itemsToUpdate = result['itemsToUpdate'];
      final int importedCount = result['importedCount'];
      if (itemsToUpdate.isNotEmpty) {
        await AsyncStore.updateAll(_dbName, itemsToUpdate);
      }
      debugPrint("LocalStore (Web): Imported $importedCount records.");
      return;
    }

    // Native: Offload the entire fetch-merge-write sequence directly to the persistent background Database Isolate (Zero IPC round-trips!)
    final int importedCount = await IsolateWorker.instance.execute<int>(
      'dbImportData',
      {'dbName': _dbName, 'data': data},
    );
    debugPrint(
      "LocalStore (Native): Imported $importedCount records (Total input: ${data.length}).",
    );
  }

  @override
  Future<List<dynamic>> exportData() async {
    return await fetch(filter: 'All', allRecords: true);
  }
}

// Top-level function for compute/IsolateWorker
Map<String, dynamic> processImportLogic(Map<String, dynamic> params) {
  final String dbName = params['dbName'];
  final List<dynamic> data = params['data'];
  final List<Map<String, dynamic>> currentEntries = params['currentEntries'];

  final Map<String, Map<String, dynamic>> cache = {};
  for (var e in currentEntries) {
    if (e.isNotEmpty && e.values.first is Map) {
      cache[e.keys.first] = Map<String, dynamic>.from(e.values.first as Map);
    }
  }

  final Map<String, dynamic> itemsToUpdate = {};
  int importedCount = 0;

  for (var item in data) {
    try {
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item as Map);
      if (m.isEmpty) continue;

      String? key;
      Map<String, dynamic>? val;

      if (m.length == 1 && m.values.first is Map) {
        key = m.keys.first;
        val = Map<String, dynamic>.from(m.values.first as Map);
      } else {
        key =
            m['Card Number']?.toString() ??
            m['key']?.toString() ??
            m['id']?.toString();
        val = m;
      }

      if (key == null) continue;

      if (cache.containsKey(key)) {
        final existingRecord = cache[key];
        if (existingRecord != null) {
          final existingDate = _getLatestDateStatic(existingRecord);
          final incomingDate = _getLatestDateStatic(val);
          if (incomingDate >= existingDate) {
            itemsToUpdate['$dbName:$key'] = val;
            importedCount++;
          }
        }
      } else {
        itemsToUpdate['$dbName:$key'] = val;
        importedCount++;
      }
    } catch (e) {
      // Silently continue in isolate
    }
  }
  return {'itemsToUpdate': itemsToUpdate, 'importedCount': importedCount};
}

int _getLatestDateStatic(Map<String, dynamic> record) {
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
  } catch (e) {
    // ignore
  }
  // Fallback: if no domain timestamp resolved, return the current wall-clock time
  // so this record is never silently ignored during import deduplication.
  return maxDate > 0 ? maxDate : DateTime.now().millisecondsSinceEpoch;
}

class FileStore extends StorageInterface {
  late String _dbName;
  late String _dbPath;
  final FileService _fileService = FileService();

  @override
  String getType() => 'file';

  @override
  Future<void> init(String dbName, Map<String, dynamic> config) async {
    _dbName = dbName;
    if (!kIsWeb) {
      final externalRoot = await _fileService.getExternalRoot();
      _dbPath = p.join(
        externalRoot,
        'database',
        _fileService.sanitizeName(dbName),
      );
    } else {
      _dbPath = "web_dummy_path";
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetch({
    String filter = 'Active',
    bool allRecords = false,
  }) async {
    if (kIsWeb) return [];
    final filePath = p.join(_dbPath, '$_dbName.json');
    final data = await _fileService.readJson(filePath);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  @override
  Future<void> add(String key, Map<String, dynamic> val) async {
    if (kIsWeb) return;
    final currentData = await fetch();
    bool found = false;
    for (int i = 0; i < currentData.length; i++) {
      if (currentData[i].keys.first == key) {
        currentData[i] = {key: val};
        found = true;
        break;
      }
    }
    if (!found) {
      currentData.add({key: val});
    }
    await _fileService.writeJson(_dbPath, '$_dbName.json', currentData);
  }

  @override
  Future<void> remove(String key) async {
    if (kIsWeb) return;
    final currentData = await fetch();
    currentData.removeWhere((e) => e.keys.first == key);
    await _fileService.writeJson(_dbPath, '$_dbName.json', currentData);
  }

  @override
  Future<Map<String, dynamic>?> get(String key) async {
    if (kIsWeb) return null;
    final currentData = await fetch();
    try {
      return currentData.firstWhere((e) => e.keys.first == key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    if (kIsWeb) return;
    await _fileService.writeJson(_dbPath, '$_dbName.json', []);
  }

  @override
  Future<void> importData(List<dynamic> data) async {
    if (kIsWeb) return;
    // Asynchronously offload serialization and disk write to the background Process Isolate
    IsolateWorker.instance
        .execute('bgWriteJson', {
          'path': _dbPath,
          'fileName': '$_dbName.json',
          'content': data,
        })
        .catchError((e) {
          debugPrint(
            "FileStore: Background JSON write failed in Process Isolate: $e",
          );
        });
  }

  @override
  Future<List<dynamic>> exportData() async {
    return await fetch();
  }
}

class RestApiStore extends StorageInterface {
  late String _url;
  late String _method;

  @override
  String getType() => 'rest-api';

  @override
  Future<void> init(String dbName, Map<String, dynamic> config) async {
    _url = config['url'] ?? '';
    _method = config['method'] ?? 'POST';
  }

  @override
  Future<List<Map<String, dynamic>>> fetch({
    String filter = 'Active',
    bool allRecords = false,
  }) async => [];

  @override
  Future<void> add(String key, Map<String, dynamic> val) async {
    if (_url.isEmpty) return;
    try {
      if (_method == 'POST') {
        await http.post(
          Uri.parse(_url),
          body: jsonEncode({key: val}),
          headers: {"Content-Type": "application/json"},
        );
      }
    } catch (e) {
      debugPrint("RestApiStore: Sync failed: $e");
    }
  }

  @override
  Future<void> remove(String key) async {}
  @override
  Future<Map<String, dynamic>?> get(String key) async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> importData(List<dynamic> data) async {}
  @override
  Future<List<dynamic>> exportData() async => [];
}

class StorageFactory {
  static StorageInterface? get(String type) {
    switch (type) {
      case 'local':
        return LocalStore();
      case 'file':
        return FileStore();
      default:
        return null;
    }
  }
}

class StorageService {
  final List<StorageInterface> _storages = [];

  Future<void> init(String database, List<dynamic> config) async {
    _storages.clear();
    for (var entry in config) {
      StorageInterface? storage = StorageFactory.get(entry['type'] ?? '');
      if (storage != null) {
        await storage.init(database, entry);
        _storages.add(storage);
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetch({
    String filter = 'Active',
    bool allRecords = false,
  }) async {
    if (_storages.isEmpty) return [];
    for (var s in _storages) {
      final results = await s.fetch(filter: filter, allRecords: allRecords);
      if (results.isNotEmpty) return results;
    }
    return [];
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

  Future<void> clear() async {
    for (var s in _storages) {
      await s.clear();
    }
  }

  Future<void> importData(List<dynamic> data) async {
    if (_storages.isNotEmpty) {
      for (var s in _storages) {
        await s.importData(data);
      }
    }
  }

  Future<List<dynamic>> exportData() async {
    if (_storages.isNotEmpty) {
      return await _storages.first.exportData();
    }
    return [];
  }
}
