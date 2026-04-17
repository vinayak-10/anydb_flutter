import 'package:flutter/foundation.dart';
import 'package:excel/excel.dart';
import 'file_service.dart';
import 'package:path/path.dart' as p;
import 'io_helper.dart' as io;

class WorkbookService {
  final FileService _fileService = FileService();

  Future<String> write(Map<String, dynamic> meta, Map<String, dynamic> data) async {
    final excel = Excel.createExcel();
    final sheetName = meta['entry'] ?? 'Sheet1';
    
    // Remove default sheet
    if (excel.sheets.containsKey('Sheet1') && sheetName != 'Sheet1') {
      excel.delete('Sheet1');
    }

    final Sheet sheetObject = excel[sheetName];

    // 1. Add Report Name
    sheetObject.appendRow([TextCellValue("Report Type"), TextCellValue(data['name'] ?? "")]);
    
    // 2. Add Header
    final List<dynamic> headers = data['header'] ?? [];
    for (var headerRow in headers) {
      sheetObject.appendRow(List<CellValue>.from(headerRow.map((e) => TextCellValue(e.toString()))));
    }

    // 3. Add Summary Headers
    sheetObject.appendRow([TextCellValue("")]); // Gap
    final Map<String, dynamic> summary = data['summary'] ?? {};
    sheetObject.appendRow(List<CellValue>.from(summary.keys.map((e) => TextCellValue(e))));
    
    // 4. Add Summary Values (Formulas not directly supported by 'excel' package in the same way, using values for now)
    sheetObject.appendRow(List<CellValue>.from(summary.values.map((e) => TextCellValue(e.toString()))));

    // 5. Add Table Data
    sheetObject.appendRow([TextCellValue("")]); // Gap
    sheetObject.appendRow([TextCellValue("")]); // Gap
    
    final List<dynamic> tableData = data['data'] ?? [];
    if (tableData.isNotEmpty) {
      // Add data headers
      final firstRow = tableData.first as Map<String, dynamic>;
      sheetObject.appendRow(List<CellValue>.from(firstRow.keys.map((e) => TextCellValue(e))));
      
      // Add data rows
      for (var row in tableData) {
        final Map<String, dynamic> rowMap = row as Map<String, dynamic>;
        sheetObject.appendRow(List<CellValue>.from(rowMap.values.map((e) => TextCellValue(e.toString()))));
      }
    }

    // Save File
    final aggregatorName = _fileService.sanitizeName(meta['aggregator']);
    final fileName = "${meta['collection']}.xlsx";
    
    if (kIsWeb) {
      // On web, skip direct file system operations
      return fileName;
    }

    final internalPath = await _fileService.getInternalPath(aggregatorName, "aggregator", "");
    await _fileService.ensureDir(internalPath);
    
    final fullPath = p.join(internalPath, fileName);
    final fileBytes = excel.save();
    if (fileBytes != null) {
      await io.writeBytes(fullPath, fileBytes);
    }

    // Copy to external for sharing
    final externalPath = await _fileService.getExternalPath(aggregatorName, "aggregator", "");
    await _fileService.ensureDir(externalPath);
    final externalFile = p.join(externalPath, fileName);
    await io.copyFile(fullPath, externalFile);

    return externalFile;
  }
}
