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

  Future<String> write(Map<String, dynamic> meta, Map<String, dynamic> data) async {
    final excel = Excel.createExcel();
    final String entryName = meta['entry'] ?? 'Default';
    final sheetName = _fileService.sanitizeName(entryName);
    debugPrint("WorkbookService: Creating report with sheet name '$sheetName'");
    
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    
    final Sheet reportSheet = excel[sheetName];
    _prepareSheet(reportSheet, data, sheetName);

    // Save File logic
    final reportName = meta['aggregator'] ?? 'Report';
    final now = DateTime.now();
    final String datePattern = _formatFilenameDate(now);
    final String fileName = "${_fileService.sanitizeName(reportName)}_$datePattern.xlsx";
    
    if (kIsWeb) {
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final base64Data = base64Encode(fileBytes);
        _lastReportPath = "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data|$fileName";
        return _lastReportPath!;
      }
      return fileName;
    }

    final schemaName = meta['aggregator'] ?? 'Default';
    final aggregatorDir = await _fileService.getAggregatorPath(schemaName, external: true);
    _lastAggregatorDir = aggregatorDir;
    await _fileService.ensureDir(aggregatorDir);
    
    final fullPath = p.join(aggregatorDir, fileName);
    _lastReportPath = p.isAbsolute(fullPath) ? fullPath : p.absolute(fullPath);
    final fileBytes = excel.save();
    if (fileBytes != null) {
      await io.writeBytes(_lastReportPath!, Uint8List.fromList(fileBytes));
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
    // sr = row (summary_val_row) + 2 (gaps) + 1 (header)
    // sr is 1-indexed for Excel
    final int sr = row + 2 + 1; 
    final int er = sr + (tableData.isNotEmpty ? tableData.length - 1 : 0);
    debugPrint("WorkbookService: formula range sr=$sr, er=$er in sheet '$sheetName'");

    // 2.2 Add Summary / Formulas - Values
    final Map<String, dynamic> formulasMap = jo['summaryFormulas'] ?? jo['summary'] ?? {};
    final List<dynamic> formulaValues = formulasMap.values.toList();
    
    for (int i = 0; i < formulaValues.length; i++) {
      final vs = _unwrap(formulaValues[i]).toString();
      final cell = ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row));
      final formulated = FormulaEngine.formulate(vs, columnNames, sr, er, sheetName: sheetName);
      
      String formulaStr = formulated ?? vs;
      if (formulaStr.startsWith('=')) {
        formulaStr = formulaStr.substring(1);
      }
      cell.value = FormulaCellValue(formulaStr);
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
      cell.value = DoubleCellValue(unwrapped.toDouble());
    } else if (unwrapped is String) {
      final n = double.tryParse(unwrapped.replaceAll(',', ''));
      if (n != null) {
        cell.value = DoubleCellValue(n);
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

  Future<List<String>> getSheetNames(String filePath, String type) async {
    try {
      final bytes = await io.readBytes(filePath);
      if (bytes == null) return [];
      final excel = Excel.decodeBytes(bytes);
      List<String> matchedSheets = [];
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;
        if (sheet.maxColumns > 1 && sheet.maxRows > 0) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0));
          if (cell.value?.toString() == type) matchedSheets.add(table);
        }
      }
      return matchedSheets;
    } catch (e) {
      return [];
    }
  }

  Future<List<List<dynamic>>> read(String filePath, String sheetName) async {
    try {
      final bytes = await io.readBytes(filePath);
      if (bytes == null) return [];
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[sheetName];
      if (sheet == null) return [];
      return sheet.rows.map((row) => row.map((cell) => cell?.value).toList()).toList();
    } catch (e) {
      return [];
    }
  }

  String _formatFilenameDate(DateTime dt) {
    // Target Pattern: Sat_Mar_21_2026_12_24_54_GMT_0530
    final String day = DateFormat('E').format(dt);
    final String month = DateFormat('MMM').format(dt);
    final String rest = DateFormat('dd_yyyy_HH_mm_ss').format(dt);
    
    final offset = dt.timeZoneOffset;
    final String hours = offset.inHours.abs().toString().padLeft(2, '0');
    final String mins = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final String sign = offset.isNegative ? "-" : "";
    final String gmt = "GMT_$sign$hours$mins";

    return "${month}_${dt.year}_${day}_${month}_${rest}_$gmt";
  }
}
