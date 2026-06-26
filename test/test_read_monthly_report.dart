import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:anydb_flutter/services/excel_generation_service.dart';
import 'package:anydb_flutter/services/isolate_worker.dart';
import 'package:anydb_flutter/core/formula_engine.dart';
import 'package:excel/excel.dart';

void main() {
  test('Read Monthly Report test', () async {
    final dir = Directory("/home/ruggedcoder/Documents/xyz.maya/anydb/RKM_Physio/Aggregators");
    if (!dir.existsSync()) {
      print("Directory does not exist!");
      return;
    }
    final files = dir.listSync().where((f) => f.path.endsWith(".xlsx")).toList();
    for (var f in files) {
      final bytes = File(f.path).readAsBytesSync();
      try {
        final excel = Excel.decodeBytes(bytes);
        print("File: ${f.path.split('/').last} (${bytes.length} bytes)");
        print("  Sheets: ${excel.tables.keys.toList()}");
        for (var sheetName in excel.tables.keys) {
          final sheet = excel.tables[sheetName]!;
          print("    Sheet '$sheetName': rows=${sheet.rows.length}, maxCols=${sheet.maxColumns}, maxRows=${sheet.maxRows}");
          final cached = ExcelGenerationService.extractCachedValues(bytes, sheetName);
          print("      Cached values count: ${cached.length}");
          final row7Keys = ['A7', 'B7', 'C7', 'D7', 'E7', 'F7', 'G7', 'H7', 'I7', 'J7', 'K7', 'L7', 'M7', 'N7'];
          final row7Cached = {};
          for (var k in row7Keys) {
            if (cached.containsKey(k)) {
              row7Cached[k] = cached[k];
            }
          }
          print("      Row 7 cached values: $row7Cached");
          if (sheet.maxRows > 7) {
            for (int r = 5; r <= 7; r++) {
              final rowCells = sheet.rows[r];
              final cellDetails = [];
              for (int c = 0; c < rowCells.length.clamp(0, 5); c++) {
                final cell = rowCells[c];
                cellDetails.add(cell == null ? "null" : "${cell.value} (${cell.value.runtimeType})");
              }
              print("      Row $r cells: $cellDetails");
            }
          }
        }
      } catch (e) {
        print("Error reading ${f.path}: $e");
      }
    }
  });

  test('Formula Evaluation Test', () {
    final List<Map<String, dynamic>> data = [
      {
        "Card Number": "569",
        "Display Name": "Rajendra Kushwaha ",
        "Sex": "Male",
        "Charges": 50,
        "Paid": 50,
        "Discount": 0,
        "Mode": "Cash",
        "Registered On": "2026-06-09",
        "Date": "2026-06-22"
      }
    ];
    final headers = ["Card Number", "Display Name", "Sex", "Charges", "Paid", "Discount", "Mode", "Registered On", "Date"];
    final formulas = {
      "Total Charges": "SUM(\$Charges.START:\$Charges.END)",
      "Total Paid": "SUM(\$Paid.START:\$Paid.END)",
      "Total Cash": "SUMIF(\$Mode.START:\$Mode.END, \"Cash\", \$Paid.START:\$Paid.END)",
      "Total UPI": "SUMIF(\$Mode.START:\$Mode.END, \"UPI\", \$Paid.START:\$Paid.END)",
      "Total Transactions": "COUNTA(\$Mode.START:\$Mode.END)",
      "Male": "IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END,\$Sex.START:\$Sex.END=\"Male\"))),0)",
    };

    for (var entry in formulas.entries) {
      final res = FormulaEngine.evaluate(entry.value, data, headers);
      print("Formula '${entry.key}' ('${entry.value}') -> result: $res (${res.runtimeType})");
    }
  });

  test('writeExcelInIsolate Unit Test', () {
    final Map<String, dynamic> reportData = {
      "name": "Daily",
      "header": [
        ["Ramakrishna Mission, Indore"],
        ["Physiotherapy Center's Daily Report"],
        ["Patients on Date", "22/06/2026"]
      ],
      "data": [
        {
          "Card Number": "569",
          "Display Name": "Rajendra Kushwaha ",
          "Sex": "Male",
          "Charges": 50,
          "Paid": 50,
          "Discount": 0,
          "Mode": "Cash",
          "Registered On": "2026-06-09",
          "Date": "2026-06-22"
        }
      ],
      "summary": {
        "Total Charges": 50.0,
        "Total Paid": 50.0,
        "Total Cash": 50.0,
        "Total UPI": 0.0,
        "Total Transactions": 1,
        "Male": 1
      },
      "summaryFormulas": {
        "Total Charges": "SUM(\$Charges.START:\$Charges.END)",
        "Total Paid": "SUM(\$Paid.START:\$Paid.END)",
        "Total Cash": "SUMIF(\$Mode.START:\$Mode.END, \"Cash\", \$Paid.START:\$Paid.END)",
        "Total UPI": "SUMIF(\$Mode.START:\$Mode.END, \"UPI\", \$Paid.START:\$Paid.END)",
        "Total Transactions": "COUNTA(\$Mode.START:\$Mode.END)",
        "Male": "IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END,\$Sex.START:\$Sex.END=\"Male\"))),0)"
      },
      "columns": ["Card Number", "Display Name", "Sex", "Charges", "Paid", "Discount", "Mode", "Registered On", "Date"]
    };

    final params = {
      "existingBytes": null,
      "data": reportData,
      "sheetName": "22_06_2026",
      "targetPath": "dummy.xlsx"
    };

    final bytes = IsolateWorker.writeExcelInIsolate(params);
    expect(bytes, isNotNull);

    final cached = ExcelGenerationService.extractCachedValues(bytes!, "22_06_2026");
    print("writeExcelInIsolate generated cached values: $cached");
    
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables["22_06_2026"]!;
    print("Generated rows length: ${sheet.rows.length}");
    for (int r = 5; r <= 7; r++) {
      final rowCells = sheet.rows[r];
      final cellDetails = [];
      for (int c = 0; c < rowCells.length.clamp(0, 5); c++) {
        final cell = rowCells[c];
        cellDetails.add(cell == null ? "null" : "${cell.value} (${cell.value.runtimeType})");
      }
      print("Generated Sheet Row $r cells: $cellDetails");
    }
  });
}
