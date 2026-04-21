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
    final reportName = meta['aggregator'] ?? 'Report';
    final sheetName = _fileService.sanitizeName(reportName);
    
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    final Sheet reportSheet = excel[sheetName];

    // Row 1: Report Type: [Aggregator]
    reportSheet.appendRow([TextCellValue("Report Type: $reportName")]);

    // Row 2 & 3: Schema Title & Subtitle
    final List<dynamic> headerData = data['header'] ?? [];
    String title = "";
    String subtitle = "";
    if (headerData.isNotEmpty && headerData[0] is List && (headerData[0] as List).isNotEmpty) {
      title = headerData[0][0].toString();
    }
    if (headerData.length > 1 && headerData[1] is List && (headerData[1] as List).isNotEmpty) {
      subtitle = headerData[1][0].toString();
    }
    reportSheet.appendRow([TextCellValue(title)]);
    reportSheet.appendRow([TextCellValue(subtitle)]);

    // Row 4-5: Gap
    reportSheet.appendRow([]);
    reportSheet.appendRow([]);

    // Row 6 & 7: Summary Headers and Formulas
    final Map<String, dynamic> summary = data['summary'] ?? {};
    final List<CellValue> summaryHeaders = [];
    final List<CellValue> summaryValues = [];
    
    final List<dynamic> tableData = data['records'] ?? [];
    final List<String> columnNames = tableData.isNotEmpty ? (tableData.first as Map<String, dynamic>).keys.toList() : [];
    
    // Data Table starts at Row 10 (1-indexed), Row 9 is headers
    final int sr = 10;
    final int er = sr + (tableData.isNotEmpty ? tableData.length - 1 : 0);

    summary.forEach((k, v) {
      summaryHeaders.add(TextCellValue(k.toUpperCase()));
      
      final vs = v.toString();
      if (vs.contains("SUM(") || vs.contains("COUNT(") || vs.contains("ROUND(")) {
        final formulated = FormulaEngine.formulate(vs, columnNames, sr, er, sheetName: sheetName);
        summaryValues.add(FormulaCellValue(formulated ?? vs));
      } else {
        summaryValues.add(TextCellValue(vs));
      }
    });
    reportSheet.appendRow(summaryHeaders);
    reportSheet.appendRow(summaryValues);

    // Row 8: Gap
    reportSheet.appendRow([]);

    // Row 9+: Data Table with Headers
    if (columnNames.isNotEmpty) {
      reportSheet.appendRow(List<CellValue>.from(columnNames.map((e) => TextCellValue(e))));
      
      for (var row in tableData) {
        final Map<String, dynamic> rowMap = row as Map<String, dynamic>;
        reportSheet.appendRow(List<CellValue>.from(columnNames.map((name) => TextCellValue(rowMap[name]?.toString() ?? ''))));
      }
    }

    // Save File logic
    final now = DateTime.now();
    final String monthStr = DateFormat('MMM').format(now);
    final String timestampStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final String fileName = "${_fileService.sanitizeName(reportName)}_${monthStr}_$timestampStr.xlsx";
    
    if (kIsWeb) {
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final base64Data = base64Encode(fileBytes);
        _lastReportPath = "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data|$fileName";
        return _lastReportPath!;
      }
      return fileName;
    }

    // Structure: xyz.maya/anydb/schemaName/Aggregators/reportName.xlsx
    final schemaName = meta['aggregator'] ?? 'Default';
    final aggregatorDir = await _fileService.getAggregatorPath(schemaName, external: true);
    _lastAggregatorDir = aggregatorDir;
    await _fileService.ensureDir(aggregatorDir);
    
    final fullPath = p.join(aggregatorDir, fileName);
    _lastReportPath = p.isAbsolute(fullPath) ? fullPath : p.absolute(fullPath);
    final fileBytes = excel.save();
    if (fileBytes != null) {
      await io.writeBytes(_lastReportPath!, Uint8List.fromList(fileBytes));
      // Trigger remote shares defined in schema
      _triggerRemoteShares(meta['share'] ?? [], _lastReportPath!, fileName);
    }

    // Database Backup (Automatic on report generation)
    await _backupDatabase(schemaName, meta['collection'] ?? "Database");

    return _lastReportPath!;
  }

  Future<void> openReport(String? path) async {
    var pStr = path ?? _lastReportPath;
    if (pStr != null) {
      // Verify that the path being passed is a full absolute path.
      // If it's just a filename, join it with the last known aggregator directory.
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
          if (bytes != null) {
            await http.post(Uri.parse(url), body: bytes);
          }
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
}
