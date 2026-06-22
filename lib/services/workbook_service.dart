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
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class WorkbookService {
  static final WorkbookService _instance = WorkbookService._internal();
  factory WorkbookService() => _instance;
  WorkbookService._internal();

  static final Map<String, String> _formulaValues = {};

  final FileService _fileService = FileService();
  String? _lastReportPath;
  String? _lastAggregatorDir;
  Excel? _cachedExcel; // Support caching during batch generation
  String? get lastReportPath => _lastReportPath;

  void clearCache() {
    _cachedExcel = null;
  }

  Future<String> write(
    Map<String, dynamic> meta,
    Map<String, dynamic> data, {
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();

    final String collectionName = meta['collection'] ?? 'Report';

    String fileName = meta['fileName'] ?? "";
    if (fileName.isEmpty) {
      final String datePattern = formatFilenameDate(now);
      fileName =
          "${_fileService.sanitizeName(collectionName)}_$datePattern.xlsx";
    }

    final schemaName = meta['aggregator'] ?? 'Default';
    final aggregatorDir = await _fileService.getAggregatorPath(
      schemaName,
      external: true,
    );
    _lastAggregatorDir = aggregatorDir;
    await _fileService.ensureDir(aggregatorDir);

    final fullPath = p.join(aggregatorDir, fileName);
    final String targetPath = p.isAbsolute(fullPath)
        ? fullPath
        : p.absolute(fullPath);

    final String entryName = meta['entry'] ?? 'Default';
    final sheetName = _fileService.sanitizeName(entryName);
    logger.log(
      "WorkbookService: Writing to sheet '$sheetName' in file '$fileName'",
    );

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
      if (sheetsToDelete.isNotEmpty &&
          excel.sheets.length > sheetsToDelete.length) {
        for (var sn in sheetsToDelete) {
          excel.delete(sn);
        }
      }
      fileBytes = excel.encode();
      if (fileBytes != null) {
        fileBytes = WorkbookService.sortSheetsInBytes(fileBytes);
        _cachedExcel = Excel.decodeBytes(fileBytes);
      }
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
        _lastReportPath =
            "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data|$fileName";
        return _lastReportPath!;
      }
      return fileName;
    }

    if (fileBytes != null) {
      await io.writeBytes(_lastReportPath!, Uint8List.fromList(fileBytes));
      final relativePath = "xyz.maya/anydb/schema/$schemaName/reports";
      await _fileService.copyToPublicDocuments(
        _lastReportPath!,
        fileName,
        relativePath: relativePath,
      );
      _triggerRemoteShares(meta['share'] ?? [], _lastReportPath!, fileName);
    }

    await _backupDatabase(schemaName, meta['collection'] ?? "Database");

    return _lastReportPath!;
  }

  static void _prepareSheet(
    Sheet ws,
    Map<String, dynamic> jo,
    String sheetName,
  ) {
    _formulaValues.clear();
    // Set default column width for the first 30 columns to prevent '###'
    for (int i = 0; i < 30; i++) {
      ws.setColumnWidth(i, 20.0);
    }

    int row = 0;
    const int gap = 1;
    const int col = 0;

    // Matches workbook.js exactly
    // 0. Add Report Name at top
    ws.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value =
        TextCellValue("Report Type");
    ws
        .cell(CellIndex.indexByColumnRow(columnIndex: col + 1, rowIndex: row))
        .value = TextCellValue(
      jo['name'] ?? "",
    );
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

    final Map<String, dynamic> summary = Map<String, dynamic>.from(
      jo['summary'] ?? {},
    );
    final List<String> summaryKeys = summary.keys.toList();
    for (int i = 0; i < summaryKeys.length; i++) {
      ws
          .cell(CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row))
          .value = TextCellValue(
        summaryKeys[i].toUpperCase(),
      );
    }

    row += gap; // Summary Values row (should be 6)

    final List<dynamic> tableData = jo['data'] ?? [];
    final List<String> columnNames = tableData.isNotEmpty
        ? Map<String, dynamic>.from(tableData.first as Map).keys.toList()
        : [];

    // 2.2 Add Summary / Formulas - Values
    final Map<String, dynamic> formulasMap = Map<String, dynamic>.from(
      jo['summaryFormulas'] ?? jo['summary'] ?? {},
    );
    final List<dynamic> formulaValues = formulasMap.values.toList();

    // Convert tableData to the format FormulaEngine expects
    final List<Map<String, dynamic>> records = tableData
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    final int summaryValRow = row;
    debugPrint(
      "WorkbookService: Summary Values at Row $summaryValRow (A${summaryValRow + 1})",
    );
    final int tableHeaderRow = summaryValRow + gap + gap;
    final int dataStartRow = tableHeaderRow + 1;

    // Excel is 1-indexed.
    final int sr = dataStartRow + 1;
    final int er = sr + (tableData.isNotEmpty ? tableData.length - 1 : 0);
    logger.log(
      "WorkbookService: Sheet '$sheetName' formula range sr=$sr, er=$er. Records: ${tableData.length}",
    );

    for (int i = 0; i < formulaValues.length; i++) {
      final vs = CellHelper.unwrap(formulaValues[i]).toString();
      final cell = ws.cell(
        CellIndex.indexByColumnRow(
          columnIndex: col + i,
          rowIndex: summaryValRow,
        ),
      );

      // 1. Calculate the static value using our high-precision AST engine
      final dynamic calculatedValue = FormulaEngine.evaluate(
        vs,
        records,
        columnNames,
      );

      // 2. Format the Excel formula string
      final formulated = FormulaEngine.formulate(
        vs,
        columnNames,
        sr,
        er,
        sheetName: sheetName,
      );
      String formulaStr = formulated ?? vs;
      if (formulaStr.startsWith('=')) {
        formulaStr = formulaStr.substring(1);
      }

      cell.value = FormulaCellValue(formulaStr);
      final cellRef = _getCellRef(col + i, summaryValRow);
      _formulaValues["$sheetName!$cellRef"] = calculatedValue.toString();
    }

    // 3. Add Table content
    row = tableHeaderRow;
    final Map<String, dynamic> source = jo['source'] ?? {};
    final sourceType = source['type'] ?? 'database';

    if (sourceType == 'database' || sourceType == 'report') {
      // Table Header
      for (int i = 0; i < columnNames.length; i++) {
        ws
            .cell(
              CellIndex.indexByColumnRow(columnIndex: col + i, rowIndex: row),
            )
            .value = TextCellValue(
          columnNames[i],
        );
      }
      row++;
      // Table Data
      final List<dynamic> columnsConfig = jo['columns'] ?? [];
      // Table Data
      for (var rowData in tableData) {
        final Map<String, dynamic> rowMap = Map<String, dynamic>.from(
          rowData as Map,
        );
        final rowDateVal = rowMap['Date'] ?? _findValueInsensitive(rowMap, 'Date');
        final String rowSheetName = rowDateVal != null ? _fileService.sanitizeName(rowDateVal.toString()) : "";

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
            _formulaValues["$sheetName!$cellRef"] = val.toString();
          } else {
            _setCellValue(ws, col + i, row, val);
          }
        }
        row++;
      }
    }
  }

  static void _setCellValue(Sheet sheet, int c, int r, dynamic val) {
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
    );
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
      if (!p.isAbsolute(pStr) &&
          !pStr.startsWith('http') &&
          !pStr.startsWith('data:') &&
          _lastAggregatorDir != null) {
        pStr = p.join(_lastAggregatorDir!, pStr);
      }
      await InvokerService.open(pStr);
    }
  }

  void _triggerRemoteShares(
    List<dynamic> shares,
    String filePath,
    String fileName,
  ) async {
    for (var share in shares) {
      final type = share['type'];
      final url = share['url'];
      if (type == 'e-mail' && url != null) {
        final Uri emailLaunchUri = Uri(
          scheme: 'mailto',
          path: url,
          query:
              'subject=Report: $fileName&body=Please find the attached report.',
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
      final dbDir = await _fileService.getDatabasePath(
        schemaName,
        dbName,
        external: true,
      );
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
        currentDir = await _fileService.getAggregatorPath(
          aggregator,
          external: true,
        );
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
                ((sanitizedCol.isNotEmpty &&
                        p
                            .basename(_lastReportPath!.split('|').last)
                            .startsWith(sanitizedCol)) ||
                    _lastReportPath == targetPath))
          : (_lastReportPath == targetPath);

      if (_cachedExcel != null && isCacheMatch) {
        debugPrint(
          "WorkbookService: Using cached excel for getSheetNames: $targetPath",
        );
        return _getMatchedSheets(_cachedExcel!, type);
      }

      // If exact file doesn't exist, try to find the latest matching the collection
      if (!await io.fileExists(targetPath) &&
          collection.isNotEmpty &&
          currentDir != null) {
        final dir = io.listDir(currentDir);
        final sanitizedCollection = collection.replaceAll(' ', '_');
        final matches = dir.where((e) {
          final base = p.basename(e.path);
          return (base.startsWith(collection) ||
                  base.startsWith(sanitizedCollection)) &&
              base.endsWith('.xlsx');
        }).toList();

        if (matches.isNotEmpty) {
          // FIX: Sort by modification time to ensure we pick the truly 'latest' file
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          targetPath = matches.first.path;
          debugPrint(
            "WorkbookService: Discovered existing workbook for discovery at $targetPath",
          );
        }
      }

      // Check Cache again after potential discovery
      if (_cachedExcel != null && isCacheMatch) {
        return _getMatchedSheets(_cachedExcel!, type);
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) {
        debugPrint(
          "WorkbookService: Could not read workbook for discovery at $targetPath",
        );
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
        currentDir = await _fileService.getAggregatorPath(
          aggregator,
          external: true,
        );
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
                ((sanitizedCol.isNotEmpty &&
                        p
                            .basename(_lastReportPath!.split('|').last)
                            .startsWith(sanitizedCol)) ||
                    _lastReportPath == targetPath))
          : (_lastReportPath == targetPath);

      if (_cachedExcel != null && isCacheMatch) {
        debugPrint("WorkbookService: Using cached excel for read: $targetPath");
        final sheet = _cachedExcel!.tables[sheetName];
        if (sheet != null) {
          return sheet.rows
              .map((row) => row.map((cell) => cell?.value).toList())
              .toList();
        }
      }

      // If exact file doesn't exist, try to find the latest matching the collection
      if (!await io.fileExists(targetPath) &&
          collection.isNotEmpty &&
          currentDir != null) {
        final dir = io.listDir(currentDir);
        final sanitizedCollection = collection.replaceAll(' ', '_');
        final matches = dir.where((e) {
          final base = p.basename(e.path);
          return (base.startsWith(collection) ||
                  base.startsWith(sanitizedCollection)) &&
              base.endsWith('.xlsx');
        }).toList();

        if (matches.isNotEmpty) {
          // FIX: Sort by modification time to ensure we pick the truly 'latest' file
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          targetPath = matches.first.path;
          debugPrint(
            "WorkbookService: Discovered existing workbook for read at $targetPath",
          );
        }
      }

      // Check Cache again after potential discovery
      if (_cachedExcel != null && isCacheMatch) {
        final sheet = _cachedExcel!.tables[sheetName];
        if (sheet != null) {
          return sheet.rows
              .map((row) => row.map((cell) => cell?.value).toList())
              .toList();
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
    final String mins = (offset.inMinutes.abs() % 60).toString().padLeft(
      2,
      '0',
    );
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
    if (sheetsToDelete.isNotEmpty &&
        excel.sheets.length > sheetsToDelete.length) {
      for (var sn in sheetsToDelete) {
        excel.delete(sn);
      }
    }
    final savedBytes = excel.save();
    if (savedBytes != null) {
      return sortSheetsInBytes(savedBytes);
    }
    return savedBytes;
  }

  static final Map<String, int> _monthMap = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static bool isMonthly(String name) {
    final regex = RegExp(r'^[A-Za-z]{3}_\d{4}$');
    return regex.hasMatch(name);
  }

  static DateTime? parseSheetDate(String name) {
    final monthlyRegex = RegExp(r'^([A-Za-z]{3})_(\d{4})$');
    final monthlyMatch = monthlyRegex.firstMatch(name);
    if (monthlyMatch != null) {
      final monthStr = monthlyMatch.group(1)!;
      final yearStr = monthlyMatch.group(2)!;
      final month = _monthMap[monthStr.toLowerCase()] ?? 1;
      final year = int.tryParse(yearStr) ?? DateTime.now().year;
      return DateTime(year, month, 1);
    }

    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ' ').trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final day = int.tryParse(parts[0]);
      if (day != null && day >= 1 && day <= 31) {
        int? month;
        final secondPart = parts[1].toLowerCase();
        month = _monthMap[secondPart];
        month ??= int.tryParse(parts[1]);

        final year = int.tryParse(parts[2]);
        if (month != null && year != null) {
          return DateTime(year, month, day);
        }
      }
    }
    return DateTime.tryParse(cleaned) ?? DateTime.tryParse(name);
  }

  static int compareSheetNames(String a, String b) {
    final bool aMonthly = isMonthly(a);
    final bool bMonthly = isMonthly(b);
    if (aMonthly && !bMonthly) return -1;
    if (!aMonthly && bMonthly) return 1;

    final dateA = parseSheetDate(a);
    final dateB = parseSheetDate(b);
    if (dateA != null && dateB != null) {
      return dateB.compareTo(dateA); // descending
    }
    return b.compareTo(a);
  }

  static List<int> sortSheetsInBytes(List<int> bytes) {
    try {
      var archive = ZipDecoder().decodeBytes(bytes);
      _injectCalculatedValues(archive);

      ArchiveFile? workbookXmlFile;
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          workbookXmlFile = file;
          break;
        }
      }
      if (workbookXmlFile == null) return bytes;

      var xmlContent = utf8.decode(workbookXmlFile.content);

      // Find <sheets>...</sheets>
      var sheetsMatch = RegExp(
        r'<sheets>(.*?)</sheets>',
      ).firstMatch(xmlContent);
      if (sheetsMatch == null) return bytes;

      var sheetsInner = sheetsMatch.group(1)!;

      // Extract all <sheet ...> style tags
      var sheetRegex = RegExp(r'(<sheet\s+[^>]*name="([^"]+)"[^>]*>)');
      var matches = sheetRegex.allMatches(sheetsInner).toList();

      // Sort the matches by sheet name
      matches.sort((m1, m2) {
        var name1 = m1.group(2)!;
        var name2 = m2.group(2)!;
        return compareSheetNames(name1, name2);
      });

      var sortedSheetsStr = matches.map((m) => m.group(1)!).join('');

      var newXmlContent = xmlContent.replaceFirst(sheetsInner, sortedSheetsStr);
      var newContent = utf8.encode(newXmlContent);

      var newArchive = Archive();
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          newArchive.addFile(
            ArchiveFile('xl/workbook.xml', newContent.length, newContent),
          );
        } else {
          newArchive.addFile(file);
        }
      }

      return ZipEncoder().encode(newArchive) ?? bytes;
    } catch (e) {
      debugPrint("WorkbookService.sortSheetsInBytes Error: $e");
      return bytes;
    }
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

    return sheet.rows
        .map(
          (row) => row.map((cell) => CellHelper.unwrap(cell?.value)).toList(),
        )
        .toList();
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

  static dynamic _findValueInsensitive(Map<String, dynamic> row, String key) {
    if (key.isEmpty) return null;
    for (var k in row.keys) {
      if (k.toLowerCase() == key.toLowerCase()) return row[k];
    }
    return null;
  }

  static void _injectCalculatedValues(Archive archive) {
    try {
      ArchiveFile? workbookXmlFile;
      ArchiveFile? relsFile;
      
      for (var file in archive.files) {
        if (file.name == 'xl/workbook.xml') {
          workbookXmlFile = file;
        } else if (file.name == 'xl/_rels/workbook.xml.rels') {
          relsFile = file;
        }
      }
      
      if (workbookXmlFile == null || relsFile == null) return;
      
      final wbDoc = XmlDocument.parse(utf8.decode(workbookXmlFile.content));
      final relsDoc = XmlDocument.parse(utf8.decode(relsFile.content));
      
      final Map<String, String> rIdToSheetName = {};
      for (final sheet in wbDoc.findAllElements('sheet')) {
        final name = sheet.getAttribute('name');
        final rId = sheet.getAttribute('r:id');
        if (name != null && rId != null) {
          rIdToSheetName[rId] = name;
        }
      }
      
      final Map<String, String> targetToSheetName = {};
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final rId = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (rId != null && target != null) {
          final sheetName = rIdToSheetName[rId];
          if (sheetName != null) {
            targetToSheetName['xl/$target'] = sheetName;
          }
        }
      }
      
      for (var file in archive.files) {
        final sheetName = targetToSheetName[file.name];
        if (sheetName != null) {
          final xmlStr = utf8.decode(file.content);
          final sheetDoc = XmlDocument.parse(xmlStr);
          bool modified = false;
          
          for (final c in sheetDoc.findAllElements('c')) {
            final cellRef = c.getAttribute('r');
            if (cellRef == null) continue;
            
            final f = c.getElement('f');
            final v = c.getElement('v');
            if (f != null && v != null) {
              final lookupKey = "$sheetName!$cellRef";
              final calculatedVal = _formulaValues[lookupKey];
              if (calculatedVal != null) {
                v.children.clear();
                v.children.add(XmlText(calculatedVal));
                modified = true;
              }
            }
          }
          
          if (modified) {
            final newContent = utf8.encode(sheetDoc.toXmlString());
            file.content = newContent;
            file.size = newContent.length;
          }
        }
      }
    } catch (e) {
      debugPrint("WorkbookService._injectCalculatedValues Error: $e");
    }
  }
}
