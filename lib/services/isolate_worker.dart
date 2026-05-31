import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'workbook_service.dart';
import 'schema_service.dart';
import 'sqlite_helper.dart'; // Direct warm database access
import 'file_service.dart';


class IsolateWorker {
  static final IsolateWorker _instance = IsolateWorker._internal();
  static IsolateWorker get instance => _instance;
  IsolateWorker._internal();

  Isolate? _dbIsolate;
  SendPort? _dbSendPort;
  final ReceivePort _dbReceivePort = ReceivePort();

  Isolate? _processIsolate;
  SendPort? _processSendPort;
  final ReceivePort _processReceivePort = ReceivePort();

  final Map<int, Completer<dynamic>> _pendingTasks = {};
  int _taskIdCounter = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    
    try {
      // 1. Establish the persistent Database & Schema Worker Isolate
      _dbIsolate = await Isolate.spawn(_dbWorkerEntryPoint, _dbReceivePort.sendPort);
      final Completer<SendPort> dbPortCompleter = Completer<SendPort>();
      
      _dbReceivePort.listen((message) {
        if (message is SendPort) {
          dbPortCompleter.complete(message);
        } else if (message is Map) {
          final int id = message['id'];
          final dynamic result = message['result'];
          final dynamic error = message['error'];
          
          final completer = _pendingTasks.remove(id);
          if (completer != null) {
            if (error != null) {
              completer.completeError(error);
            } else {
              completer.complete(result);
            }
          }
        }
      });
      _dbSendPort = await dbPortCompleter.future;

      // 2. Establish the persistent Report & Calculation Worker Isolate
      _processIsolate = await Isolate.spawn(_processWorkerEntryPoint, _processReceivePort.sendPort);
      final Completer<SendPort> processPortCompleter = Completer<SendPort>();
      
      _processReceivePort.listen((message) {
        if (message is SendPort) {
          processPortCompleter.complete(message);
        } else if (message is Map) {
          final int id = message['id'];
          final dynamic result = message['result'];
          final dynamic error = message['error'];
          
          final completer = _pendingTasks.remove(id);
          if (completer != null) {
            if (error != null) {
              completer.completeError(error);
            } else {
              completer.complete(result);
            }
          }
        }
      });
      _processSendPort = await processPortCompleter.future;

      // 3. Establish direct Inter-Isolate IPC connection
      _processSendPort!.send({
        'type': 'initIpc',
        'dbSendPort': _dbSendPort,
      });

      // 4. Resolve raw internal path on main thread and establish SQLite folder mapping
      final rootPath = await FileService().getInternalRoot();
      _dbSendPort!.send({
        'type': 'initPath',
        'path': rootPath,
      });

      _initialized = true;
      debugPrint("IsolateWorker: Dual persistent worker pool successfully established.");
    } catch (e) {
      debugPrint("IsolateWorker Init Error: $e");
      rethrow;
    }
  }

  Future<T> execute<T>(String taskType, Map<String, dynamic> params) async {
    if (kIsWeb) {
      return _executeTaskSync(taskType, params) as T;
    }
    
    await init();
    final int taskId = _taskIdCounter++;
    final completer = Completer<T>();
    _pendingTasks[taskId] = completer;

    // Route tasks dynamically based on task type categories
    final isDbTask = taskType.startsWith('db') || taskType == 'importMerge';
    final targetPort = isDbTask ? _dbSendPort! : _processSendPort!;

    targetPort.send({
      'id': taskId,
      'type': taskType,
      'params': params,
    });

    return completer.future;
  }

  void dispose() {
    _dbIsolate?.kill();
    _processIsolate?.kill();
    _dbReceivePort.close();
    _processReceivePort.close();
    _initialized = false;
  }
}

// ==========================================
// 1. Isolate 1: Database & Schema Worker Entrypoint
// ==========================================
void _dbWorkerEntryPoint(SendPort mainSendPort) {
  final ReceivePort workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  // Background warm record memory cache
  // Structure: { dbName: { recordId: StringValue } }
  final Map<String, Map<String, String>> bgCache = {};

  workerReceivePort.listen((message) async {
    if (message is Map) {
      // Warm SQLite path handshake check
      if (message['type'] == 'initPath') {
        SqliteHelper.databasePathOverride = message['path'] as String?;
        return;
      }

      // IPC channel check
      if (message['type'] == 'ipcGetBackup') {
        final SendPort replyPort = message['replyPort'];
        final Map<String, dynamic> params = message['params'] ?? {};
        final String dbName = params['dbName'] ?? "";
        final tableCache = bgCache[dbName] ?? {};
        
        final list = tableCache.entries.map((e) => {e.key: jsonDecode(e.value)}).toList();
        replyPort.send(list);
        return;
      }

      final int? id = message['id'];
      final String taskType = message['type'];
      final Map<String, dynamic> params = message['params'] ?? {};

      try {
        final result = await _executeDbTask(taskType, params, bgCache);
        if (id != null) {
          mainSendPort.send({
            'id': id,
            'result': result,
          });
        }
      } catch (e) {
        if (id != null) {
          mainSendPort.send({
            'id': id,
            'error': e.toString(),
          });
        }
      }
    }
  });
}

// ==========================================
// 2. Isolate 2: Report & Process Worker Entrypoint
// ==========================================
void _processWorkerEntryPoint(SendPort mainSendPort) {
  final ReceivePort workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  SendPort? dbSendPort;

  workerReceivePort.listen((message) async {
    if (message is Map) {
      // IPC Link initialization
      if (message['type'] == 'initIpc') {
        dbSendPort = message['dbSendPort'] as SendPort?;
        return;
      }

      final int? id = message['id'];
      final String taskType = message['type'];
      final Map<String, dynamic> params = message['params'] ?? {};

      try {
        final result = await _executeProcessTask(taskType, params, dbSendPort);
        if (id != null) {
          mainSendPort.send({
            'id': id,
            'result': result,
          });
        }
      } catch (e) {
        if (id != null) {
          mainSendPort.send({
            'id': id,
            'error': e.toString(),
          });
        }
      }
    }
  });
}

bool _recordMatchesQuery(Map<String, dynamic> record, String query, List<String> searchableFields) {
  final bool filterBySearchable = searchableFields.isNotEmpty;
  
  for (var entry in record.entries) {
    final key = entry.key;
    if (key == '__meta__') continue; // Always ignore metadata
    
    final val = entry.value;
    final bool isSearchable = !filterBySearchable || searchableFields.contains(key);
    
    if (val is Map) {
      if (_recordMatchesQuery(Map<String, dynamic>.from(val), query, searchableFields)) return true;
    } else if (val is List) {
      for (var item in val) {
        if (item is Map) {
          if (_recordMatchesQuery(Map<String, dynamic>.from(item), query, searchableFields)) return true;
        } else if (isSearchable && item?.toString().toLowerCase().contains(query) == true) {
          return true;
        }
      }
    } else if (isSearchable && val?.toString().toLowerCase().contains(query) == true) {
      return true;
    }
  }
  return false;
}

// ==========================================
// 3. Database Tasks execution logic
// ==========================================
Future<dynamic> _executeDbTask(String type, Map<String, dynamic> params, Map<String, Map<String, String>> bgCache) async {
  switch (type) {
    case 'dbGetBusinessUniqueKey':
      final String schemaName = params['schemaName'];
      return await SqliteHelper.getBusinessUniqueKeyRaw(schemaName);

    case 'dbSetBusinessUniqueKey':
      final String schemaName = params['schemaName'];
      final String keyName = params['keyName'];
      await SqliteHelper.setBusinessUniqueKeyRaw(schemaName, keyName);
      return null;

    case 'dbGetAll':
      final String dbName = params['dbName'];
      
      // 1. Ensure timestamps table is initialized and backfilled
      await SqliteHelper.backfillTimestamps(dbName);
      
      // 2. Fetch all raw string records from SQLite (near-instant)
      final List<Map<String, String>> rawRecords = await SqliteHelper.getAllRawString(dbName);
      
      // 3. Populate background warm memory cache
      final Map<String, String> tableCache = bgCache[dbName] ??= {};
      tableCache.clear();
      for (var rec in rawRecords) {
        tableCache[rec['id']!] = rec['value']!;
      }
      
      // 4. Determine 30% boundary limit
      final int totalCount = rawRecords.length;
      final int limit = (totalCount * 0.30).round().clamp(100, totalCount);
      
      // 5. Query top recent IDs from timestamps table
      final List<String> recentIds = await SqliteHelper.getTopRecentIds(dbName, limit);
      
      // 6. Look up raw strings from cache map (avoid SQL re-query and avoid jsonDecode sort loop)
      final List<Map<String, String>> results = [];
      for (var id in recentIds) {
        final val = tableCache[id];
        if (val != null) {
          results.add({'id': id, 'value': val});
        }
      }
      return results;

    case 'dbSearch':
      final String dbName = params['dbName'];
      final String query = params['query'].toString().toLowerCase();
      final List<String> searchableFields = List<String>.from(params['searchableFields'] ?? []);
      
      // Auto-populate cache in background isolate if not loaded yet
      var tableCache = bgCache[dbName];
      if (tableCache == null || tableCache.isEmpty) {
        final List<Map<String, String>> allRecords = await SqliteHelper.getAllRawString(dbName);
        tableCache = bgCache[dbName] = {};
        for (var rec in allRecords) {
          tableCache[rec['id']!] = rec['value']!;
        }
      }
      
      final List<Map<String, dynamic>> matches = [];
      for (var entry in tableCache.entries) {
        final key = entry.key;
        final valueStr = entry.value;
        final decoded = jsonDecode(valueStr);
        if (decoded is Map && _recordMatchesQuery(Map<String, dynamic>.from(decoded), query, searchableFields)) {
          matches.add({key: decoded});
        }
      }
      return matches;

    case 'dbUpdateAll':
      final String dbName = params['dbName'];
      final Map<String, dynamic> items = Map<String, dynamic>.from(params['items']);
      final String? businessKeyName = params['businessKeyName'];
      
      // Synchronous batch transaction on warm SQLite connection
      await SqliteHelper.updateAllRaw(dbName, items, businessKeyName);
      
      // Sync cache as raw strings
      final tableCache = bgCache[dbName] ??= {};
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        tableCache[id] = jsonEncode(entry.value);
      }
      return null;

    case 'dbImportData':
      final String dbName = params['dbName'];
      final List<dynamic> data = params['data'];

      // 1. Fetch current raw string records directly inside the isolate in micro-seconds (No IPC!)
      final List<Map<String, String>> rawRecords = await SqliteHelper.getAllRawString(dbName);
      
      // 2. Build the warm memory cache for fast O(1) matching
      final Map<String, Map<String, dynamic>> cache = {};
      for (var rec in rawRecords) {
        final key = rec['id']!;
        try {
          final decoded = jsonDecode(rec['value']!);
          if (decoded is Map) {
            cache[key] = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }

      // 3. Process the merge comparison in Isolate RAM
      final Map<String, dynamic> itemsToUpdate = {};
      int importedCount = 0;

      for (var item in data) {
        try {
          if (item is! Map) continue;
          final Map<String, dynamic> m = Map<String, dynamic>.from(item);
          if (m.isEmpty) continue;

          String? key;
          Map<String, dynamic>? val;

          if (m.length == 1 && m.values.first is Map) {
            key = m.keys.first;
            val = Map<String, dynamic>.from(m.values.first as Map);
          } else {
            key = m['Card Number']?.toString() ?? m['key']?.toString() ?? m['id']?.toString();
            val = m;
          }

          if (key == null) continue;

          if (cache.containsKey(key)) {
            final existingRecord = cache[key];
            if (existingRecord != null) {
              final existingDate = _getLatestDateStaticForImport(existingRecord);
              final incomingDate = _getLatestDateStaticForImport(val);
              if (incomingDate >= existingDate) {
                itemsToUpdate['$dbName:$key'] = val;
                importedCount++;
              }
            }
          } else {
            itemsToUpdate['$dbName:$key'] = val;
            importedCount++;
          }
        } catch (_) {}
      }

      // 4. Perform direct transactional batch write to SQLite inside the Database Isolate (zero IPC!)
      if (itemsToUpdate.isNotEmpty) {
        final businessKeyName = await SqliteHelper.getBusinessUniqueKeyRaw(dbName);
        await SqliteHelper.updateAllRaw(dbName, itemsToUpdate, businessKeyName);
        
        // 5. Update the background warm cache in place
        final tableCache = bgCache[dbName] ??= {};
        for (var entry in itemsToUpdate.entries) {
          final id = entry.key.replaceFirst('$dbName:', '');
          tableCache[id] = jsonEncode(entry.value);
        }
      }

      return importedCount;

    default:
      throw "Database Isolate: Unknown task type '$type'";
  }
}

// ==========================================
// 4. Processing / Heavy Compute Tasks logic
// ==========================================
Future<dynamic> _executeProcessTask(String type, Map<String, dynamic> params, SendPort? dbSendPort) async {
  switch (type) {
    case 'writeExcel':
      return WorkbookService.writeExcelInIsolate(params);
    case 'getMatchedSheets':
      return WorkbookService.getMatchedSheetsInIsolate(params);
    case 'readSheet':
      return WorkbookService.readSheetInIsolate(params);
    case 'parseSchema':
      return parseSchemaJsonInIsolate(params['jsonStr'] ?? "");
    case 'bgWriteJson':
      final String path = params['path'];
      final String fileName = params['fileName'];
      final dynamic content = params['content'];
      await FileService().writeJson(path, fileName, content);
      return null;
    default:
      throw "Process Isolate: Unknown task type '$type'";
  }
}

// ==========================================
// 5. Common Sync Dispatcher (Web Fallback)
// ==========================================
dynamic _executeTaskSync(String type, Map<String, dynamic> params) {
  switch (type) {
    case 'writeExcel':
      return WorkbookService.writeExcelInIsolate(params);
    case 'getMatchedSheets':
      return WorkbookService.getMatchedSheetsInIsolate(params);
    case 'readSheet':
      return WorkbookService.readSheetInIsolate(params);
    case 'parseSchema':
      return parseSchemaJsonInIsolate(params['jsonStr'] ?? "");
    case 'dbImportData':
      return 0;
    case 'bgWriteJson':
      final String path = params['path'];
      final String fileName = params['fileName'];
      final dynamic content = params['content'];
      FileService().writeJson(path, fileName, content);
      return null;
    default:
      throw "IsolateWorker: Unknown task type '$type'";
  }
}

int _getLatestDateStaticForImport(Map<String, dynamic> record) {
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
                dt = DateTime.tryParse(d)?.millisecondsSinceEpoch ?? int.tryParse(d) ?? 0;
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
  return maxDate;
}


