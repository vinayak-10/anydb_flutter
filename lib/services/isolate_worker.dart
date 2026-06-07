import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'workbook_service.dart';
import 'schema_service.dart';
import 'sqlite_helper.dart'; // Direct warm database access
import 'file_service.dart';
import 'aggregator_service.dart';
import 'io_helper.dart' as io;
import 'package:intl/intl.dart';


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

      if (message['type'] == 'ipcGetAllRecords') {
        final SendPort replyPort = message['replyPort'];
        final Map<String, dynamic> params = message['params'] ?? {};
        final String dbName = params['dbName'] ?? "";
        
        final List<Map<String, String>> rawRecords = await SqliteHelper.getAllRawString(dbName);
        final list = rawRecords.map((rec) {
          final key = rec['id']!;
          final decoded = jsonDecode(rec['value']!);
          return {key: decoded is Map ? Map<String, dynamic>.from(decoded) : decoded};
        }).toList();
        
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

bool _recordMatchesQuery(Map<String, dynamic> record, String query, List<String> searchableFields, {bool exact = false}) {
  final bool filterBySearchable = searchableFields.isNotEmpty;
  
  for (var entry in record.entries) {
    final key = entry.key;
    if (key == '__meta__') continue; // Always ignore metadata
    
    final val = entry.value;
    final bool isSearchable = !filterBySearchable || searchableFields.contains(key);
    
    if (val is Map) {
      if (_recordMatchesQuery(Map<String, dynamic>.from(val), query, searchableFields, exact: exact)) return true;
    } else if (val is List) {
      for (var item in val) {
        if (item is Map) {
          if (_recordMatchesQuery(Map<String, dynamic>.from(item), query, searchableFields, exact: exact)) return true;
        } else if (isSearchable) {
          final itemStr = item?.toString().toLowerCase() ?? '';
          final matched = exact ? (itemStr == query) : itemStr.contains(query);
          if (matched) return true;
        }
      }
    } else if (isSearchable) {
      final valStr = val?.toString().toLowerCase() ?? '';
      final matched = exact ? (valStr == query) : valStr.contains(query);
      if (matched) return true;
    }
  }
  return false;
}
bool _recordMatchesFilter(Map<String, dynamic> record, String filter) {
  if (filter == 'All') return true;
  
  Map<dynamic, dynamic>? meta;
  if (record.containsKey('__meta__')) {
    meta = record['__meta__'] as Map?;
  } else if (record.values.isNotEmpty && record.values.first is Map) {
    final firstVal = record.values.first as Map;
    if (firstVal.containsKey('__meta__')) {
      meta = firstVal['__meta__'] as Map?;
    }
  }
  
  if (filter == 'Active') {
    if (meta == null) return true;
    final time = meta['time'] ?? {};
    return !time.containsKey('a') && !time.containsKey('d');
  }
  
  if (filter == 'Archived') {
    if (meta == null) return false;
    final time = meta['time'] ?? {};
    return time.containsKey('a');
  }
  
  if (filter == 'Deleted') {
    if (meta == null) return false;
    final time = meta['time'] ?? {};
    return time.containsKey('d');
  }
  
  return true;
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

    case 'dbUpdateSingle':
      final String dbName = params['dbName'];
      final String id = params['id'];
      final dynamic value = params['value'];
      final String? businessKeyName = params['businessKeyName'];
      
      // Perform database update
      await SqliteHelper.updateRaw(dbName, id, value, businessKeyName);
      
      // Update isolate memory cache
      final tableCache = bgCache[dbName] ??= {};
      tableCache[id] = jsonEncode(value);
      return null;

    case 'dbGetAll':
      final String dbName = params['dbName'];
      final String filter = params['filter']?.toString() ?? 'Active';
      final bool allRecords = params['allRecords'] == true;

      // 1. Ensure timestamps table is initialized and backfilled
      await SqliteHelper.backfillTimestamps(dbName);

      // 2. Fetch raw records matching filter (near-instant)
      List<Map<String, String>> rawRecords;
      if (filter == 'Active') {
        rawRecords = await SqliteHelper.getActiveRecordsRawString(dbName);
      } else if (filter == 'Archived' || filter == 'Deleted') {
        rawRecords = await SqliteHelper.getInactiveRecordsRawString(dbName);
      } else {
        rawRecords = await SqliteHelper.getAllRawString(dbName);
      }

      // 3. Populate background warm memory cache
      final Map<String, String> tableCache = bgCache[dbName] ??= {};
      if (filter == 'Active') {
        tableCache.clear();
      }
      for (var rec in rawRecords) {
        tableCache[rec['id']!] = rec['value']!;
      }
      if (filter == 'Archived' || filter == 'Deleted' || filter == 'All') {
        tableCache['__inactive_loaded__'] = 'true';
      }

      // 4. Determine boundary limit based on the filtered records
      final int totalCount = rawRecords.length;
      final int limit = allRecords ? totalCount : (totalCount * 0.30).round().clamp(100, totalCount);

      // 5. Query top recent IDs from timestamps table using status filter
      final List<String> recentIds = await SqliteHelper.getTopRecentIds(dbName, limit, filter: filter);

      // 6. Look up raw strings from cache map
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
      final bool exact = params['exact'] == true;
      final String filter = params['filter']?.toString() ?? 'Active';
      
      // Auto-populate cache with active records if not loaded yet
      var tableCache = bgCache[dbName];
      if (tableCache == null || tableCache.isEmpty) {
        final List<Map<String, String>> activeRecords = await SqliteHelper.getActiveRecordsRawString(dbName);
        tableCache = bgCache[dbName] = {};
        for (var rec in activeRecords) {
          tableCache[rec['id']!] = rec['value']!;
        }
      }
      
      // Lazy load inactive records when searching non-active views (Archived, Deleted, All)
      if (filter != 'Active') {
        final bool hasInactiveLoaded = tableCache['__inactive_loaded__'] == 'true';
        if (!hasInactiveLoaded) {
          final List<Map<String, String>> inactiveRecords = await SqliteHelper.getInactiveRecordsRawString(dbName);
          for (var rec in inactiveRecords) {
            tableCache[rec['id']!] = rec['value']!;
          }
          tableCache['__inactive_loaded__'] = 'true';
        }
      }
      
      final List<Map<String, dynamic>> matches = [];
      for (var entry in tableCache.entries) {
        final key = entry.key;
        if (key.startsWith('__')) continue; // Ignore cache metadata like __inactive_loaded__
        
        final valueStr = entry.value;
        final decoded = jsonDecode(valueStr);
        if (decoded is Map) {
          final decodedMap = Map<String, dynamic>.from(decoded);
          
          if (!_recordMatchesFilter(decodedMap, filter)) continue;
          
          if (_recordMatchesQuery(decodedMap, query, searchableFields, exact: exact)) {
            matches.add({key: decoded});
          }
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
    case 'runReportGenerationPipeline':
      final String dbName = params['dbName'];
      final String reportKey = params['reportKey'];
      final dynamic date = params['date'];
      final String targetPath = params['targetPath'];
      final Map<String, dynamic> aggregatorJson = params['aggregatorJson'];
      
      // A. Fetch raw database records from Database Isolate via IPC
      final ReceivePort replyPort = ReceivePort();
      dbSendPort!.send({
        'type': 'ipcGetAllRecords',
        'replyPort': replyPort.sendPort,
        'params': {'dbName': dbName},
      });
      final List<dynamic> rawElements = await replyPort.first;
      replyPort.close();
      
      final List<Map<String, dynamic>> elements = rawElements.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      
      // B. Initialize Aggregator Service and AggregatorReport in Isolate
      final agg = AggregatorService();
      agg.init(aggregatorJson);
      
      final report = agg.reports.firstWhere((r) => r.key == reportKey);
      
      // C. Populate Extractor Database with raw elements directly (decoding, flattening, filtering in Isolate)
      final DateTime targetDate = date is DateTime ? date : (date is String ? DateTime.tryParse(date) ?? DateTime.now() : DateTime.now());
      
      // Run the predicate calculations
      final extIntf = report.extractor[0];
      extIntf.populateWithData(elements);
      
      final s = await extIntf.extractor!.applyPredicate(
        extIntf.extractor!.predicates[0],
        data: targetDate,
        getFileName: (meta, {DateTime? timestamp}) => agg.getFileName(meta, timestamp: timestamp),
        timestamp: null,
        force: true,
      );
      
      // Inject final sheetName
      final String entryName = extIntf.predicatedName(extIntf.extractor!.predicates[0] ?? {}, targetDate.toIso8601String());
      final sheetName = FileService().sanitizeName(entryName);
      String finalSheetName = sheetName;
      if (report.key.toLowerCase().contains('monthly')) {
        finalSheetName = DateFormat('MMM_yyyy').format(targetDate);
      }
      s['extra'] ??= {};
      s['extra']['name'] = finalSheetName;
      
      // D. Generate report data rows and evaluate formulas
      final reportData = report.generateData(s);
      
      // E. Compile Excel Workbook and write to file
      final writeParams = {
        'existingBytes': null,
        'data': reportData,
        'sheetName': finalSheetName,
      };
      
      // Check if target file exists to load existingBytes (supporting sheets appending)
      List<int>? existingBytes;
      if (await io.fileExists(targetPath)) {
        existingBytes = await io.readBytes(targetPath);
        writeParams['existingBytes'] = existingBytes;
      }
      
      final List<int>? fileBytes = WorkbookService.writeExcelInIsolate(writeParams);
      if (fileBytes != null) {
        await io.writeBytes(targetPath, Uint8List.fromList(fileBytes));
      }
      
      return {
        'data': reportData,
        'path': targetPath,
      };
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


