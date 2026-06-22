import 'dart:math';
import 'package:flutter/foundation.dart';
import 'ast.dart';

class Evaluator implements ExpressionVisitor<dynamic> {
  final List<Map<String, dynamic>> data;
  final List<dynamic>? headers;
  final Map<String, String>? titleToKeyMap;
  Map<String, dynamic>? _currentRow;

  Evaluator(this.data, [this.headers, this.titleToKeyMap]);

  dynamic evaluate(Expression expression) {
    return expression.accept(this);
  }

  @override
  dynamic visitBinary(BinaryExpression node) {
    final left = node.left.accept(this);
    final right = node.right.accept(this);

    switch (node.operator) {
      case '+':
        return _toNum(left) + _toNum(right);
      case '-':
        return _toNum(left) - _toNum(right);
      case '*':
        return _toNum(left) * _toNum(right);
      case '/':
        return _toNum(left) / _toNum(right);
      case '=':
        return _compare(left, right) == 0;
      case '<>':
        return _compare(left, right) != 0;
      case '>':
        return _compare(left, right) > 0;
      case '>=':
        return _compare(left, right) >= 0;
      case '<':
        return _compare(left, right) < 0;
      case '<=':
        return _compare(left, right) <= 0;
      default:
        throw Exception("Unknown operator ${node.operator}");
    }
  }

  @override
  dynamic visitUnary(UnaryExpression node) {
    final right = node.right.accept(this);
    switch (node.operator) {
      case '-':
        return -_toNum(right);
      case '+':
        return _toNum(right);
      default:
        throw Exception("Unknown unary operator ${node.operator}");
    }
  }

  @override
  dynamic visitLiteral(LiteralExpression node) => node.value;

  @override
  dynamic visitReference(ReferenceExpression node) {
    if (_currentRow != null) {
      final key = _getActualKey(node.name);
      return _unwrap(_currentRow![key]);
    }
    // In global context, a reference behaves like a range (returns all values)
    final key = _getActualKey(node.name);
    return data.map((row) => _unwrap(row[key])).toList();
  }

  @override
  dynamic visitRange(RangeExpression node) {
    if (_currentRow != null) {
      // In row context (e.g. inside FILTER condition), Range behaves like a single value
      final key = _getActualKey(node.start.name);
      return _unwrap(_currentRow![key]);
    }
    // A range normally evaluates to a list of values across all rows
    final key = _getActualKey(node.start.name);
    return data.map((row) => _unwrap(row[key])).toList();
  }

  @override
  dynamic visitFunctionCall(FunctionCallExpression node) {
    switch (node.name) {
      case 'SUM':
        return _sum(node.arguments);
      case 'SUMIF':
        return _sumif(node.arguments);
      case 'COUNT':
        return _count(node.arguments);
      case 'COUNTIF':
        return _countif(node.arguments);
      case 'COUNTA':
        return _counta(node.arguments);
      case 'ROUND':
        return _round(node.arguments);
      case 'IFERROR':
        return _iferror(node.arguments);
      case 'FILTER':
        return _filter(node.arguments);
      case 'UNIQUE':
        return _unique(node.arguments);
      case 'ROWS':
        return _rows(node.arguments);
      default:
        throw Exception("Unknown function ${node.name}");
    }
  }

  // --- Helper Methods ---

  double _toNum(dynamic val) {
    if (val is num) {
      if (val.isNaN || val.isInfinite) return 0.0;
      return val.toDouble();
    }
    if (val == null) return 0.0;
    String s = val.toString().replaceAll(',', '').replaceAll(RegExp(r'\s+'), '').trim();
    if (s.isEmpty || s.toLowerCase() == "nan" || s.toLowerCase() == "infinity") {
      return 0.0;
    }
    
    // Extract first numeric-like sequence (optional leading minus, followed by digits and optional decimal part)
    final regex = RegExp(r'-?\d+(?:\.\d+)?');
    final match = regex.firstMatch(s);
    if (match != null) {
      final matchedStr = match.group(0)!;
      try {
        return double.tryParse(matchedStr) ?? 0.0;
      } catch (e) {
        debugPrint("Evaluator: _toNum Parse Error for '$matchedStr': $e");
        return 0.0;
      }
    }
    return 0.0;
  }

  int _compare(dynamic v1, dynamic v2) {
    if (v1 is num && v2 is num) return v1.compareTo(v2);
    try {
      final n1 = double.tryParse(v1.toString().replaceAll(',', '').trim());
      final n2 = double.tryParse(v2.toString().replaceAll(',', '').trim());
      if (n1 != null && n2 != null) return n1.compareTo(n2);
    } catch (e) {
      // fallback to string compare
    }
    return v1.toString().toLowerCase().compareTo(v2.toString().toLowerCase());
  }

  dynamic _unwrap(dynamic val) {
    if (val is List && val.isNotEmpty) return _unwrap(val.first);
    return val;
  }

  String _getActualKey(String colName) {
    // Remove .START or .END suffix if present for key lookup
    String cleanName = colName
        .replaceAll(".START", "")
        .replaceAll(".END", "")
        .trim();
    if (data.isEmpty) return cleanName;

    final firstRow = data.first;

    // Priority 1: Check titleToKeyMap translation
    if (titleToKeyMap != null) {
      final mapped = titleToKeyMap![cleanName];
      if (mapped != null) {
        if (firstRow.containsKey(mapped)) return mapped;
        final cleanMapped = mapped.trim().toLowerCase();
        for (var k in firstRow.keys) {
          if (k.trim().toLowerCase() == cleanMapped) return k;
        }
      }
    }

    // Priority 2: Perform case-insensitive raw key search
    if (firstRow.containsKey(cleanName)) return cleanName;

    final normalizedSearch = cleanName.toLowerCase();
    for (var k in firstRow.keys) {
      if (k.trim().toLowerCase() == normalizedSearch) return k;
    }

    // Priority 3: Search the headers list
    if (headers != null) {
      for (var h in headers!) {
        if (h.toString().trim().toLowerCase() == normalizedSearch) {
          int idx = headers!.indexOf(h);
          if (idx >= 0 && idx < firstRow.keys.length) {
            return firstRow.keys.elementAt(idx);
          }
        }
      }
    }
    return cleanName;
  }

  // --- Functions ---

  double _sum(List<Expression> args) {
    if (args.isEmpty) return 0;
    final val = args[0].accept(this);
    if (val is List) {
      return val.fold(0.0, (prev, element) => prev + _toNum(element));
    }
    return _toNum(val);
  }

  double _sumif(List<Expression> args) {
    if (args.length < 2) return 0;
    // args: range, criteria, [sum_range]
    final rangeExpr = args[0];
    final criteriaExpr = args[1];
    final sumRangeExpr = args.length > 2 ? args[2] : rangeExpr;

    String rangeKey = "";
    if (rangeExpr is RangeExpression)
      rangeKey = _getActualKey(rangeExpr.start.name);
    else if (rangeExpr is ReferenceExpression)
      rangeKey = _getActualKey(rangeExpr.name);

    String sumKey = "";
    if (sumRangeExpr is RangeExpression)
      sumKey = _getActualKey(sumRangeExpr.start.name);
    else if (sumRangeExpr is ReferenceExpression)
      sumKey = _getActualKey(sumRangeExpr.name);

    if (rangeKey.isEmpty) return 0;

    double total = 0;

    for (var row in data) {
      dynamic criteria;
      _currentRow = row;
      try {
        criteria = criteriaExpr.accept(this);
      } finally {
        _currentRow = null;
      }

      final checkVal = _unwrap(row[rangeKey]);
      if (_compare(checkVal, criteria) == 0) {
        total += _toNum(_unwrap(row[sumKey]));
      }
    }
    return total;
  }

  int _count(List<Expression> args) {
    if (args.isEmpty) return 0;
    final val = args[0].accept(this);
    if (val is List) {
      return val.where((v) {
        if (v == null) return false;
        return double.tryParse(v.toString().replaceAll(',', '')) != null;
      }).length;
    }
    return double.tryParse(val.toString().replaceAll(',', '')) != null ? 1 : 0;
  }

  int _countif(List<Expression> args) {
    if (args.length < 2) return 0;
    final rangeExpr = args[0];
    final criteriaExpr = args[1];

    String rangeKey = "";
    if (rangeExpr is RangeExpression)
      rangeKey = _getActualKey(rangeExpr.start.name);
    else if (rangeExpr is ReferenceExpression)
      rangeKey = _getActualKey(rangeExpr.name);

    if (rangeKey.isEmpty) return 0;

    int count = 0;
    for (var row in data) {
      dynamic criteria;
      _currentRow = row;
      try {
        criteria = criteriaExpr.accept(this);
      } finally {
        _currentRow = null;
      }

      if (criteria == "*") {
        final v = _unwrap(row[rangeKey]);
        if (v != null && v.toString().trim().isNotEmpty) {
          count++;
        }
      } else {
        final v = _unwrap(row[rangeKey]);
        if (_compare(v, criteria) == 0) {
          count++;
        }
      }
    }
    return count;
  }

  int _counta(List<Expression> args) {
    if (args.isEmpty) return 0;
    final val = args[0].accept(this);
    if (val is List) {
      return val
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .length;
    }
    return (val != null && val.toString().trim().isNotEmpty) ? 1 : 0;
  }

  dynamic _round(List<Expression> args) {
    if (args.isEmpty) return 0;
    final value = _toNum(args[0].accept(this));
    final digits = args.length > 1 ? _toNum(args[1].accept(this)).toInt() : 0;
    num mod = pow(10.0, digits);
    return ((value * mod).roundToDouble() / mod);
  }

  dynamic _iferror(List<Expression> args) {
    if (args.isEmpty) return null;
    try {
      final res = args[0].accept(this);
      if (res == "Error" || res == null) {
        return args.length > 1 ? args[1].accept(this) : null;
      }
      return res;
    } catch (e) {
      return args.length > 1 ? args[1].accept(this) : null;
    }
  }

  dynamic _filter(List<Expression> args) {
    if (args.length < 2) return [];
    // args: target_range, condition_expr
    final targetExpr = args[0];
    final conditionExpr = args[1];

    String targetKey = "";
    if (targetExpr is RangeExpression)
      targetKey = _getActualKey(targetExpr.start.name);
    else if (targetExpr is ReferenceExpression)
      targetKey = _getActualKey(targetExpr.name);

    if (targetKey.isEmpty) return [];

    List<dynamic> results = [];
    for (var row in data) {
      _currentRow = row;
      try {
        final matches = conditionExpr.accept(this);
        if (matches == true) {
          results.add(_unwrap(row[targetKey]));
        }
      } finally {
        _currentRow = null;
      }
    }
    return results;
  }

  List<dynamic> _unique(List<Expression> args) {
    if (args.isEmpty) return [];
    final val = args[0].accept(this);
    if (val is List) {
      final Set<String> unique = {};
      final List<dynamic> result = [];
      for (var item in val) {
        final s = item?.toString().trim().toLowerCase() ?? "";
        if (s.isNotEmpty && !unique.contains(s)) {
          unique.add(s);
          result.add(item);
        }
      }
      return result;
    }
    return [val];
  }

  int _rows(List<Expression> args) {
    if (args.isEmpty) return 0;
    final val = args[0].accept(this);
    if (val is List) return val.length;
    return 1;
  }
}
