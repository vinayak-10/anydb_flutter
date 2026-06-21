import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sql;

// Replicate parsing logic from isolate_worker.dart
DateTime? _parseDateStatic(dynamic val) {
  if (val == null) return null;
  if (val is DateTime) return val;
  if (val is num) {
     if (val.isNaN || val.isInfinite) return null;
     return DateTime.fromMillisecondsSinceEpoch(val.toInt());
  }
  
  final s = val.toString().trim();
  if (s.isEmpty || s.toLowerCase() == "nan") return null;

  final dt = DateTime.tryParse(s);
  if (dt != null) return dt;

  final ms = int.tryParse(s);
  if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);

  return null;
}

dynamic _findValueInsensitiveStatic(Map<dynamic, dynamic> row, String key) {
  if (key.isEmpty) return null;
  for (var k in row.keys) {
    if (k.toString().toLowerCase() == key.toLowerCase()) return row[k];
  }
  return null;
}

bool _recordMatchesDatePredicate(Map<dynamic, dynamic> record, DateTime targetDate, String searchKey, String matchType) {
  final rootVal = record[searchKey] ?? _findValueInsensitiveStatic(record, searchKey);
  if (rootVal != null) {
    final rd = _parseDateStatic(rootVal);
    if (rd != null) {
      if (matchType == 'month') {
        if (rd.month == targetDate.month && rd.year == targetDate.year) return true;
      } else {
        if (rd.day == targetDate.day && rd.month == targetDate.month && rd.year == targetDate.year) return true;
      }
    }
  }

  final account = record['Account'];
  if (account is Map && account.isNotEmpty) {
    final history = account.values.first;
    if (history is List) {
      for (var tx in history) {
        if (tx is Map) {
          final val = tx[searchKey] ?? _findValueInsensitiveStatic(tx, searchKey);
          final rd = _parseDateStatic(val);
          if (rd != null) {
            if (matchType == 'month') {
              if (rd.month == targetDate.month && rd.year == targetDate.year) return true;
            } else {
              if (rd.day == targetDate.day && rd.month == targetDate.month && rd.year == targetDate.year) return true;
            }
          }
        }
      }
    }
  }
  return false;
}

// Replicate flattening from extractor_service.dart
String _getJsonType(dynamic o) {
  if (o == null) return "null";
  if (o is List) return "array";
  if (o is bool) return "boolean";
  if (o is num) return "number";
  if (o is String) return "string";
  if (o is Map) return "object";
  return "undefined";
}

void _flatten(dynamic e, int index, List<Map<String, dynamic>> keyValues) {
  void sv(List<Map<String, dynamic>> a, int i, String k, dynamic v) {
    if (i >= a.length) {
      for (int j = a.length; j <= i; j++) {
        a.add({});
      }
    }
    a[i][k] = v;
  }

  if (e is! Map) return;
  Map tmpe = Map.from(e);

  for (var entry in tmpe.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    final typeofValue = _getJsonType(value);

    switch (typeofValue) {
      case "object":
        _flatten(value, index, keyValues);
        break;
      case "array":
        if (key.contains(':') ||
            (value is List && value.isNotEmpty && value.first is Map)) {
          for (int vi = 0; vi < value.length; vi++) {
            _flatten(value[vi], index + vi, keyValues);
          }
        } else {
          sv(keyValues, index, key, value);
        }
        break;
      default:
        sv(keyValues, index, key, value);
        break;
    }
  }
}

void main() {
  final dbPath = '/home/ruggedcoder/Documents/xyz.maya/anydb/anydb_storage.db';
  final db = sql.sqlite3.open(dbPath);
  
  final results = db.select('SELECT id, value FROM Patients');
  print('Total records in Patients table: ${results.length}');
  
  final List<Map<String, dynamic>> elements = [];
  for (var row in results) {
    final key = row['id'] as String;
    final value = jsonDecode(row['value'] as String);
    elements.add({key: value});
  }
  
  // Collect all unique transaction dates in the database
  final Set<String> allDates = {};
  for (var e in elements) {
    final rec = e.values.first as Map;
    final account = rec['Account'];
    if (account is Map && account.isNotEmpty) {
      final history = account.values.first;
      if (history is List) {
        for (var tx in history) {
          if (tx is Map) {
            final val = tx['Date'];
            final dt = _parseDateStatic(val);
            if (dt != null) {
              allDates.add('${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}');
            }
          }
        }
      }
    }
  }
  
  print('Collected ${allDates.length} unique transaction dates in the database.');
  
  int mismatchCount = 0;
  for (var dateStr in allDates) {
    final targetDate = DateTime.parse(dateStr);
    
    // 1. Run Isolate pre-filtering logic
    final filteredByPreFilter = elements.where((e) {
      final recordVal = e.values.first;
      return _recordMatchesDatePredicate(recordVal, targetDate, 'Date', 'day');
    }).toList();
    
    // 2. Run actual ExtractorDatabase flattening and date filtering logic
    final List<Map<String, dynamic>> extractedRows = [];
    for (var e in elements) {
      final recordVal = e.values.first;
      List<Map<String, dynamic>> trows = [];
      _flatten(recordVal, 0, trows);
      extractedRows.addAll(trows);
    }
    
    final predicatedRows = extractedRows.where((row) {
      final val = row['Date'] ?? _findValueInsensitiveStatic(row, 'Date');
      final rd = _parseDateStatic(val);
      return rd != null &&
          rd.day == targetDate.day &&
          rd.month == targetDate.month &&
          rd.year == targetDate.year;
    }).toList();
    
    // Check if the set of patient IDs represented in predicatedRows is a subset of filteredByPreFilter
    final Set<String> expectedIds = predicatedRows.map((r) => r['Card Number']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
    final Set<String> actualIds = filteredByPreFilter.map((e) {
      final rec = e.values.first as Map;
      final reg = rec['Registration'];
      if (reg is Map) {
        return reg['Card Number']?.toString() ?? '';
      }
      return '';
    }).where((id) => id.isNotEmpty).toSet();
    
    final missingIds = expectedIds.difference(actualIds);
    if (missingIds.isNotEmpty) {
      print('MISMATCH on date $dateStr:');
      print('  Expected patient IDs (from extractor): $expectedIds');
      print('  Actual patient IDs (from pre-filter): $actualIds');
      print('  Missing IDs: $missingIds');
      mismatchCount++;
    }
  }
  
  if (mismatchCount == 0) {
    print('SUCCESS: No filtering discrepancies found across any dates.');
  } else {
    print('FAILED: Found $mismatchCount dates with discrepancies.');
  }
  
  db.dispose();
}
