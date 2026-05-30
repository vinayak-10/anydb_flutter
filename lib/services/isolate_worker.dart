import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'workbook_service.dart';
import 'schema_service.dart';
import 'storage_service.dart';
import 'sqlite_helper.dart'; // Direct warm database access

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
  // Structure: { dbName: { recordId: MapValue } }
  final Map<String, Map<String, dynamic>> bgCache = {};

  workerReceivePort.listen((message) async {
    if (message is Map) {
      // IPC channel check
      if (message['type'] == 'ipcGetBackup') {
        final SendPort replyPort = message['replyPort'];
        final Map<String, dynamic> params = message['params'] ?? {};
        final String dbName = params['dbName'] ?? "";
        final tableCache = bgCache[dbName] ?? {};
        
        final list = tableCache.entries.map((e) => {e.key: e.value}).toList();
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

// ==========================================
// 3. Database Tasks execution logic
// ==========================================
Future<dynamic> _executeDbTask(String type, Map<String, dynamic> params, Map<String, Map<String, dynamic>> bgCache) async {
  switch (type) {
    case 'dbGetAll':
      final String dbName = params['dbName'];
      
      // Query warm SQLite connection directly
      final List<Map<String, dynamic>> allRecords = await SqliteHelper.getAllRaw(dbName);
      
      // Populate background warm memory cache
      final Map<String, dynamic> tableCache = bgCache[dbName] ??= {};
      tableCache.clear();
      for (var rec in allRecords) {
        if (rec.isNotEmpty) {
          tableCache[rec.keys.first] = rec.values.first;
        }
      }
      
      // Sort descending based on last transaction date
      final List<Map<String, dynamic>> sortedList = allRecords.toList();
      sortedList.sort((a, b) {
        final aVal = a.values.first as Map<String, dynamic>;
        final bVal = b.values.first as Map<String, dynamic>;
        return _getLatestDateStatic(bVal).compareTo(_getLatestDateStatic(aVal));
      });
      
      // Dynamically calculate dynamic 30% boundary limit
      final int totalCount = sortedList.length;
      final int limit = (totalCount * 0.30).round().clamp(100, totalCount);
      return sortedList.take(limit).toList();

    case 'dbSearch':
      final String dbName = params['dbName'];
      final String query = params['query'].toString().toLowerCase();
      final tableCache = bgCache[dbName] ?? {};
      
      final List<Map<String, dynamic>> matches = [];
      for (var entry in tableCache.entries) {
        final key = entry.key;
        final value = entry.value;
        final recordStr = jsonEncode(value).toLowerCase();
        if (recordStr.contains(query)) {
          matches.add({key: value});
        }
      }
      return matches;

    case 'dbUpdateAll':
      final String dbName = params['dbName'];
      final Map<String, dynamic> items = Map<String, dynamic>.from(params['items']);
      
      // Synchronous batch transaction on warm SQLite connection
      await SqliteHelper.updateAllRaw(dbName, items);
      
      // Sync cache
      final tableCache = bgCache[dbName] ??= {};
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        tableCache[id] = entry.value;
      }
      return null;

    case 'importMerge':
      // Offload import logic merges inside the database Isolate
      final result = processImportLogic(params);
      
      // Pre-update background cache for merged items to preserve immediate searchability
      final String dbName = params['dbName'];
      final Map<String, dynamic> itemsToUpdate = result['itemsToUpdate'];
      final tableCache = bgCache[dbName] ??= {};
      for (var entry in itemsToUpdate.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        tableCache[id] = entry.value;
      }
      return result;

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
    case 'importMerge':
      return processImportLogic(params);
    default:
      throw "IsolateWorker: Unknown task type '$type'";
  }
}

// ==========================================
// 6. Helper Recursive Date Extractor Heuristics
// ==========================================
int _getLatestDateStatic(Map<String, dynamic> record) {
  int maxDate = 0;
  
  void traverse(dynamic value) {
    if (value is Map) {
      for (var entry in value.entries) {
        final lowerKey = entry.key.toString().toLowerCase();
        if (lowerKey.contains('register') || lowerKey.contains('created') || lowerKey.contains('date')) {
          final val = entry.value;
          if (val is int) {
            if (val > maxDate) maxDate = val;
          } else if (val is String) {
            final parsed = int.tryParse(val);
            if (parsed != null) {
              if (parsed > maxDate) maxDate = parsed;
            } else {
              final parsedDate = DateTime.tryParse(val);
              if (parsedDate != null && parsedDate.millisecondsSinceEpoch > maxDate) {
                maxDate = parsedDate.millisecondsSinceEpoch;
              }
            }
          }
        }
        traverse(entry.value);
      }
    } else if (value is List) {
      for (var item in value) {
        traverse(item);
      }
    }
  }

  traverse(record);
  return maxDate;
}
