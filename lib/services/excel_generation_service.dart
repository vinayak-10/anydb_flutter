import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:excel/excel.dart';
import 'file_service.dart';
import '../core/cell_helper.dart';
import 'report_formula_service.dart';

/// ExcelGenerationService: Decoupled spreadsheet generator.
/// Instantiates and writes headers, table rows, and formula structures using package:excel/excel.dart.
class ExcelGenerationService {
  static Excel? cachedExcel;
  static String? cachedExcelPath;

  static void clearCache() {
    cachedExcel = null;
    cachedExcelPath = null;
  }

  /// Returns matched sheet names from the memory cache if available and path matches.
  static List<String>? getMatchedSheetsFromCache(String targetPath, String type) {
    if (cachedExcel != null && cachedExcelPath == targetPath) {
      return getMatchedSheetsInIsolate({
        'excel': cachedExcel,
        'type': type,
      });
    }
    return null;
  }

  /// Reads sheet rows from the memory cache if available and path matches.
  static List<List<dynamic>>? readSheetFromCache(String targetPath, String sheetName) {
    if (cachedExcel != null && cachedExcelPath == targetPath) {
      final sheet = cachedExcel!.tables[sheetName];
      if (sheet != null) {
        return sheet.rows
            .map((row) => row.map((cell) => CellHelper.unwrap(cell?.value)).toList())
            .toList();
      }
    }
    return null;
  }

  /// Builds the Sheet structure from the provided configuration and pre-computed values.
  static void populateSheet({
    required Sheet ws,
    required Map<String, dynamic> jo,
    required String sheetName,
    required FormulaCalculationResult calcResult,
    required Map<String, String> formulaRegistry, // Passed registry to gather cell calculated values
  }) {
    // 1. Column Width Setup
    for (int i = 0; i < 30; i++) {
      ws.setColumnWidth(i, 20.0);
    }

    int row = 0;
    const int gap = 1;
    const int col = 0;

    // 2. Write Report Name
    ws.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
        TextCellValue("Report Type");
    ws.cell(CellIndex.indexByColumnRow(columnIndex: col + 1, rowIndex: row)).value =
        TextCellValue(jo['name'] ?? "");
    row += 1;

    // 3. Write Custom Header Rows
    final List<dynamic> headerData = jo['header'] ?? [];
    for (var headerRow in headerData) {
      if (headerRow is List) {
        for (int c = 0; c < headerRow.length; c++) {
          _setCellValue(ws, col + c, row, headerRow[c]);
        }
        row++;
      }
    }

    // 4. Position Summary Header (Row 6 / A7)
    int targetSummaryHeaderRow = 5;
    if (row < targetSummaryHeaderRow) {
      row = targetSummaryHeaderRow;
    } else {
      row += gap;
    }

    // 5. Populate Summary Titles
    final Map<String, dynamic> summary = Map<String, dynamic>.from(jo['summary'] ?? {});
    final List<String> summaryKeys = summary.keys.toList();
    for (int i = 0; i < summaryKeys.length; i++) {
      ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row)).value =
          TextCellValue(summaryKeys[i].toUpperCase());
    }

    row += gap; // Summary Values row (Row 6 index)
    final int summaryValRow = row;

    // 6. Populate Summary Values and Formulas
    for (int i = 0; i < calcResult.compiledFormulas.length; i++) {
      final cell = ws.cell(
        CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: summaryValRow),
      );
      cell.value = FormulaCellValue(calcResult.compiledFormulas[i]);
    }
    
    // Register pre-calculated results for global inject post-processing
    formulaRegistry.addAll(calcResult.formulaValuesCache);

    // 7. Write Main Table Contents
    final int tableHeaderRow = summaryValRow + gap + gap;
    row = tableHeaderRow;
    final List<dynamic> tableData = jo['data'] ?? [];
    final List<String> columnNames = calcResult.columnNames;
    final Map<String, dynamic> source = jo['source'] ?? {};
    final sourceType = source['type'] ?? 'database';

    if (sourceType == 'database' || sourceType == 'report') {
      // Table Column Headers
      for (int i = 0; i < columnNames.length; i++) {
        ws.cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row)).value =
            TextCellValue(columnNames[i]);
      }
      row++;

      // Table Row Data
      final List<dynamic> columnsConfig = jo['columns'] ?? [];
      for (var rowData in tableData) {
        final Map<String, dynamic> rowMap = Map<String, dynamic>.from(rowData as Map);
        final rowDateVal = rowMap['Date'] ?? _findValueInsensitive(rowMap, 'Date');
        final String rowSheetName = rowDateVal != null 
            ? FileService().sanitizeName(rowDateVal.toString()) 
            : "";

        for (int i = 0; i < columnNames.length; i++) {
          final val = CellHelper.unwrap(rowMap[columnNames[i]]);
          final cell = ws.cell(
            CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row),
          );

          String? colFormula;
          if (sourceType == 'report') {
            for (var colConf in columnsConfig) {
              if (colConf is Map && colConf['title'] == columnNames[i]) {
                colFormula = colConf['formula']?.toString();
                break;
              }
            }
          }

          // Write linked sheet formula for reports, otherwise write static value
          if (sourceType == 'report' && colFormula != null && rowSheetName.isNotEmpty) {
            final sourceReportName = jo['source']?['name'] ?? 'Daily';
            String formulaStr = colFormula
                .replaceAll("'$sourceReportName'", "'$rowSheetName'")
                .replaceAll(sourceReportName, rowSheetName);
            if (formulaStr.startsWith('=')) {
              formulaStr = formulaStr.substring(1);
            }
            cell.value = FormulaCellValue(formulaStr);
            
            final cellRef = _getCellRef(col + i, row);
            formulaRegistry["$sheetName!$cellRef"] = val.toString();
          } else {
            _setCellValue(ws, col + i, row, val);
          }
        }
        row++;
      }
    }
  }

  static List<String> getMatchedSheetsInIsolate(Map<String, dynamic> params) {
    final dynamic excelParam = params['excel'];
    final Excel excel = excelParam is Excel ? excelParam : Excel.decodeBytes(params['bytes'] as List<int>);
    final String type = params['type'];

    List<String> matchedSheets = [];
    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;
      if (sheet.maxColumns > 1 && sheet.maxRows > 0) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
        );
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

    final cachedValues = _extractCachedValues(bytes, sheetName);

    return sheet.rows.map((row) {
      return row.map((cell) {
        if (cell == null) return "";
        final val = cell.value;
        if (val is FormulaCellValue) {
          final ref = _getCellRef(cell.cellIndex.columnIndex, cell.cellIndex.rowIndex);
          final cached = cachedValues[ref];
          if (cached != null) {
            final n = double.tryParse(cached);
            if (n != null) {
              return n % 1 == 0 ? n.toInt() : n;
            }
            return cached;
          }
          return val.formula;
        }
        return CellHelper.unwrap(val);
      }).toList();
    }).toList();
  }

  static Map<String, String> _extractCachedValues(List<int> bytes, String targetSheetName) {
    final Map<String, String> cachedValues = {};
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? workbookFile;
      ArchiveFile? relsFile;
      for (final f in archive.files) {
        if (f.name == 'xl/workbook.xml') workbookFile = f;
        if (f.name == 'xl/_rels/workbook.xml.rels') relsFile = f;
      }
      if (workbookFile == null || relsFile == null) return {};

      final wbDoc = XmlDocument.parse(utf8.decode(workbookFile.content));
      final relsDoc = XmlDocument.parse(utf8.decode(relsFile.content));

      final Map<String, String> rIdToSheetName = {};
      for (final sheet in wbDoc.findAllElements('sheet')) {
        final name = sheet.getAttribute('name');
        final rId = sheet.getAttribute('r:id');
        if (name != null && rId != null) {
          rIdToSheetName[rId] = name;
        }
      }

      String? targetPath;
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final rId = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (rId != null && target != null) {
          final sheetName = rIdToSheetName[rId];
          if (sheetName != null && sheetName.toLowerCase() == targetSheetName.toLowerCase()) {
            targetPath = 'xl/$target';
            break;
          }
        }
      }

      if (targetPath != null) {
        for (final f in archive.files) {
          if (f.name == targetPath) {
            final sheetDoc = XmlDocument.parse(utf8.decode(f.content));
            for (final c in sheetDoc.findAllElements('c')) {
              final r = c.getAttribute('r');
              final v = c.getElement('v')?.innerText;
              if (r != null && v != null) {
                cachedValues[r] = v;
              }
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint("ExcelGenerationService._extractCachedValues Error: $e");
    }
    return cachedValues;
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

  static dynamic _findValueInsensitive(Map<String, dynamic> row, String key) {
    if (key.isEmpty) return null;
    for (var k in row.keys) {
      if (k.toLowerCase() == key.toLowerCase()) return row[k];
    }
    return null;
  }

  static String _getCellRef(int colIdx, int rowIdx) {
    int temp = colIdx;
    String columnLetter = "";
    while (temp >= 0) {
      columnLetter = String.fromCharCode((temp % 26) + 65) + columnLetter;
      temp = (temp ~/ 26) - 1;
    }
    return "$columnLetter${rowIdx + 1}";
  }
}
