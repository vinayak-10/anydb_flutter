import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import '../core/cell_helper.dart';
import 'workbook_service.dart';
import 'schema_service.dart';
import 'storage_service.dart';

class IsolateWorker {
  static final IsolateWorker _instance = IsolateWorker._internal();
  static IsolateWorker get instance => _instance;
  IsolateWorker._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer<dynamic>> _pendingTasks = {};
  int _taskIdCounter = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    
    try {
      _isolate = await Isolate.spawn(_workerEntryPoint, _receivePort.sendPort);
      
      final Completer<SendPort> portCompleter = Completer<SendPort>();
      _receivePort.listen((message) {
        if (message is SendPort) {
          portCompleter.complete(message);
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

      _sendPort = await portCompleter.future;
      _initialized = true;
      debugPrint("IsolateWorker: Persistent worker thread successfully established.");
    } catch (e) {
      debugPrint("IsolateWorker Init Error: $e");
      rethrow;
    }
  }

  Future<T> execute<T>(String taskType, Map<String, dynamic> params) async {
    if (kIsWeb) {
      // Browser environment executes tasks synchronously on the main thread safely
      return _executeTaskSync(taskType, params) as T;
    }
    
    await init();
    final int taskId = _taskIdCounter++;
    final completer = Completer<T>();
    _pendingTasks[taskId] = completer;

    _sendPort!.send({
      'id': taskId,
      'type': taskType,
      'params': params,
    });

    return completer.future;
  }
}

// 1. Worker thread entrypoint executing in raw OS sandbox
void _workerEntryPoint(SendPort mainSendPort) {
  final ReceivePort workerReceivePort = ReceivePort();
  mainSendPort.send(workerReceivePort.sendPort);

  workerReceivePort.listen((message) {
    if (message is Map) {
      final int id = message['id'];
      final String taskType = message['type'];
      final Map<String, dynamic> params = message['params'];

      try {
        final result = _executeTaskSync(taskType, params);
        mainSendPort.send({
          'id': id,
          'result': result,
        });
      } catch (e) {
        mainSendPort.send({
          'id': id,
          'error': e.toString(),
        });
      }
    }
  });
}

// 2. Synchronous task dispatch table
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
