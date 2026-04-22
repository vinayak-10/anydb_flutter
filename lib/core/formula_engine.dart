import 'dart:math';

class FormulaEngine {
  /// Evaluates a formula based on provided data rows.
  static dynamic evaluate(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    if (formula.isEmpty) return "";
    String f = formula.trim();
    if (f.startsWith("=")) f = f.substring(1).trim();

    // Remove outer IFERROR if present
    if (f.startsWith("IFERROR(")) {
      final inner = f.substring(8, f.lastIndexOf(","));
      final fallback = f.substring(f.lastIndexOf(",") + 1, f.lastIndexOf(")")).trim();
      try {
        return _evalRecursive(inner, data, headers);
      } catch (e) {
        return fallback.replaceAll("\"", "");
      }
    }

    try {
      return _evalRecursive(f, data, headers);
    } catch (e) {
      return "Error";
    }
  }

  static dynamic _evalRecursive(String f, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    f = f.trim();
    if (f.startsWith("SUM(")) return _sum(f, data, headers);
    if (f.startsWith("SUMIF(")) return _sumif(f, data, headers);
    if (f.startsWith("COUNT(")) return _count(f, data, headers);
    if (f.startsWith("COUNTIF(")) return _countif(f, data, headers);
    if (f.startsWith("COUNTA(")) return _counta(f, data, headers);
    if (f.startsWith("ROUND(")) return _round(f, data, headers);
    if (f.startsWith("ROWS(UNIQUE(")) return _rowsUnique(f, data, headers);
    
    // Check if it's just a raw number
    final numVal = double.tryParse(f);
    if (numVal != null) return numVal;
    
    return f; // Return as string
  }

  static String _getActualKey(String colName, List<Map<String, dynamic>> data, List<dynamic>? headers) {
    if (data.isEmpty) return colName;
    final firstRow = data.first;
    
    // 1. Try exact match
    if (firstRow.containsKey(colName)) return colName;
    
    // 2. Try case-insensitive match from data keys
    for (var k in firstRow.keys) {
      if (k.toLowerCase() == colName.toLowerCase()) return k;
    }

    // 3. Try to match from original headers (if they differ from keys)
    if (headers != null) {
      for (var h in headers) {
        if (h.toString().toLowerCase() == colName.toLowerCase()) {
           // Find which key in the data row corresponds to this header index
           int idx = headers.indexOf(h);
           if (idx < firstRow.keys.length) return firstRow.keys.elementAt(idx);
        }
      }
    }
    
    return colName;
  }

  static String? _extractColumn(String part) {
    // Regex to find $ColumnName.START or $ColumnName.END
    final regex = RegExp(r"\$(.*?)\.(START|END)");
    final match = regex.firstMatch(part);
    return match?.group(1);
  }

  static double _sum(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data, headers);
    
    double total = 0;
    for (var row in data) {
      final val = row[actualKey];
      if (val != null) {
        String cleaned = val.toString().replaceAll(',', '').trim();
        total += double.tryParse(cleaned) ?? 0;
      }
    }
    return total;
  }

  static double _sumif(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // SUMIF(range, criteria, [sum_range])
    final argsContent = formula.substring(6, formula.lastIndexOf(")"));
    final args = _splitArguments(argsContent);
    if (args.length < 2) return 0;

    final rangeCol = _extractColumn(args[0]);
    final criteria = args[1].replaceAll("\"", "").trim();
    final sumCol = args.length > 2 ? _extractColumn(args[2]) : rangeCol;

    if (rangeCol == null || data.isEmpty) return 0;
    
    final rangeKey = _getActualKey(rangeCol, data, headers);
    final sumKey = sumCol != null ? _getActualKey(sumCol, data, headers) : rangeKey;

    double total = 0;
    for (var row in data) {
      final checkVal = row[rangeKey]?.toString() ?? "";
      if (checkVal == criteria) {
        final val = row[sumKey];
        String cleaned = val?.toString().replaceAll(',', '').trim() ?? '0';
        total += double.tryParse(cleaned) ?? 0;
      }
    }
    return total;
  }

  static int _countif(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // COUNTIF(range, criteria)
    final argsContent = formula.substring(8, formula.lastIndexOf(")"));
    final args = _splitArguments(argsContent);
    if (args.length < 2) return 0;

    final rangeCol = _extractColumn(args[0]);
    final criteria = args[1].replaceAll("\"", "").trim();
    if (rangeCol == null || data.isEmpty) return 0;

    final rangeKey = _getActualKey(rangeCol, data, headers);
    
    if (criteria == "*") {
      return data.where((row) => row[rangeKey] != null && row[rangeKey].toString().trim().isNotEmpty).length;
    }

    return data.where((row) => row[rangeKey]?.toString() == criteria).length;
  }

  static int _rowsUnique(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // Complex implementation for ROWS(UNIQUE(FILTER(range, condition)))
    if (data.isEmpty) return 0;
    
    // Check if it's a filtered unique count
    if (formula.contains("FILTER(")) {
      final filterPart = formula.substring(formula.indexOf("FILTER(") + 7, formula.lastIndexOf(")"));
      final fArgs = _splitArguments(filterPart);
      if (fArgs.length >= 2) {
         final targetCol = _extractColumn(fArgs[0]);
         final condition = fArgs[1]; // e.g. $Sex.START:$Sex.END=\"Male\"
         
         if (targetCol == null) return 0;
         final targetKey = _getActualKey(targetCol, data, headers);
         
         // Parse condition
         final condParts = condition.split("=");
         if (condParts.length == 2) {
            final condCol = _extractColumn(condParts[0]);
            final condVal = condParts[1].replaceAll("\"", "").trim();
            if (condCol != null) {
               final condKey = _getActualKey(condCol, data, headers);
               final Set<String> unique = {};
               for (var row in data) {
                 if (row[condKey]?.toString() == condVal) {
                   final val = row[targetKey]?.toString() ?? "";
                   if (val.isNotEmpty) unique.add(val);
                 }
               }
               return unique.length;
            }
         }
      }
    }

    // Simple unique count: ROWS(UNIQUE($Range))
    final colName = _extractColumn(formula);
    if (colName == null) return 0;
    final actualKey = _getActualKey(colName, data, headers);
    
    final Set<String> unique = {};
    for (var row in data) {
      final val = row[actualKey]?.toString() ?? "";
      if (val.isNotEmpty) unique.add(val);
    }
    return unique.length;
  }

  static int _count(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data, headers);
    
    return data.where((row) {
      final val = row[actualKey];
      if (val == null) return false;
      return double.tryParse(val.toString().replaceAll(',', '')) != null;
    }).length;
  }

  static int _counta(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data, headers);
    return data.where((row) => row[actualKey] != null && row[actualKey].toString().trim().isNotEmpty).length;
  }

  static dynamic _round(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // ROUND(number, digits)
    final argsContent = formula.substring(6, formula.lastIndexOf(")"));
    final args = _splitArguments(argsContent);
    if (args.length < 2) return 0;

    final value = double.tryParse(_evalRecursive(args[0], data, headers).toString()) ?? 0.0;
    final digits = int.tryParse(args[1]) ?? 0;
    
    num mod = pow(10.0, digits);
    return ((value * mod).round().toDouble() / mod);
  }

  static List<String> _splitArguments(String args) {
    List<String> result = [];
    int bracketLevel = 0;
    int start = 0;
    for (int i = 0; i < args.length; i++) {
      if (args[i] == '(') bracketLevel++;
      if (args[i] == ')') bracketLevel--;
      if (args[i] == ',' && bracketLevel == 0) {
        result.add(args.substring(start, i).trim());
        start = i + 1;
      }
    }
    result.add(args.substring(start).trim());
    return result;
  }

  static String? formulate(String formula, List<dynamic>? headers, int startRow, int endRow, {String? sheetName, int startColOffset = 0}) {
    if (headers == null || headers.isEmpty) return formula;

    String getColumnOf(String colName) {
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].toString().toLowerCase() == colName.toLowerCase()) {
          int colIdx = i + startColOffset;
          String columnLetter = "";
          while (colIdx >= 0) {
            columnLetter = String.fromCharCode((colIdx % 26) + 65) + columnLetter;
            colIdx = (colIdx ~/ 26) - 1;
          }
          return columnLetter;
        }
      }
      return "";
    }

    final regex = RegExp(r"\$(.*?)(\.START|\.END)");
    String result = formula;
    
    final matches = regex.allMatches(formula).toList().reversed;
    for (final match in matches) {
      final colName = match.group(1)!;
      final suffix = match.group(2)!;
      
      String columnLetter = getColumnOf(colName);
      if (columnLetter.isNotEmpty) {
        // Excel formulas in a sheet don't need the sheet prefix for internal references
        String excelRef = "$columnLetter${suffix == ".START" ? startRow : endRow}";
        result = result.replaceRange(match.start, match.end, excelRef);
      }
    }
    
    return result;
  }
}
