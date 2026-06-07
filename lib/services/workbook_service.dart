import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'file_service.dart';
import 'invoker_service.dart';
import 'isolate_worker.dart';
import '../core/formula_engine.dart';
import '../core/cell_helper.dart';
import '../core/logger.dart';
import 'package:path/path.dart' as p;
import 'io_helper.dart' as io;

class WorkbookService {
  static final WorkbookService _instance = WorkbookService._internal();
  factory WorkbookService() => _instance;
  WorkbookService._internal();

  final FileService _fileService = FileService();
  String? _lastReportPath;
  String? _lastAggregatorDir;
  Excel? _cachedExcel; // Support caching during batch generation
  String? get lastReportPath => _lastReportPath;

  void clearCache() {
    _cachedExcel = null;
  }

  Future<String> write(Map<String, dynamic> meta, Map<String, dynamic> data, {DateTime? timestamp}) async {
    final now = timestamp ?? DateTime.now();
    
    final String collectionName = meta['collection'] ?? 'Report';
    
    String fileName = meta['fileName'] ?? "";
    if (fileName.isEmpty) {
      final String datePattern = formatFilenameDate(now);
      fileName = "${_fileService.sanitizeName(collectionName)}_$datePattern.xlsx";
    }
    
    final schemaName = meta['aggregator'] ?? 'Default';
    final aggregatorDir = await _fileService.getAggregatorPath(schemaName, external: true);
    _lastAggregatorDir = aggregatorDir;
    await _fileService.ensureDir(aggregatorDir);
    
    final fullPath = p.join(aggregatorDir, fileName);
    final String targetPath = p.isAbsolute(fullPath) ? fullPath : p.absolute(fullPath);
    
    final String entryName = meta['entry'] ?? 'Default';
    final sheetName = _fileService.sanitizeName(entryName);
    logger.log("WorkbookService: Writing to sheet '$sheetName' in file '$fileName'");
    
    List<int>? fileBytes;
    if (kIsWeb) {
      Excel excel;
      if (_cachedExcel != null) {
        excel = _cachedExcel!;
      } else {
        excel = Excel.createExcel();
        _cachedExcel = excel;
      }
      final Sheet reportSheet = excel[sheetName];
      _prepareSheet(reportSheet, data, sheetName);
      
      final List<String> sheetsToDelete = [];
      for (var sn in excel.sheets.keys) {
        if (sn != sheetName && (sn == 'Sheet1' || sn == 'Sheet 1')) {
          sheetsToDelete.add(sn);
        }
      }
      if (sheetsToDelete.isNotEmpty && excel.sheets.length > sheetsToDelete.length) {
        for (var sn in sheetsToDelete) {
          excel.delete(sn);
        }
      }
      fileBytes = excel.encode();
    } else {
      List<int>? existingBytes;
      if (_cachedExcel != null) {
        existingBytes = _cachedExcel!.save();
      } else if (await io.fileExists(targetPath)) {
        existingBytes = await io.readBytes(targetPath);
      }
      
      if (IsolateWorker.isInsideWorkerIsolate) {
        final fileBytesList = WorkbookService.writeExcelInIsolate({
          'existingBytes': existingBytes,
          'data': data,
          'sheetName': sheetName,
        });
        fileBytes = fileBytesList;
      } else {
        fileBytes = await IsolateWorker.instance.execute<List<int>?>(
          'writeExcel',
          {
            'existingBytes': existingBytes,
            'data': data,
            'sheetName': sheetName,
          },
        );
      }
      
      if (fileBytes != null) {
        _cachedExcel = Excel.decodeBytes(fileBytes);
      }
    }

    _lastReportPath = targetPath;
    
    if (kIsWeb) {
      if (fileBytes != null) {
        final base64Data = base64Encode(fileBytes);
        _lastReportPath = "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data|$fileName";
        return _lastReportPath!;
      }
      return fileName;
    }

    if (fileBytes != null) {
      await io.writeBytes(_lastReportPath!, Uint8List.fromList(fileBytes));
      _triggerRemoteShares(meta['share'] ?? [], _lastReportPath!, fileName);
    }

    await _backupDatabase(schemaName, meta['collection'] ?? "Database");

    return _lastReportPath!;
  }

  static void _prepareSheet(Sheet ws, Map<String, dynamic> jo, String sheetName) {
    // Set default column width for the first 30 columns to prevent '###'
    for (int i = 0; i < 30; i++) {
      ws.setColumnWidth(i, 20.0);
    }

    int row = 0;
    const int gap = 1;
    const int col = 0;

    // Matches workbook.js exactly
    // 0. Add Report Name at top
    ws.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = TextCellValue("Report Type");
    ws.cell(CellIndex.indexByColumnRow(columnIndex: col + 1, rowIndex: row)).value = TextCellValue(jo['name'] ?? "");
    row += 1;

    // 1. Add Header (AOA)
    final List<dynamic> headerData = jo['header'] ?? [];
    for (var headerRow in headerData) {
      if (headerRow is List) {
        for (int c = 0; c < headerRow.length; c++) {
          _setCellValue(ws, col + c, row, headerRow[c]);
        }
        row++;
      }
    }

    // 2.1 Add Summary / Formulas - Header
    // We force the summary row to match AnyDB schema expectations (Row 6 / A7)
    // regardless of the number of header rows.
    int targetSummaryHeaderRow = 5;
    if (row < targetSummaryHeaderRow) {
      row = targetSummaryHeaderRow;
    } else {
      row += gap;
    }

    final Map<String, dynamic> summary = Map<String, dynamic>.from(jo['summary'] ?? {});
    final List<String> summaryKeys = summary.keys.toList();
    for (int i = 0; i < summaryKeys.length; i++) {
      ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row)).value = TextCellValue(summaryKeys[i].toUpperCase());
    }
    
    row += gap; // Summary Values row (should be 6)
    
    final List<dynamic> tableData = jo['data'] ?? [];
    final List<String> columnNames = tableData.isNotEmpty 
        ? Map<String, dynamic>.from(tableData.first as Map).keys.toList() 
        : [];
    
    // 2.2 Add Summary / Formulas - Values
    final Map<String, dynamic> formulasMap = Map<String, dynamic>.from(jo['summaryFormulas'] ?? jo['summary'] ?? {});
    final List<dynamic> formulaValues = formulasMap.values.toList();
    
    // Convert tableData to the format FormulaEngine expects
    final List<Map<String, dynamic>> records = tableData.map((r) => Map<String, dynamic>.from(r as Map)).toList();

    final int summaryValRow = row;
    debugPrint("WorkbookService: Summary Values at Row $summaryValRow (A${summaryValRow + 1})");
    final int tableHeaderRow = summaryValRow + gap + gap;
    final int dataStartRow = tableHeaderRow + 1;
    
    // Excel is 1-indexed.
    final int sr = dataStartRow + 1; 
    final int er = sr + (tableData.isNotEmpty ? tableData.length - 1 : 0);
    logger.log("WorkbookService: Sheet '$sheetName' formula range sr=$sr, er=$er. Records: ${tableData.length}");

    for (int i = 0; i < formulaValues.length; i++) {
      final vs = CellHelper.unwrap(formulaValues[i]).toString();
      final cell = ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: summaryValRow));
      
      // 1. Calculate the static value using our high-precision AST engine
      final dynamic calculatedValue = FormulaEngine.evaluate(vs, records, columnNames);
      
      // 2. Format the Excel formula string
      final formulated = FormulaEngine.formulate(vs, columnNames, sr, er, sheetName: sheetName);
      String formulaStr = formulated ?? vs;
      if (formulaStr.startsWith('=')) {
        formulaStr = formulaStr.substring(1);
      }
      
      // 3. Write HYBRID cell: Formula for live updates, Static Value for immediate accuracy
      cell.setFormula(formulaStr);
      if (calculatedValue is num) {
        if (calculatedValue % 1 == 0) {
          cell.value = IntCellValue(calculatedValue.toInt());
        } else {
          cell.value = DoubleCellValue(calculatedValue.toDouble());
        }
      } else {
        cell.value = TextCellValue(calculatedValue.toString());
      }
    }

    // 3. Add Table content
    row = tableHeaderRow;
    final Map<String, dynamic> source = jo['source'] ?? {};
    final sourceType = source['type'] ?? 'database';

    if (sourceType == 'database' || sourceType == 'report') {
       // Table Header
       for (int i = 0; i < columnNames.length; i++) {
         ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row)).value = TextCellValue(columnNames[i]);
       }
       row++;
       // Table Data
       for (var rowData in tableData) {
         final Map<String, dynamic> rowMap = Map<String, dynamic>.from(rowData as Map);
         for (int i = 0; i < columnNames.length; i++) {
           final val = CellHelper.unwrap(rowMap[columnNames[i]]);
           final cell = ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row));
           
           // Check if it's a formula reference (starts with ! or contains ! and looks like a cell ref)
           bool isFormula = val is String && (val.startsWith('=') || val.contains('!'));

           if (sourceType == 'report' && isFormula) {
              String formulaStr = val.toString();
              if (formulaStr.startsWith('=')) {
                formulaStr = formulaStr.substring(1);
              }
              cell.value = FormulaCellValue(formulaStr);
           } else {
              _setCellValue(ws, col + i, row, val);
           }
         }
         row++;
       }
    }
  }

  static void _setCellValue(Sheet sheet, int c, int r, dynamic val) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
    final unwrapped = CellHelper.unwrap(val);
    
    if (unwrapped is num) {
      if (unwrapped.isNaN || unwrapped.isInfinite) {
        cell.value = IntCellValue(0);
        return;
      }
      if (unwrapped % 1 == 0) {
        cell.value = IntCellValue(unwrapped.toInt());
      } else {
        cell.value = DoubleCellValue(unwrapped.toDouble());
      }
    } else if (unwrapped is String) {
      final n = double.tryParse(unwrapped.replaceAll(',', ''));
      if (n != null) {
        if (n.isNaN || n.isInfinite) {
          cell.value = IntCellValue(0);
        } else if (n % 1 == 0) {
          cell.value = IntCellValue(n.toInt());
        } else {
          cell.value = DoubleCellValue(n);
        }
      } else {
        cell.value = TextCellValue(unwrapped);
      }
    } else {
      cell.value = TextCellValue(unwrapped.toString());
    }
  }

  Future<void> openReport(String? path) async {
    var pStr = path ?? _lastReportPath;
    if (pStr != null) {
      if (!p.isAbsolute(pStr) && !pStr.startsWith('http') && !pStr.startsWith('data:') && _lastAggregatorDir != null) {
        pStr = p.join(_lastAggregatorDir!, pStr);
      }
      await InvokerService.open(pStr);
    }
  }

  void _triggerRemoteShares(List<dynamic> shares, String filePath, String fileName) async {
    for (var share in shares) {
      final type = share['type'];
      final url = share['url'];
      if (type == 'e-mail' && url != null) {
        final Uri emailLaunchUri = Uri(
          scheme: 'mailto',
          path: url,
          query: 'subject=Report: $fileName&body=Please find the attached report.',
        );
        launchUrl(emailLaunchUri);
      } else if (type == 'url' && url != null) {
        try {
          final bytes = await io.readBytes(filePath);
          if (bytes != null) await http.post(Uri.parse(url), body: bytes);
        } catch (e) {
          debugPrint("WorkbookService: REST share failed: $e");
        }
      }
    }
  }

  Future<void> _backupDatabase(String schemaName, String dbName) async {
    try {
      final dbDir = await _fileService.getDatabasePath(schemaName, dbName, external: true);
      await _fileService.ensureDir(dbDir);
    } catch (e) {
      debugPrint("WorkbookService: Backup failed: $e");
    }
  }

  Future<List<String>> getSheetNames(dynamic fileMeta, String type) async {
    try {
      String fileName = "";
      String collection = "";
      String aggregator = "";
      if (fileMeta is Map) {
        fileName = fileMeta['fileName'] ?? fileMeta['collection'] ?? "";
        collection = fileMeta['collection'] ?? "";
        aggregator = fileMeta['aggregator'] ?? "";
      } else {
        fileName = fileMeta.toString();
        collection = fileName;
      }

      String? currentDir = _lastAggregatorDir;
      if (currentDir == null && aggregator.isNotEmpty) {
        currentDir = await _fileService.getAggregatorPath(aggregator, external: true);
        _lastAggregatorDir = currentDir;
      }

      String targetPath = fileName;
      if (!p.isAbsolute(fileName) && currentDir != null) {
        String f = fileName;
        if (!f.endsWith('.xlsx')) f += '.xlsx';
        targetPath = p.join(currentDir, f);
      }

      // Check Cache first
      final String sanitizedCol = _fileService.sanitizeName(collection);
      final bool isCacheMatch = kIsWeb
          ? (_lastReportPath != null &&
              ((sanitizedCol.isNotEmpty && p.basename(_lastReportPath!.split('|').last).startsWith(sanitizedCol)) ||
               _lastReportPath == targetPath))
          : (_lastReportPath == targetPath);

      if (_cachedExcel != null && isCacheMatch) {
        debugPrint("WorkbookService: Using cached excel for getSheetNames: $targetPath");
        return _getMatchedSheets(_cachedExcel!, type);
      }

      // If exact file doesn't exist, try to find the latest matching the collection
      if (!await io.fileExists(targetPath) && collection.isNotEmpty && currentDir != null) {
        final dir = io.listDir(currentDir);
        final sanitizedCollection = collection.replaceAll(' ', '_');
        final matches = dir.where((e) {
           final base = p.basename(e.path);
           return (base.startsWith(collection) || base.startsWith(sanitizedCollection)) && base.endsWith('.xlsx');
        }).toList();
        
        if (matches.isNotEmpty) {
          // FIX: Sort by modification time to ensure we pick the truly 'latest' file
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          targetPath = matches.first.path;
          debugPrint("WorkbookService: Discovered existing workbook for discovery at $targetPath");
        }
      }

      // Check Cache again after potential discovery
      if (_cachedExcel != null && isCacheMatch) {
        return _getMatchedSheets(_cachedExcel!, type);
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) {
        debugPrint("WorkbookService: Could not read workbook for discovery at $targetPath");
        return [];
      }
      if (IsolateWorker.isInsideWorkerIsolate) {
        return getMatchedSheetsInIsolate({'bytes': bytes, 'type': type});
      }
      return await IsolateWorker.instance.execute<List<String>>(
        'getMatchedSheets',
        {'bytes': bytes, 'type': type},
      );
    } catch (e) {
      debugPrint("WorkbookService: getSheetNames Error: $e");
      return [];
    }
  }

  List<String> _getMatchedSheets(Excel excel, String type) {
    List<String> matchedSheets = [];
    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;
      
      // RN Logic: Check B1 (col 1, row 0) for the report type
      if (sheet.maxColumns > 1 && sheet.maxRows > 0) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0));
        final val = CellHelper.unwrap(cell.value);
        if (val.toString().trim().toLowerCase() == type.toLowerCase()) {
          matchedSheets.add(table);
        }
      }
    }
    return matchedSheets;
  }

  Future<List<List<dynamic>>> read(dynamic fileMeta, String sheetName) async {
    try {
      String fileName = "";
      String collection = "";
      String aggregator = "";
      if (fileMeta is Map) {
        fileName = fileMeta['fileName'] ?? fileMeta['collection'] ?? "";
        collection = fileMeta['collection'] ?? "";
        aggregator = fileMeta['aggregator'] ?? "";
      } else {
        fileName = fileMeta.toString();
        collection = fileName;
      }

      String? currentDir = _lastAggregatorDir;
      if (currentDir == null && aggregator.isNotEmpty) {
        currentDir = await _fileService.getAggregatorPath(aggregator, external: true);
        _lastAggregatorDir = currentDir;
      }

      String targetPath = fileName;
      if (!p.isAbsolute(fileName) && currentDir != null) {
        String f = fileName;
        if (!f.endsWith('.xlsx')) f += '.xlsx';
        targetPath = p.join(currentDir, f);
      }

      // Check Cache first
      final String sanitizedCol = _fileService.sanitizeName(collection);
      final bool isCacheMatch = kIsWeb
          ? (_lastReportPath != null &&
              ((sanitizedCol.isNotEmpty && p.basename(_lastReportPath!.split('|').last).startsWith(sanitizedCol)) ||
               _lastReportPath == targetPath))
          : (_lastReportPath == targetPath);

      if (_cachedExcel != null && isCacheMatch) {
        debugPrint("WorkbookService: Using cached excel for read: $targetPath");
        final sheet = _cachedExcel!.tables[sheetName];
        if (sheet != null) {
          return sheet.rows.map((row) => row.map((cell) => cell?.value).toList()).toList();
        }
      }

      // If exact file doesn't exist, try to find the latest matching the collection
      if (!await io.fileExists(targetPath) && collection.isNotEmpty && currentDir != null) {
        final dir = io.listDir(currentDir);
        final sanitizedCollection = collection.replaceAll(' ', '_');
        final matches = dir.where((e) {
           final base = p.basename(e.path);
           return (base.startsWith(collection) || base.startsWith(sanitizedCollection)) && base.endsWith('.xlsx');
        }).toList();

        if (matches.isNotEmpty) {
          // FIX: Sort by modification time to ensure we pick the truly 'latest' file
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          targetPath = matches.first.path;
          debugPrint("WorkbookService: Discovered existing workbook for read at $targetPath");
        }
      }

      // Check Cache again after potential discovery
      if (_cachedExcel != null && isCacheMatch) {
        final sheet = _cachedExcel!.tables[sheetName];
        if (sheet != null) {
          return sheet.rows.map((row) => row.map((cell) => cell?.value).toList()).toList();
        }
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) return [];
      
      if (IsolateWorker.isInsideWorkerIsolate) {
        return readSheetInIsolate({'bytes': bytes, 'sheetName': sheetName});
      }
      final dynamic rawRows = await IsolateWorker.instance.execute(
        'readSheet',
        {'bytes': bytes, 'sheetName': sheetName},
      );
      
      if (rawRows is List) {
        return rawRows.map((row) => (row as List).toList()).toList();
      }
      return [];
    } catch (e) {
      debugPrint("WorkbookService: read Error: $e");
      return [];
    }
  }

  String formatFilenameDate(DateTime dt) {
    // User requested pattern: Sat_Mar_21_2026_12_24_54_GMT_0530
    final String dayName = DateFormat('E').format(dt);
    final String monthName = DateFormat('MMM').format(dt);
    final String rest = DateFormat('dd_yyyy_HH_mm_ss').format(dt);
    
    final offset = dt.timeZoneOffset;
    final String hours = offset.inHours.abs().toString().padLeft(2, '0');
    final String mins = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final String sign = offset.isNegative ? "-" : "";
    final String gmt = "GMT_$sign$hours$mins";

    return "${dayName}_${monthName}_${rest}_$gmt";
  }

  // --- Static Isolate Workers Dispatchers ---
  static List<int>? writeExcelInIsolate(Map<String, dynamic> params) {
    final List<int>? existingBytes = params['existingBytes'];
    final Map<String, dynamic> data = params['data'];
    final String sheetName = params['sheetName'];
    
    Excel excel;
    if (existingBytes != null && existingBytes.isNotEmpty) {
      excel = Excel.decodeBytes(existingBytes);
    } else {
      excel = Excel.createExcel();
    }
    
    final Sheet ws = excel[sheetName];
    _prepareSheet(ws, data, sheetName);
    
    final List<String> sheetsToDelete = [];
    for (var sn in excel.sheets.keys) {
      if (sn != sheetName && (sn == 'Sheet1' || sn == 'Sheet 1')) {
        sheetsToDelete.add(sn);
      }
    }
    if (sheetsToDelete.isNotEmpty && excel.sheets.length > sheetsToDelete.length) {
      for (var sn in sheetsToDelete) {
        excel.delete(sn);
      }
    }
    return excel.save();
  }

  static List<String> getMatchedSheetsInIsolate(Map<String, dynamic> params) {
    final List<int> bytes = params['bytes'];
    final String type = params['type'];
    final excel = Excel.decodeBytes(bytes);
    
    List<String> matchedSheets = [];
    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;
      if (sheet.maxColumns > 1 && sheet.maxRows > 0) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0));
        final val = CellHelper.unwrap(cell.value);
        if (val.toString().trim().toLowerCase() == type.toLowerCase()) {
          matchedSheets.add(table);
        }
      }
    }
    return matchedSheets;
  }

  static List<List<dynamic>> readSheetInIsolate(Map<String, dynamic> params) {
    final List<int> bytes = params['bytes'];
    final String sheetName = params['sheetName'];
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[sheetName];
    if (sheet == null) return [];
    
    return sheet.rows.map((row) => row.map((cell) => CellHelper.unwrap(cell?.value)).toList()).toList();
  }
}
