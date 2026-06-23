import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:anydb_flutter/services/excel_generation_service.dart';

void main() {
  test('Read Monthly Report test', () async {
    final path = "/home/ruggedcoder/Documents/xyz.maya/anydb/RKM_Physio/Aggregators/Monthly_Jun_2026_Sun_Jun_21_2026_12_21_38_GMT_0530.xlsx";
    final file = File(path);
    if (!file.existsSync()) {
      print("File does not exist!");
      return;
    }

    final bytes = file.readAsBytesSync();
    try {
      final rows = ExcelGenerationService.readSheetInIsolate({
        'bytes': bytes,
        'sheetName': 'Jun_2026',
      });
      print("Parsed sheet has ${rows.length} rows.");
      for (int i = 0; i < rows.length; i++) {
        print("Row $i: ${rows[i]}");
      }
    } catch (e, stack) {
      print("Error during parsing: $e");
      print(stack);
    }
  });
}
