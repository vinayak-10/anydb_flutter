import 'package:excel/excel.dart';

class CellHelper {
  /// Unwraps an excel CellValue into a raw Dart type (num, String, bool, etc.)
  static dynamic unwrap(dynamic val) {
    if (val == null) return "";
    if (val is num) return val;
    if (val is String) return val;
    if (val is bool) return val;

    if (val is TextCellValue) return val.value.toString();
    if (val is DoubleCellValue) return val.value;
    if (val is IntCellValue) return val.value;
    if (val is FormulaCellValue) return val.formula;
    if (val is BoolCellValue) return val.value;
    if (val is DateCellValue) return val.toString();

    if (val is List) {
      if (val.isEmpty) return "";
      if (val.length == 1) return unwrap(val.first);
      return val.map((e) => unwrap(e)).join(', ');
    }

    // Try to access .value via reflection-like dynamic if it's some other CellValue type
    try {
      return (val as dynamic).value;
    } catch (e) {
      return val.toString();
    }
  }
}
