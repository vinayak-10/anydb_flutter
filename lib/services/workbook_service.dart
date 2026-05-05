import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'file_service.dart';
import 'invoker_service.dart';
import '../core/formula_engine.dart';
import 'package:path/path.dart' as p;
import 'io_helper.dart' as io;

class WorkbookService {
  final FileService _fileService = FileService();
  String? _lastReportPath;
  String? _lastAggregatorDir;
  String? get lastReportPath => _lastReportPath;

  Future<String> write(Map<String, dynamic> meta, Map<String, dynamic> data, {DateTime? timestamp}) async {
    final reportName = meta['aggregator'] ?? 'Report';
    final now = timestamp ?? DateTime.now();
    
    // JS Logic: monthly reports and daily reports for the same aggregator 
    // should probably be in the same file if the name matches.
    // In RN, Workbook.js uses meta.collection for the filename.
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
    
    Excel excel;
    if (!kIsWeb && await io.fileExists(targetPath)) {
      final bytes = await io.readBytes(targetPath);
      excel = Excel.decodeBytes(bytes!);
    } else {
      excel = Excel.createExcel();
    }

    final String entryName = meta['entry'] ?? 'Default';
    final sheetName = _fileService.sanitizeName(entryName);
    debugPrint("WorkbookService: Writing to sheet '$sheetName' in file '$fileName'");
    
    // In excel library, creating a sheet if it doesn't exist
    final Sheet reportSheet = excel[sheetName];
    _prepareSheet(reportSheet, data, sheetName);

    // If we have our target sheet and it's not 'Sheet1', delete 'Sheet1'
    if (sheetName != 'Sheet1' && excel.sheets.containsKey('Sheet1')) {
      // Only delete if there is at least one other sheet
      if (excel.sheets.length > 1) {
        excel.delete('Sheet1');
      }
    }

    _lastReportPath = targetPath;
    
    if (kIsWeb) {
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final base64Data = base64Encode(fileBytes);
        _lastReportPath = "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data|$fileName";
        return _lastReportPath!;
      }
      return fileName;
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await io.writeBytes(_lastReportPath!, Uint8List.fromList(fileBytes));
      // In JS, copy to external is also done.
      // But we are already writing to an 'external' path in aggregatorDir.
      _triggerRemoteShares(meta['share'] ?? [], _lastReportPath!, fileName);
    }

    await _backupDatabase(schemaName, meta['collection'] ?? "Database");

    return _lastReportPath!;
  }

  void _prepareSheet(Sheet ws, Map<String, dynamic> jo, String sheetName) {
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
    row += gap;
    final Map<String, dynamic> summary = jo['summary'] ?? {};
    final List<String> summaryKeys = summary.keys.toList();
    for (int i = 0; i < summaryKeys.length; i++) {
      ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row)).value = TextCellValue(summaryKeys[i].toUpperCase());
    }
    
    // JS: row += gap (row is now 5 if there were 2 header rows)
    row += gap; 
    
    final List<dynamic> tableData = jo['data'] ?? [];
    final List<String> columnNames = tableData.isNotEmpty 
        ? (tableData.first as Map<String, dynamic>).keys.toList() 
        : [];
    
    // JS Logic for sr (start row):
    // In RN, row was incremented manually. 
    // row 0: Report Name
    // row 1-2: Header (2 rows)
    // row 3: Gap
    // row 4: Summary Headers
    // row 5: Summary Values (Formulas)
    // row 6: Gap
    // row 7: Gap
    // row 8: Table Headers
    // row 9: Data Start
    
    // In our _prepareSheet:
    // row 0: Report Name (1 row)
    // row 1-2: Header (len=2) -> row becomes 3
    // row 4: Summary Headers (gap 1) -> row becomes 5
    // row 5: Summary Values (Formulas) -> row stays 5
    // row 7: Table Headers (gap 2) -> row becomes 8
    // row 9: Data Start (row++) -> data starts at 9
    
    const int sr = 9; 
    final int er = sr + (tableData.isNotEmpty ? tableData.length - 1 : 0);
    debugPrint("WorkbookService: formula range sr=$sr, er=$er in sheet '$sheetName'");

    // 2.2 Add Summary / Formulas - Values
    final Map<String, dynamic> formulasMap = jo['summaryFormulas'] ?? jo['summary'] ?? {};
    final List<dynamic> formulaValues = formulasMap.values.toList();
    
    // Convert tableData to the format FormulaEngine expects
    final List<Map<String, dynamic>> records = tableData.map((r) => Map<String, dynamic>.from(r as Map)).toList();

    for (int i = 0; i < formulaValues.length; i++) {
      final vs = _unwrap(formulaValues[i]).toString();
      final cell = ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row));
      
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
        cell.value = DoubleCellValue(calculatedValue.toDouble());
      } else {
        cell.value = TextCellValue(calculatedValue.toString());
      }
    }

    // 3. Add Table content
    row += gap; row += gap;
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
           final val = _unwrap(rowMap[columnNames[i]]);
           final cell = ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row));
           
           if (sourceType == 'report' && val is String && val.startsWith('=')) {
              cell.value = FormulaCellValue(val.startsWith('=') ? val.substring(1) : val);
           } else {
              _setCellValue(ws, col + i, row, val);
           }
         }
         row++;
       }
    }
  }

  void _setCellValue(Sheet sheet, int c, int r, dynamic val) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
    final unwrapped = _unwrap(val);
    
    if (unwrapped is num) {
      if (unwrapped % 1 == 0) {
        cell.value = IntCellValue(unwrapped.toInt());
      } else {
        cell.value = DoubleCellValue(unwrapped.toDouble());
      }
    } else if (unwrapped is String) {
      final n = double.tryParse(unwrapped.replaceAll(',', ''));
      if (n != null) {
        if (n % 1 == 0) {
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

  dynamic _unwrap(dynamic val) {
    if (val is List && val.isNotEmpty) return _unwrap(val.first);
    return val ?? "";
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
      if (fileMeta is Map) {
        fileName = fileMeta['fileName'] ?? fileMeta['collection'] ?? "";
      } else {
        fileName = fileMeta.toString();
      }

      String targetPath = fileName;
      if (!p.isAbsolute(fileName) && _lastAggregatorDir != null) {
        String f = fileName;
        if (!f.endsWith('.xlsx')) f += '.xlsx';
        targetPath = p.join(_lastAggregatorDir!, f);
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) {
        debugPrint("WorkbookService: Could not read workbook at $targetPath");
        return [];
      }
      final excel = Excel.decodeBytes(bytes);
      List<String> matchedSheets = [];
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;
        
        // RN Logic: Check B1 (col 1, row 0) for the report type
        if (sheet.maxColumns > 1 && sheet.maxRows > 0) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0));
          final val = cell.value?.toString().trim();
          if (val == type) {
            matchedSheets.add(table);
          }
        }
      }
      return matchedSheets;
    } catch (e) {
      debugPrint("WorkbookService: getSheetNames Error: $e");
      return [];
    }
  }

  Future<List<List<dynamic>>> read(dynamic fileMeta, String sheetName) async {
    try {
      String fileName = "";
      if (fileMeta is Map) {
        fileName = fileMeta['fileName'] ?? fileMeta['collection'] ?? "";
      } else {
        fileName = fileMeta.toString();
      }

      String targetPath = fileName;
      if (!p.isAbsolute(fileName) && _lastAggregatorDir != null) {
        String f = fileName;
        if (!f.endsWith('.xlsx')) f += '.xlsx';
        targetPath = p.join(_lastAggregatorDir!, f);
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) return [];
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[sheetName];
      if (sheet == null) return [];

      return sheet.rows.map((row) => row.map((cell) => cell?.value).toList()).toList();
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
}
