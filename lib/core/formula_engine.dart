import 'dart:math';

class FormulaEngine {
  /// Evaluates a formula based on provided data rows.
  static dynamic evaluate(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    if (formula.isEmpty) return "";
    
    // Normalize formula: remove outer IFERROR if present
    if (formula.startsWith("IFERROR(")) {
      final inner = formula.substring(8, formula.lastIndexOf(","));
      final fallback = formula.substring(formula.lastIndexOf(",") + 1, formula.lastIndexOf(")")).trim();
      try {
        return evaluate(inner, data, headers);
      } catch (e) {
        return fallback.replaceAll("\"", "");
      }
    }

    try {
      if (formula.startsWith("SUM(")) {
        return _sum(formula, data, headers);
      } else if (formula.startsWith("SUMIF(")) {
        return _sumif(formula, data, headers);
      } else if (formula.startsWith("COUNT(")) {
        return _count(formula, data, headers);
      } else if (formula.startsWith("COUNTIF(")) {
        return _countif(formula, data, headers);
      } else if (formula.startsWith("COUNTA(")) {
        return _counta(formula, data, headers);
      } else if (formula.startsWith("ROUND(")) {
        return _round(formula, data, headers);
      } else if (formula.startsWith("ROWS(UNIQUE(")) {
        return _rowsUnique(formula, data, headers);
      }
      
      // Fallback for simple string/numeric formulas
      return formula;
    } catch (e) {
      return "Error";
    }
  }

  static String _getActualKey(String colName, Map<String, dynamic> firstRow, List<dynamic>? headers) {
    if (firstRow.containsKey(colName)) return colName;
    if (headers != null) {
      for (var h in headers) {
        final hs = h.toString();
        if (hs.toLowerCase() == colName.toLowerCase() || hs.toLowerCase().startsWith("${colName.toLowerCase()} ")) {
          return hs;
        }
      }
    }
    for (var k in firstRow.keys) {
      if (k.toLowerCase() == colName.toLowerCase() || k.toLowerCase().startsWith("${colName.toLowerCase()} ")) {
        return k;
      }
    }
    return colName;
  }

  static String? _extractColumn(String part) {
    final start = part.indexOf("\$");
    if (start == -1) return null;
    final end = part.indexOf(".", start);
    if (end == -1) return null;
    return part.substring(start + 1, end);
  }

  static double _sum(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data.first, headers);
    
    double total = 0;
    for (var row in data) {
      final val = row[actualKey];
      if (val != null) {
        total += double.tryParse(val.toString().replaceAll(',', '')) ?? 0;
      }
    }
    return total;
  }

  static double _sumif(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // Format: SUMIF(criteria_range, criteria, sum_range)
    final parts = _splitArguments(formula.substring(6, formula.lastIndexOf(")")));
    if (parts.length < 2) return 0;

    final criteriaCol = _extractColumn(parts[0]);
    final criteria = parts[1].replaceAll("\"", "").trim();
    final sumCol = parts.length > 2 ? _extractColumn(parts[2]) : criteriaCol;

    if (criteriaCol == null || data.isEmpty) return 0;
    final actualCriteriaKey = _getActualKey(criteriaCol, data.first, headers);
    final actualSumKey = sumCol != null ? _getActualKey(sumCol, data.first, headers) : actualCriteriaKey;

    double total = 0;
    for (var row in data) {
      if (row[actualCriteriaKey]?.toString() == criteria) {
        final val = row[actualSumKey];
        total += double.tryParse(val?.toString().replaceAll(',', '') ?? '0') ?? 0;
      }
    }
    return total;
  }

  static int _countif(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // Format: COUNTIF(range, criteria)
    final parts = _splitArguments(formula.substring(8, formula.lastIndexOf(")")));
    if (parts.length < 2) return 0;

    final colName = _extractColumn(parts[0]);
    final criteria = parts[1].replaceAll("\"", "").trim();
    if (colName == null || data.isEmpty) return 0;

    final actualKey = _getActualKey(colName, data.first, headers);
    if (criteria == "*") return data.where((row) => row[actualKey] != null && row[actualKey].toString().isNotEmpty).length;

    return data.where((row) => row[actualKey]?.toString() == criteria).length;
  }

  static int _rowsUnique(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    // Simple implementation for ROWS(UNIQUE(FILTER(...))) or ROWS(UNIQUE($Col...))
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data.first, headers);

    // If there is a FILTER(...) with a condition like $Sex=\"Male\"
    String? filterVal;
    String? filterKey;
    if (formula.contains("=")) {
      final filterPart = formula.substring(formula.indexOf("FILTER(") + 7, formula.lastIndexOf(")"));
      final fArgs = _splitArguments(filterPart);
      if (fArgs.length > 1 && fArgs[1].contains("=")) {
        final fEq = fArgs[1].split("=");
        filterKey = _getActualKey(_extractColumn(fEq[0]) ?? "", data.first, headers);
        filterVal = fEq[1].replaceAll("\"", "").trim();
      }
    }

    final Set<String> uniqueValues = {};
    for (var row in data) {
      if (filterKey == null || row[filterKey]?.toString() == filterVal) {
        final val = row[actualKey]?.toString();
        if (val != null && val.isNotEmpty) uniqueValues.add(val);
      }
    }
    return uniqueValues.length;
  }

  static int _count(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data.first, headers);
    return data.where((row) => row[actualKey] != null && double.tryParse(row[actualKey].toString()) != null).length;
  }

  static int _counta(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final colName = _extractColumn(formula);
    if (colName == null || data.isEmpty) return 0;
    final actualKey = _getActualKey(colName, data.first, headers);
    return data.where((row) => row[actualKey] != null && row[actualKey].toString().isNotEmpty).length;
  }

  static double _round(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final innerContent = formula.substring(6, formula.lastIndexOf(")"));
    final parts = _splitArguments(innerContent);
    if (parts.length < 2) return 0;

    final value = double.tryParse(evaluate(parts[0], data, headers).toString()) ?? 0.0;
    final precision = int.tryParse(parts[1]) ?? 0;
    num mod = pow(10.0, precision);
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
        if (headers[i].toString() == colName) {
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
        String sheetPrefix = sheetName != null ? "'$sheetName'!" : "";
        String excelRef = "$sheetPrefix$columnLetter${suffix == ".START" ? startRow : endRow}";
        result = result.replaceRange(match.start, match.end, excelRef);
      }
    }
    
    return result;
  }
}
