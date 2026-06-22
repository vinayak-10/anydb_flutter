import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'schema_service.dart';
import 'sqlite_helper.dart'; // Direct warm database access
import 'file_service.dart';
import 'path_manager.dart';
import 'aggregator_service.dart';
import 'io_helper.dart' as io;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../core/cell_helper.dart';
import 'package:excel/excel.dart';
import 'excel_generation_service.dart';
import 'excel_binary_helper.dart';
import 'report_formula_service.dart';

class IsolateWorker {
  static final IsolateWorker _instance = IsolateWorker._internal();
  static IsolateWorker get instance => _instance;
  IsolateWorker._internal();

  static List<int>? writeExcelInIsolate(Map<String, dynamic> params) {
    final List<int>? existingBytes = params['existingBytes'];
    final Map<String, dynamic> data = params['data'];
    final String sheetName = params['sheetName'];
    final String targetPath = params['targetPath'] ?? "";

    Excel excel;
    if (existingBytes != null && existingBytes.isNotEmpty) {
      excel = Excel.decodeBytes(existingBytes);
    } else if (ExcelGenerationService.cachedExcel != null &&
        ExcelGenerationService.cachedExcelPath == targetPath &&
        targetPath.isNotEmpty) {
      excel = ExcelGenerationService.cachedExcel!;
    } else {
      excel = Excel.createExcel();
    }

    final Sheet ws = excel[sheetName];

    // 1. Calculate formulas & cache registries using the Formula Module
    final calcResult = ReportFormulaService.calculateSummaryFormulas(
      jo: data,
      sheetName: sheetName,
      summaryValRow: 6,
      dataStartRow: 8,
    );

    // 2. Structure sheet and populate cells using the Excel Module
    final Map<String, String> formulaRegistry = {};
    ExcelGenerationService.populateSheet(
      ws: ws,
      jo: data,
      sheetName: sheetName,
      calcResult: calcResult,
      formulaRegistry: formulaRegistry,
    );

    // 3. Clear placeholder Sheets
    final List<String> sheetsToDelete = [];
    for (var sn in excel.sheets.keys) {
      if (sn != sheetName && (sn == 'Sheet1' || sn == 'Sheet 1')) {
        sheetsToDelete.add(sn);
      }
    }
    if (sheetsToDelete.isNotEmpty &&
        excel.sheets.length > sheetsToDelete.length) {
      for (var sn in sheetsToDelete) {
        excel.delete(sn);
      }
    }

    final savedBytes = excel.save();
    if (savedBytes != null) {
      // 4. Inject static pre-calculated results & sort sheets using Binary Module
      final processed = ExcelBinaryHelper.postProcessBytes(savedBytes, formulaRegistry);
      if (targetPath.isNotEmpty) {
        ExcelGenerationService.cachedExcel = Excel.decodeBytes(processed);
        ExcelGenerationService.cachedExcelPath = targetPath;
      }
      return processed;
    }
    return savedBytes;
  }

  Isolate? _dbIsolate;
  SendPort? _dbSendPort;
  final ReceivePort _dbReceivePort = ReceivePort();

  Isolate? _processIsolate;
  SendPort? _processSendPort;
  final ReceivePort _processReceivePort = ReceivePort();

  final Map<int, Completer<dynamic>> _pendingTasks = {};
  int _taskIdCounter = 0;
  bool _initialized = false;
  static bool isInsideWorkerIsolate = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    try {
      // 1. Establish the persistent Database & Schema Worker Isolate
      _dbIsolate = await Isolate.spawn(
        _dbWorkerEntryPoint,
        _dbReceivePort.sendPort,
      );
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
      _processIsolate = await Isolate.spawn(
        _processWorkerEntryPoint,
        _processReceivePort.sendPort,
      );
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
      _processSendPort!.send({'type': 'initIpc', 'dbSendPort': _dbSendPort});

      // 4. Resolve raw internal and external paths on main thread and establish SQLite folder mapping
      if (!PathManager.isInitialized) await PathManager.init();
      final initPathsMsg = <String, dynamic>{
        'type': 'initPaths',
        ...PathManager.toIsolateMessage(),
      };

      _dbSendPort!.send(initPathsMsg);
      _processSendPort!.send(initPathsMsg);

      _initialized = true;
      debugPrint(
        "IsolateWorker: Dual persistent worker pool successfully established.",
      );
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

    targetPort.send({'id': taskId, 'type': taskType, 'params': params});

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
  IsolateWorker.isInsideWorkerIsolate = true;
  final ReceivePort workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  // Background warm record memory cache (Pre-decoded Map format to optimize RAM usage & CPU time)
  // Structure: { dbName: { recordId: DecodedValue } }
  final Map<String, Map<String, dynamic>> bgCache = {};

  workerReceivePort.listen((message) async {
    if (message is Map) {
      // Warm SQLite path handshake check
      if (message['type'] == 'initPaths') {
        final internalRoot = message['internalRoot'] as String?;
        final externalRoot = message['externalRoot'] as String?;
        FileService.internalRootOverride = internalRoot;
        FileService.externalRootOverride = externalRoot;
        SqliteHelper.databasePathOverride = internalRoot;
        return;
      }
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

        final list = tableCache.entries
            .where((e) => !e.key.startsWith('__'))
            .map((e) => {e.key: e.value})
            .toList();
        replyPort.send(list);
        return;
      }

      if (message['type'] == 'ipcGetLatestTimestamp') {
        final SendPort replyPort = message['replyPort'];
        final Map<String, dynamic> params = message['params'] ?? {};
        final String dbName = params['dbName'] ?? "";
        final int ts = await SqliteHelper.getLatestTimestamp(dbName);
        replyPort.send(ts);
        return;
      }

      if (message['type'] == 'ipcGetAllRecords') {
        final SendPort replyPort = message['replyPort'];
        final Map<String, dynamic> params = message['params'] ?? {};
        final String dbName = params['dbName'] ?? "";

        var tableCache = bgCache[dbName];
        final bool hasInactiveLoaded =
            tableCache != null && tableCache['__inactive_loaded__'] == 'true';

        if (tableCache == null || !hasInactiveLoaded) {
          final List<Map<String, String>> rawRecords =
              await SqliteHelper.getAllRawString(dbName);
          tableCache = bgCache[dbName] = {};
          for (var rec in rawRecords) {
            tableCache[rec['id']!] = jsonDecode(rec['value']!);
          }
          tableCache['__inactive_loaded__'] = 'true';
        }

        final list = tableCache.entries
            .where((e) => !e.key.startsWith('__'))
            .map((e) => {e.key: e.value})
            .toList();

        replyPort.send(list);
        return;
      }

      if (message['type'] == 'ipcGetFilteredReportData') {
        final SendPort replyPort = message['replyPort'];
        final Map<String, dynamic> params = message['params'] ?? {};
        final String dbName = params['dbName'] ?? "";
        final String reportKey = params['reportKey'] ?? "";
        final dynamic date = params['date'];
        final Map<String, dynamic> aggregatorJson =
            params['aggregatorJson'] ?? {};

        // 1. Ensure cache is fully warmed
        var tableCache = bgCache[dbName];
        final bool hasInactiveLoaded =
            tableCache != null && tableCache['__inactive_loaded__'] == 'true';

        if (tableCache == null || !hasInactiveLoaded) {
          final List<Map<String, String>> rawRecords =
              await SqliteHelper.getAllRawString(dbName);
          tableCache = bgCache[dbName] = {};
          for (var rec in rawRecords) {
            tableCache[rec['id']!] = jsonDecode(rec['value']!);
          }
          tableCache['__inactive_loaded__'] = 'true';
        }

        // 2. Prepare elements from pre-decoded cache wrapped in {key: value} format
        final elements = tableCache.entries
            .where((e) => !e.key.startsWith('__'))
            .map((e) => {e.key: Map<String, dynamic>.from(e.value as Map)})
            .toList();

        // 3. Initialize aggregator service and run daily filtering logic inside database isolate
        final agg = AggregatorService();
        agg.init(aggregatorJson);
        final report = agg.reports.firstWhere((r) => r.key == reportKey);
        final DateTime targetDate = date is DateTime
            ? date
            : (date is String
                  ? DateTime.tryParse(date) ?? DateTime.now()
                  : DateTime.now());

        final extIntf = report.extractor[0];

        // 4. Pre-filter elements using the date predicate before running the flattening/extraction engine.
        // This avoids running recursive flattening on thousands of unrelated records.
        final predicate = extIntf.extractor?.predicates.firstWhere(
          (p) => p is Map && p['operation'] == 'date',
          orElse: () => null,
        );

        List<Map<String, dynamic>> filteredElements;
        if (predicate != null && predicate is Map) {
          final String searchKey = predicate['column']?.toString() ?? "Date";
          final String matchType =
              predicate['parameter']?['type']?.toString() ?? "day";
          filteredElements = elements.where((e) {
            if (e.isEmpty) return false;
            final recordVal = e.values.first;
            return _recordMatchesDatePredicate(
              recordVal,
              targetDate,
              searchKey,
              matchType,
            );
          }).toList();
          debugPrint(
            "Isolate DB Worker: Pre-filtered elements from ${elements.length} down to ${filteredElements.length} using key='$searchKey', matchType='$matchType', date='$targetDate'.",
          );
        } else {
          filteredElements = elements;
        }

        await extIntf.populateWithData(filteredElements);

        final s = await extIntf.extractor!.applyPredicate(
          extIntf.extractor!.predicates[0],
          data: targetDate,
          getFileName: (meta, {DateTime? timestamp}) =>
              agg.getFileName(meta, timestamp: timestamp),
          timestamp: null,
          force: true,
        );

        replyPort.send(s);
        return;
      }

      final int? id = message['id'];
      final String taskType = message['type'];
      final Map<String, dynamic> params = message['params'] ?? {};

      try {
        final result = await _executeDbTask(taskType, params, bgCache);
        if (id != null) {
          mainSendPort.send({'id': id, 'result': result});
        }
      } catch (e) {
        if (id != null) {
          mainSendPort.send({'id': id, 'error': e.toString()});
        }
      }
    }
  });
}

// ==========================================
// 2. Isolate 2: Report & Process Worker Entrypoint
// ==========================================
void _processWorkerEntryPoint(SendPort mainSendPort) {
  IsolateWorker.isInsideWorkerIsolate = true;
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

      if (message['type'] == 'initPaths') {
        final internalRoot = message['internalRoot'] as String?;
        final externalRoot = message['externalRoot'] as String?;
        FileService.internalRootOverride = internalRoot;
        FileService.externalRootOverride = externalRoot;
        return;
      }

      final int? id = message['id'];
      final String taskType = message['type'];
      final Map<String, dynamic> params = message['params'] ?? {};

      try {
        final result = await _executeProcessTask(taskType, params, dbSendPort);
        if (id != null) {
          mainSendPort.send({'id': id, 'result': result});
        }
      } catch (e) {
        if (id != null) {
          mainSendPort.send({'id': id, 'error': e.toString()});
        }
      }
    }
  });
}

bool _recordMatchesQuery(
  Map<String, dynamic> record,
  String query,
  List<String> searchableFields, {
  bool exact = false,
}) {
  final bool filterBySearchable = searchableFields.isNotEmpty;

  for (var entry in record.entries) {
    final key = entry.key;
    if (key == '__meta__') continue; // Always ignore metadata

    final val = entry.value;
    final bool isSearchable =
        !filterBySearchable || searchableFields.contains(key);

    if (val is Map) {
      if (_recordMatchesQuery(
        Map<String, dynamic>.from(val),
        query,
        searchableFields,
        exact: exact,
      ))
        return true;
    } else if (val is List) {
      for (var item in val) {
        if (item is Map) {
          if (_recordMatchesQuery(
            Map<String, dynamic>.from(item),
            query,
            searchableFields,
            exact: exact,
          ))
            return true;
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
Future<dynamic> _executeDbTask(
  String type,
  Map<String, dynamic> params,
  Map<String, Map<String, dynamic>> bgCache,
) async {
  switch (type) {
    case 'dbClearCache':
      final String dbName = params['dbName'];
      bgCache.remove(dbName);
      return null;

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
      tableCache[id] = value;
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
      final Map<String, dynamic> tableCache = bgCache[dbName] ??= {};
      if (filter == 'Active') {
        tableCache.clear();
      }
      for (var rec in rawRecords) {
        tableCache[rec['id']!] = jsonDecode(rec['value']!);
      }
      if (filter == 'Archived' || filter == 'Deleted' || filter == 'All') {
        tableCache['__inactive_loaded__'] = 'true';
      }

      // 4. Determine boundary limit based on the filtered records
      final int totalCount = rawRecords.length;
      final int limit = allRecords
          ? totalCount
          : (totalCount * 0.30).round().clamp(100, totalCount);

      // 5. Query top recent IDs from timestamps table using status filter
      final List<String> recentIds = await SqliteHelper.getTopRecentIds(
        dbName,
        limit,
        filter: filter,
      );

      // 6. Look up raw strings from cache map
      final List<Map<String, String>> results = [];
      for (var id in recentIds) {
        final val = tableCache[id];
        if (val != null) {
          results.add({'id': id, 'value': jsonEncode(val)});
        }
      }
      return results;

    case 'dbSearch':
      final String dbName = params['dbName'];
      final String query = params['query'].toString().toLowerCase();
      final List<String> searchableFields = List<String>.from(
        params['searchableFields'] ?? [],
      );
      final bool exact = params['exact'] == true;
      final String filter = params['filter']?.toString() ?? 'Active';

      // Auto-populate cache with active records if not loaded yet
      var tableCache = bgCache[dbName];
      if (tableCache == null || tableCache.isEmpty) {
        final List<Map<String, String>> activeRecords =
            await SqliteHelper.getActiveRecordsRawString(dbName);
        tableCache = bgCache[dbName] = {};
        for (var rec in activeRecords) {
          tableCache[rec['id']!] = jsonDecode(rec['value']!);
        }
      }

      // Lazy load inactive records when searching non-active views (Archived, Deleted, All)
      if (filter != 'Active') {
        final bool hasInactiveLoaded =
            tableCache['__inactive_loaded__'] == 'true';
        if (!hasInactiveLoaded) {
          final List<Map<String, String>> inactiveRecords =
              await SqliteHelper.getInactiveRecordsRawString(dbName);
          for (var rec in inactiveRecords) {
            tableCache[rec['id']!] = jsonDecode(rec['value']!);
          }
          tableCache['__inactive_loaded__'] = 'true';
        }
      }

      final List<Map<String, dynamic>> matches = [];
      for (var entry in tableCache.entries) {
        final key = entry.key;
        if (key.startsWith('__'))
          continue; // Ignore cache metadata like __inactive_loaded__

        final decoded = entry.value;
        if (decoded is Map) {
          final decodedMap = Map<String, dynamic>.from(decoded);

          if (!_recordMatchesFilter(decodedMap, filter)) continue;

          if (_recordMatchesQuery(
            decodedMap,
            query,
            searchableFields,
            exact: exact,
          )) {
            matches.add({key: decoded});
          }
        }
      }
      return matches;

    case 'dbUpdateAll':
      final String dbName = params['dbName'];
      final Map<String, dynamic> items = Map<String, dynamic>.from(
        params['items'],
      );
      final String? businessKeyName = params['businessKeyName'];

      // Synchronous batch transaction on warm SQLite connection
      await SqliteHelper.updateAllRaw(dbName, items, businessKeyName);

      // Sync cache as decoded maps
      final tableCache = bgCache[dbName] ??= {};
      for (var entry in items.entries) {
        final id = entry.key.replaceFirst('$dbName:', '');
        tableCache[id] = entry.value;
      }
      return null;

    case 'dbImportData':
      final String dbName = params['dbName'];
      final List<dynamic> data = params['data'];

      // 1. Fetch current raw string records directly inside the isolate in micro-seconds (No IPC!)
      final List<Map<String, String>> rawRecords =
          await SqliteHelper.getAllRawString(dbName);

      // 2. Build the warm memory cache for fast O(1) matching
      final Map<String, Map<String, dynamic>> cache = {};
      for (var rec in rawRecords) {
        final key = rec['id']!;
        try {
          final decoded = jsonDecode(rec['value']!);
          if (decoded is Map) {
            cache[key] = Map<String, dynamic>.from(decoded);
          }
        } catch (e) {
          debugPrint('IsolateWorker[DB]: Record decode failed: $e');
        }
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
              final existingDate = _getLatestDateStaticForImport(
                existingRecord,
              );
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
        } catch (e) {
          debugPrint('IsolateWorker[DB]: Import item processing error: $e');
        }
      }

      // 4. Perform direct transactional batch write to SQLite inside the Database Isolate (zero IPC!)
      if (itemsToUpdate.isNotEmpty) {
        final businessKeyName = await SqliteHelper.getBusinessUniqueKeyRaw(
          dbName,
        );
        await SqliteHelper.updateAllRaw(dbName, itemsToUpdate, businessKeyName);

        // 5. Update the background warm cache in place
        final tableCache = bgCache[dbName] ??= {};
        for (var entry in itemsToUpdate.entries) {
          final id = entry.key.replaceFirst('$dbName:', '');
          tableCache[id] = entry.value;
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
Future<dynamic> _executeProcessTask(
  String type,
  Map<String, dynamic> params,
  SendPort? dbSendPort,
) async {
  switch (type) {
    case 'writeExcel':
      return IsolateWorker.writeExcelInIsolate(params);
    case 'getMatchedSheets':
      return ExcelGenerationService.getMatchedSheetsInIsolate(params);
    case 'readSheet':
      return ExcelGenerationService.readSheetInIsolate(params);
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
      final bool forceRebuild = params['forceRebuild'] ?? false;

      final DateTime targetDate = date is DateTime
          ? date
          : (date is String
                ? DateTime.tryParse(date) ?? DateTime.now()
                : DateTime.now());

      // B. Initialize Aggregator Service and AggregatorReport in Isolate first to resolve source schema name
      final agg = AggregatorService();
      agg.init(aggregatorJson);

      final report = agg.reports.firstWhere((r) => r.key == reportKey);
      final String sourceDbName = report.extractor.isNotEmpty
          ? (report.extractor[0].extractor?.source['name'] ?? dbName)
          : dbName;

      final String sourceType = report.extractor.isNotEmpty
          ? (report.extractor[0].extractor?.source['type'] ?? 'database')
          : 'database';

      final meta = agg.getFileName({
        "predicate": {"value": targetDate},
      }, timestamp: targetDate);
      final String collection = meta['collection'] ?? reportKey;
      final String sanitizedCollection = FileService().sanitizeName(collection);

      // 1. Fetch latest database update timestamp from Database Isolate via IPC
      final ReceivePort replyPortTs = ReceivePort();
      dbSendPort!.send({
        'type': 'ipcGetLatestTimestamp',
        'replyPort': replyPortTs.sendPort,
        'params': {
          'dbName': sourceDbName,
        },
      });
      final int latestDbTs = await replyPortTs.first as int;
      replyPortTs.close();

      // 2. Discover existing workbook files for this report/date in target directory
      final String parentDir = p.dirname(targetPath);
      dynamic latestFile;
      if (await io.dirExists(parentDir)) {
        final dirFiles = io.listDir(parentDir);
        final matches = dirFiles.where((e) {
          final base = p.basename(e.path);
          return base.startsWith(sanitizedCollection) && base.endsWith('.xlsx');
        }).toList();

        if (matches.isNotEmpty) {
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          latestFile = matches.first;
        }
      }

      // 3. Validate existing cached report on disk if database has no new changes since its modification
      if (latestFile != null && !forceRebuild) {
        final fileStat = io.getFileStatSync(latestFile.path);
        final fileModifiedMs = fileStat.modified.millisecondsSinceEpoch;

        if (fileModifiedMs >= latestDbTs) {
          final fileBytes = await io.readBytes(latestFile.path);
          if (fileBytes != null && fileBytes.isNotEmpty) {
            try {
              final excel = Excel.decodeBytes(fileBytes);
              final Map<String, dynamic> predObj = report.extractor[0].extractor!.predicates.isNotEmpty
                  ? Map<String, dynamic>.from(report.extractor[0].extractor!.predicates[0] as Map)
                  : {};
              String finalSheetName = FileService().sanitizeName(
                report.extractor[0].predicatedName(
                  predObj,
                  targetDate.toIso8601String(),
                ),
              );
              if (report.key.toLowerCase().contains('monthly')) {
                finalSheetName = DateFormat('MMM_yyyy').format(targetDate);
              }

              final sheet = excel.tables[finalSheetName];
              if (sheet != null && sheet.rows.length >= 9) {
                // Parse headers (rows 1-4)
                final List<dynamic> headerData = [];
                for (int r = 1; r < 5; r++) {
                  if (r < sheet.rows.length) {
                    final cells = sheet.rows[r];
                    final rowVals =
                        cells
                            .map((c) => CellHelper.unwrap(c?.value))
                            .toList();
                    if (rowVals.any(
                      (v) => v != null && v.toString().isNotEmpty,
                    )) {
                      headerData.add(rowVals);
                    }
                  }
                }

                // Parse Summary (row 5-6)
                final Map<String, dynamic> summary = {};
                final Map<String, dynamic> summaryFormulas = {};
                final summaryTitleCells = sheet.rows[5];
                final summaryValueCells = sheet.rows[6];
                for (int col = 0; col < summaryTitleCells.length; col++) {
                  final title =
                      CellHelper.unwrap(summaryTitleCells[col]?.value)
                          ?.toString()
                          .trim();
                  if (title != null && title.isNotEmpty) {
                    final cellVal = summaryValueCells[col]?.value;
                    final calculatedVal = CellHelper.unwrap(cellVal);
                    final formula = cellVal is FormulaCellValue ? cellVal.formula : null;
                    summary[title] = calculatedVal ?? '';
                    summaryFormulas[title] = formula ?? calculatedVal ?? '';
                  }
                }

                // Parse Data rows (row 8 headers, row 9+ data)
                final dataHeaderCells = sheet.rows[8];
                final List<String> columnNames =
                    dataHeaderCells
                        .map((c) => CellHelper.unwrap(c?.value)?.toString() ?? '')
                        .toList();

                final List<List<dynamic>> aoa = [];
                aoa.add(columnNames);

                final List<Map<String, dynamic>> dataRows = [];
                for (int r = 9; r < sheet.rows.length; r++) {
                  final cells = sheet.rows[r];
                  final rowVals =
                      cells
                          .map((c) => CellHelper.unwrap(c?.value))
                          .toList();
                  final Map<String, dynamic> record = {};
                  for (int col = 0; col < columnNames.length; col++) {
                    if (col < rowVals.length && columnNames[col].isNotEmpty) {
                      record[columnNames[col]] = rowVals[col] ?? '';
                    }
                  }
                  dataRows.add(record);
                  aoa.add(
                    columnNames.map((name) => record[name] ?? '').toList(),
                  );
                }

                final Map<String, dynamic> metaPredicate = {
                  if (report.extractor[0].extractor!.predicates.isNotEmpty)
                    ...Map<String, dynamic>.from(report.extractor[0].extractor!.predicates[0] as Map),
                  "value": targetDate.toIso8601String(),
                };

                final reportData = {
                  "meta": {
                    "collection": collection,
                    "entry": report.extractor[0].predicatedName(
                      metaPredicate,
                      targetDate.toIso8601String(),
                    ),
                    "predicate": metaPredicate,
                  },
                  "name": reportKey,
                  "source": report.extractor[0].extractor?.source ?? {},
                  "header": headerData,
                  "data": dataRows,
                  "summary": summary,
                  "summaryFormulas": summaryFormulas,
                };

                debugPrint(
                  "Isolate Process Worker: Validated existing report file on disk: ${latestFile.path}. Database has no changes since file creation.",
                );
                return {
                  'data': reportData,
                  'path': latestFile.path,
                  'aoa': aoa,
                };
              }
            } catch (e) {
              debugPrint(
                "Isolate Process Worker: Cached report validation failed for ${latestFile.path}: $e. Regenerating...",
              );
            }
          }
        }
      }

      // 4. Regenerate: Clean up any previous matching reports to avoid version thrashing
      if (await io.dirExists(parentDir)) {
        final dirFiles = io.listDir(parentDir);
        final matches = dirFiles.where((e) {
          final base = p.basename(e.path);
          return base.startsWith(sanitizedCollection) && base.endsWith('.xlsx');
        }).toList();
        for (var match in matches) {
          try {
            await io.deleteFile(match.path);
          } catch (e) {
            debugPrint('IsolateWorker[Process]: Failed to delete stale report: $e');
          }
        }
      }

      Map<String, dynamic> s;

      if (sourceType == 'database') {
        // A. Fetch filtered report data from Database Isolate via IPC (Pre-filtered in DB Isolate!)
        final ReceivePort replyPort = ReceivePort();
        dbSendPort.send({
          'type': 'ipcGetFilteredReportData',
          'replyPort': replyPort.sendPort,
          'params': {
            'dbName': sourceDbName,
            'reportKey': reportKey,
            'date': date,
            'aggregatorJson': aggregatorJson,
          },
        });
        final dynamic sRaw = await replyPort.first;
        replyPort.close();
        s = Map<String, dynamic>.from(sRaw as Map);
      } else {
        // For report-sourced extractors (like unconsolidated Monthly), read directly from files on disk
        final extIntf = report.extractor[0];

        s = await extIntf.extractor!.applyPredicate(
          extIntf.extractor!.predicates[0],
          data: targetDate,
          getFileName: (meta, {DateTime? timestamp}) =>
              agg.getFileName(meta, timestamp: timestamp),
          timestamp: null,
          force: true,
        );
      }

      // Inject final sheetName
      final extIntf = report.extractor[0];
      final String entryName = extIntf.predicatedName(
        extIntf.extractor!.predicates[0] ?? {},
        targetDate.toIso8601String(),
      );
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
        'targetPath': targetPath,
      };

      // Check if target file exists to load existingBytes (supporting sheets appending)
      List<int>? existingBytes;
      if (await io.fileExists(targetPath)) {
        existingBytes = await io.readBytes(targetPath);
        writeParams['existingBytes'] = existingBytes;
      }

      final List<int>? fileBytes = IsolateWorker.writeExcelInIsolate(
        writeParams,
      );
      if (fileBytes != null) {
        await FileService().ensureDir(parentDir);
        await io.writeBytes(targetPath, Uint8List.fromList(fileBytes));
      }

      final List<Map<String, dynamic>> records =
          List<Map<String, dynamic>>.from(reportData['data'] as List? ?? []);
      final List<List<dynamic>> aoa = [];
      if (records.isNotEmpty) {
        final List<String> columnNames = records[0].keys.toList();
        aoa.add(columnNames);
        for (var record in records) {
          aoa.add(columnNames.map((name) => record[name] ?? '').toList());
        }
      }

      return {'data': reportData, 'path': targetPath, 'aoa': aoa};
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
      return IsolateWorker.writeExcelInIsolate(params);
    case 'getMatchedSheets':
      return ExcelGenerationService.getMatchedSheetsInIsolate(params);
    case 'readSheet':
      return ExcelGenerationService.readSheetInIsolate(params);
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
    debugPrint('IsolateWorker: Date parse error in _getLatestDateStatic: $e');
  }
  return maxDate;
}

DateTime? _parseDateStatic(dynamic val) {
  if (val == null) return null;
  if (val is DateTime) return val;
  if (val is num) {
    if (val.isNaN || val.isInfinite) return null;
    return DateTime.fromMillisecondsSinceEpoch(val.toInt());
  }

  final s = val.toString().trim();
  if (s.isEmpty || s.toLowerCase() == "nan") return null;

  final dt = DateTime.tryParse(s);
  if (dt != null) return dt;

  final ms = int.tryParse(s);
  if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);

  return null;
}

dynamic _findValueInsensitiveStatic(Map<dynamic, dynamic> row, String key) {
  if (key.isEmpty) return null;
  for (var k in row.keys) {
    if (k.toString().toLowerCase() == key.toLowerCase()) return row[k];
  }
  return null;
}

bool _recordMatchesDatePredicate(
  Map<dynamic, dynamic> record,
  DateTime targetDate,
  String searchKey,
  String matchType,
) {
  // Check root level fields (like "Date" if it exists at root, or "Registered On")
  final rootVal =
      record[searchKey] ?? _findValueInsensitiveStatic(record, searchKey);
  if (rootVal != null) {
    final rd = _parseDateStatic(rootVal);
    if (rd != null) {
      if (matchType == 'month') {
        if (rd.month == targetDate.month && rd.year == targetDate.year) {
          return true;
        }
      } else {
        if (rd.day == targetDate.day &&
            rd.month == targetDate.month &&
            rd.year == targetDate.year) {
          return true;
        }
      }
    }
  }

  // Check simple account transactions dynamically
  for (var entry in record.entries) {
    if (entry.key == '__meta__') continue;
    var history = entry.value;
    if (history is Map && history.isNotEmpty) {
      history = history.values.first;
    }
    if (history is List) {
      for (var tx in history) {
        if (tx is Map) {
          final val =
              tx[searchKey] ?? _findValueInsensitiveStatic(tx, searchKey);
          final rd = _parseDateStatic(val);
          if (rd != null) {
            if (matchType == 'month') {
              if (rd.month == targetDate.month && rd.year == targetDate.year) {
                return true;
              }
            } else {
              if (rd.day == targetDate.day &&
                  rd.month == targetDate.month &&
                  rd.year == targetDate.year) {
                return true;
              }
            }
          }
        }
      }
    }
  }
  return false;
}
