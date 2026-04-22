import 'dart:math';

class FormulaEngine {
  static dynamic evaluate(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    if (formula.isEmpty) return "";
    String f = formula.trim();
    if (f.startsWith("=")) f = f.substring(1).trim();

    if (f.startsWith("IFERROR(")) {
      final lastCommaIdx = f.lastIndexOf(",");
      final lastParenIdx = f.lastIndexOf(")");
      if (lastCommaIdx != -1 && lastParenIdx > lastCommaIdx) {
        final inner = f.substring(8, lastCommaIdx).trim();
        final fallback = f.substring(lastCommaIdx + 1, lastParenIdx).trim();
        try {
          final res = evaluate(inner, data, headers);
          if (res == "Error" || res == null) return fallback.replaceAll("\"", "");
          return res;
        } catch (e) {
          return fallback.replaceAll("\"", "");
        }
      }
    }

    try {
      return _evalRecursive(f, data, headers);
    } catch (e) {
      print("FormulaEngine: Evaluation error for '\$f': \$e");
      return "Error";
    }
  }

  static dynamic _evalRecursive(String f, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    f = f.trim();
    if (f.startsWith("SUM(")) return _sum(f, data, headers);
    if (f.startsWith("SUMIF(")) return _sumif(f, data, headers);
    if (f.startsWith("COUNT(")) {
      if (f.contains("FILTER(")) return _countFilter(f, data, headers);
      return _count(f, data, headers);
    }
    if (f.startsWith("COUNTIF(")) return _countif(f, data, headers);
    if (f.startsWith("COUNTA(")) return _counta(f, data, headers);
    if (f.startsWith("ROUND(")) return _round(f, data, headers);
    if (f.startsWith("ROWS(UNIQUE(")) return _rowsUnique(f, data, headers);
    
    final numVal = double.tryParse(f.replaceAll(',', ''));
    if (numVal != null) return numVal;
    
    return f;
  }

  static String _getActualKey(String colName, List<Map<String, dynamic>> data, List<dynamic>? headers) {
    if (data.isEmpty) return colName;
    final firstRow = data.first;
    final normalizedSearch = colName.trim().toLowerCase();
    
    if (firstRow.containsKey(colName)) return colName;
    
    for (var k in firstRow.keys) {
      if (k.trim().toLowerCase() == normalizedSearch) return k;
    }

    if (headers != null) {
      for (var h in headers) {
        if (h.toString().trim().toLowerCase() == normalizedSearch) {
           int idx = headers.indexOf(h);
           if (idx >= 0 && idx < firstRow.keys.length) return firstRow.keys.elementAt(idx);
        }
      }
    }
    return colName;
  }

  static String? _extractColumn(String part) {
    final regex = RegExp(r"\$([^$.(),=<>:!]+)(?:\.START|\.END|(?=[,=\s)<>:]|\$))");
    final match = regex.firstMatch(part);
    return match?.group(1)?.trim();
  }

  static String? _extractFunctionContent(String f, String funcName) {
    int start = f.indexOf("$funcName(") + funcName.length + 1;
    if (start < 1) return null;
    
    int level = 1;
    for (int i = start; i < f.length; i++) {
      if (f[i] == '(') level++;
      if (f[i] == ')') level--;
      if (level == 0) return f.substring(start, i);
    }
    return null;
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
    final content = _extractFunctionContent(formula, "SUMIF");
    if (content == null) return 0;
    final args = _splitArguments(content);
    if (args.length < 2) return 0;

    final rangeCol = _extractColumn(args[0]);
    final criteria = args[1].replaceAll("\"", "").trim().toLowerCase();
    final sumCol = args.length > 2 ? _extractColumn(args[2]) : rangeCol;

    if (rangeCol == null || data.isEmpty) return 0;
    final rangeKey = _getActualKey(rangeCol, data, headers);
    final sumKey = sumCol != null ? _getActualKey(sumCol, data, headers) : rangeKey;

    double total = 0;
    int matches = 0;
    for (var row in data) {
      final checkVal = row[rangeKey]?.toString().trim().toLowerCase() ?? "";
      if (checkVal == criteria) {
        matches++;
        final val = row[sumKey];
        String cleaned = val?.toString().replaceAll(',', '').trim() ?? '0';
        total += double.tryParse(cleaned) ?? 0;
      }
    }
    print("FormulaEngine: SUMIF rangeKey='\$rangeKey', criteria='\$criteria', matches=\$matches, total=\$total");
    return total;
  }

  static int _countif(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final content = _extractFunctionContent(formula, "COUNTIF");
    if (content == null) return 0;
    final args = _splitArguments(content);
    if (args.length < 2) return 0;

    final rangeCol = _extractColumn(args[0]);
    final criteria = args[1].replaceAll("\"", "").trim().toLowerCase();
    if (rangeCol == null || data.isEmpty) return 0;

    final rangeKey = _getActualKey(rangeCol, data, headers);
    
    int matches = 0;
    if (criteria == "*") {
      matches = data.where((row) => row[rangeKey] != null && row[rangeKey].toString().trim().isNotEmpty).length;
    } else {
      matches = data.where((row) => row[rangeKey]?.toString().trim().toLowerCase() == criteria).length;
    }
    print("FormulaEngine: COUNTIF rangeKey='\$rangeKey', criteria='\$criteria', matches=\$matches");
    return matches;
  }

  static int _countFilter(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    final content = _extractFunctionContent(formula, "FILTER");
    if (content == null) return 0;
    final fArgs = _splitArguments(content);
    if (fArgs.length < 2) return 0;

    final targetCol = _extractColumn(fArgs[0]);
    final condition = fArgs[1];
    
    if (targetCol == null || data.isEmpty) return 0;
    final targetKey = _getActualKey(targetCol, data, headers);
    
    int count = 0;
    for (var row in data) {
      if (_evaluateCondition(condition, row, data, headers)) {
        final val = row[targetKey]?.toString() ?? "";
        if (val.isNotEmpty) count++;
      }
    }
    print("FormulaEngine: COUNT(FILTER) targetKey='\$targetKey', condition='\$condition', count=\$count");
    return count;
  }

  static int _rowsUnique(String formula, List<Map<String, dynamic>> data, [List<dynamic>? headers]) {
    if (data.isEmpty) return 0;
    
    if (formula.contains("FILTER(")) {
      final content = _extractFunctionContent(formula, "FILTER");
      if (content != null) {
        final fArgs = _splitArguments(content);
        if (fArgs.length >= 2) {
           final targetCol = _extractColumn(fArgs[0]);
           final condition = fArgs[1];
           
           if (targetCol == null) return 0;
           final targetKey = _getActualKey(targetCol, data, headers);
           
           final Set<String> unique = {};
           for (var row in data) {
             if (_evaluateCondition(condition, row, data, headers)) {
               final val = row[targetKey]?.toString().trim() ?? "";
               if (val.isNotEmpty) unique.add(val.toLowerCase());
             }
           }
           print("FormulaEngine: ROWS(UNIQUE(FILTER)) targetKey='\$targetKey', condition='\$condition', uniqueCount=\${unique.length}");
           return unique.length;
        }
      }
    }

    final content = _extractFunctionContent(formula, "UNIQUE");
    final colName = _extractColumn(content ?? formula);
    if (colName == null) return 0;
    final actualKey = _getActualKey(colName, data, headers);
    
    final Set<String> unique = {};
    for (var row in data) {
      final val = row[actualKey]?.toString().trim() ?? "";
      if (val.isNotEmpty) unique.add(val.toLowerCase());
    }
    print("FormulaEngine: ROWS(UNIQUE) actualKey='\$actualKey', uniqueCount=\${unique.length}");
    return unique.length;
  }

  static bool _evaluateCondition(String condition, Map<String, dynamic> row, List<Map<String, dynamic>> data, List<dynamic>? headers) {
    String op = "=";
    if (condition.contains("<>")) op = "<>";
    else if (condition.contains(">=")) op = ">=";
    else if (condition.contains("<=")) op = "<=";
    else if (condition.contains(">")) op = ">";
    else if (condition.contains("<")) op = "<";

    final parts = condition.split(op);
    if (parts.length != 2) return false;

    final leftStr = parts[0].trim();
    final rightStr = parts[1].trim();
    
    final leftCol = _extractColumn(leftStr);
    final rightCol = _extractColumn(rightStr);
    
    dynamic leftVal;
    if (leftCol != null) {
      leftVal = row[_getActualKey(leftCol, data, headers)]?.toString().trim().toLowerCase() ?? "";
    } else {
      leftVal = leftStr.replaceAll("\"", "").trim().toLowerCase();
    }
    
    dynamic rightVal;
    if (rightCol != null) {
      rightVal = row[_getActualKey(rightCol, data, headers)]?.toString().trim().toLowerCase() ?? "";
    } else {
      rightVal = rightStr.replaceAll("\"", "").trim().toLowerCase();
    }
    
    bool result = false;
    switch (op) {
      case "=": result = leftVal == rightVal; break;
      case "<>": result = leftVal != rightVal; break;
      case ">=": result = _compare(leftVal, rightVal) >= 0; break;
      case "<=": result = _compare(leftVal, rightVal) <= 0; break;
      case ">": result = _compare(leftVal, rightVal) > 0; break;
      case "<": result = _compare(leftVal, rightVal) < 0; break;
      default: result = leftVal == rightVal;
    }
    return result;
  }

  static int _compare(dynamic v1, dynamic v2) {
    final n1 = double.tryParse(v1.toString());
    final n2 = double.tryParse(v2.toString());
    if (n1 != null && n2 != null) return n1.compareTo(n2);
    return v1.toString().compareTo(v2.toString());
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
    final content = _extractFunctionContent(formula, "ROUND");
    if (content == null) return 0;
    final args = _splitArguments(content);
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
}

void main() {
  final data = [
    {"Card Number": "1", "Sex": "Male", "Mode": "Cash", "Paid": "100", "Registered On": "2026-03-13", "Date": "2026-03-13", "Charges": "100", "Discount": "0"},
    {"Card Number": "2", "Sex": "Female", "Mode": "UPI", "Paid": "200", "Registered On": "2026-03-12", "Date": "2026-03-13", "Charges": "200", "Discount": "0"},
    {"Card Number": "3", "Sex": "Male", "Mode": "Cash", "Paid": "300", "Registered On": "2026-03-13", "Date": "2026-03-13", "Charges": "300", "Discount": "0"},
  ];
  
  final f1 = 'SUMIF(\$Mode.START:\$Mode.END, "Cash", \$Paid.START:\$Paid.END)';
  final r1 = FormulaEngine.evaluate(f1, data);
  print("f1 (SUMIF Cash) -> \$r1");
  
  final f2 = 'IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END,\$Sex.START:\$Sex.END="Male"))),0)';
  final r2 = FormulaEngine.evaluate(f2, data);
  print("f2 (Male) -> \$r2");

  final f3 = 'IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END,\$Sex.START:\$Sex.END="Female"))),0)';
  final r3 = FormulaEngine.evaluate(f3, data);
  print("f3 (Female) -> \$r3");
  
  final f4 = 'COUNTIF(\$Mode.START:\$Mode.END, "Cash")';
  final r4 = FormulaEngine.evaluate(f4, data);
  print("f4 (COUNTIF Cash) -> \$r4");

  final f5 = 'IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END,\$Registered On.START:\$Registered On.END=\$Date.START))),0)';
  final r5 = FormulaEngine.evaluate(f5, data);
  print("f5 (New Patients) -> \$r5");
}
