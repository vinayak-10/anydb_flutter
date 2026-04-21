import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'storage_service.dart';

abstract class Extractor {
  late Map<String, dynamic> source;
  late List<dynamic> predicates;
  late List<dynamic> columns;
  
  void init(Map<String, dynamic> jsonObj) {
    source = jsonObj['source'] ?? {};
    predicates = jsonObj['predicates'] ?? [];
    columns = jsonObj['columns'] ?? [];
  }

  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data});
}

class ExtractorDatabase extends Extractor {
  final List<Map<String, dynamic>> _data = [];
  late StorageService _storage;

  @override
  void init(Map<String, dynamic> jsonObj) {
    super.init(jsonObj);
    _storage = StorageService();
  }

  Future<void> _prepareData() async {
    _data.clear();
    
    // Ensure we have at least local storage if none specified
    final storageConfig = (source['storage'] as List?) ?? [{"type": "local"}];
    await _storage.init(source['name'], storageConfig);
    
    final elements = await _storage.fetch();

    for (var element in elements) {
      try {
        if (element.isEmpty) continue;
        final recordValue = element.values.first;
        if (recordValue is! Map) continue;
        
        List<Map<String, dynamic>> flattenedRows = [];
        // Extract common fields (Patient Name, Card Number)
        Map<String, dynamic> commonData = {};
        _extractCommon(recordValue, commonData);

        // Extract history rows, passing commonData to ensure it's in every row
        _flatten(recordValue, 0, flattenedRows, commonData);
        
        for (var row in flattenedRows) {
          // Double check common details are in every transaction row
          commonData.forEach((k, v) {
            if (!row.containsKey(k) || row[k] == null || row[k] == "") row[k] = v;
          });
          _data.add(row);
        }
      } catch (e) {
        // Silently handle errors in loop as per instructions
      }
    }
    debugPrint("Extractor: Completed in session cache mode.");
  }

  void _extractCommon(Map e, Map<String, dynamic> target) {
    for (var key in e.keys) {
      final value = e[key];
      if (value is Map) {
        _extractCommon(value, target);
      } else if (value is! List) {
        target[key.toString()] = value;
      }
    }
  }

  void _flatten(Map e, int index, List<Map<String, dynamic>> results, [Map<String, dynamic>? common]) {
    void sv(int i, String k, dynamic v) {
      if (i >= results.length) {
        for (int j = results.length; j <= i; j++) {
          results.add(common != null ? Map<String, dynamic>.from(common) : {});
        }
      }
      results[i][k] = v;
    }

    for (var key in e.keys) {
      final value = e[key];
      if (value is Map) {
        if (value.isNotEmpty && value.values.first is List) {
          // Found a versioned history array (e.g. "Account": {"1.0.0": [...]})
          final history = value.values.first as List;
          for (int vi = 0; vi < history.length; vi++) {
            final tx = history[vi];
            if (tx is Map) {
              for (var tk in tx.keys) {
                sv(vi, tk.toString(), tx[tk]);
              }
            }
          }
        } else {
          _flatten(value, index, results, common);
        }
      } else if (value is! List) {
        sv(index, key.toString(), value);
      }
    }
  }

  List<Map<String, dynamic>> _filterColumns(List<Map<String, dynamic>> rows) {
    if (columns.isEmpty) return rows;
    return rows.map((row) {
      Map<String, dynamic> filtered = {};
      for (var col in columns) {
        String colName = col is Map ? col['title'].toString() : col.toString();
        // Try exact match, then case-insensitive
        if (row.containsKey(colName)) {
          filtered[colName] = row[colName];
        } else {
          final key = row.keys.firstWhere((k) => k.toLowerCase() == colName.toLowerCase(), orElse: () => "");
          filtered[colName] = key.isNotEmpty ? row[key] : "";
        }
      }
      return filtered;
    }).toList();
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    if (val is String) {
      final dt = DateTime.tryParse(val);
      if (dt != null) return dt;
      final ms = int.tryParse(val);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data}) async {
    await _prepareData();
    
    final operation = pred['operation'];
    final column = pred['column']?.toString() ?? "";
    List<Map<String, dynamic>> sourceRows = (data is List) ? List<Map<String, dynamic>>.from(data) : _data;
    
    List<Map<String, dynamic>> resultData = [];
    String name = "Report";

    if (operation == 'date') {
      final effectiveDate = data is DateTime || data is DateTimeRange ? data : DateTime.now();
      debugPrint("Extractor: Filtering by Date on column '$column' with value $effectiveDate");

      if (effectiveDate is DateTime) {
        resultData = sourceRows.where((row) {
          final val = row[column] ?? _findValueInsensitive(row, column);
          if (val == null) return false;
          DateTime? rowDate = _parseDate(val);
          if (rowDate == null) return false;
          return rowDate.day == effectiveDate.day && rowDate.month == effectiveDate.month && rowDate.year == effectiveDate.year;
        }).toList();
        name = "${pred['name']}: ${DateFormat('yyyy-MM-dd').format(effectiveDate)}";
      } else if (effectiveDate is DateTimeRange) {
        resultData = sourceRows.where((row) {
          final val = row[column] ?? _findValueInsensitive(row, column);
          if (val == null) return false;
          DateTime? rowDate = _parseDate(val);
          if (rowDate == null) return false;
          final start = DateTime(effectiveDate.start.year, effectiveDate.start.month, effectiveDate.start.day);
          final end = DateTime(effectiveDate.end.year, effectiveDate.end.month, effectiveDate.end.day, 23, 59, 59);
          return rowDate.isAfter(start.subtract(const Duration(seconds: 1))) && 
                 rowDate.isBefore(end.add(const Duration(seconds: 1)));
        }).toList();
        name = "${pred['name']}: ${DateFormat('yyyy-MM-dd').format(effectiveDate.start)} to ${DateFormat('yyyy-MM-dd').format(effectiveDate.end)}";
      }
    } else if (operation == 'sort') {
      resultData = List<Map<String, dynamic>>.from(sourceRows);
      final dir = pred['parameter']?['dir'] ?? 'asc';
      
      resultData.sort((a, b) {
        dynamic valA = a[column] ?? _findValueInsensitive(a, column);
        dynamic valB = b[column] ?? _findValueInsensitive(b, column);

        int compareValues(dynamic v1, dynamic v2) {
          if (v1 == null && v2 == null) return 0;
          if (v1 == null) return -1;
          if (v2 == null) return 1;

          DateTime? dt1 = _parseDate(v1);
          DateTime? dt2 = _parseDate(v2);
          if (dt1 != null && dt2 != null) return dt1.compareTo(dt2);
          
          if (v1 is num && v2 is num) return v1.compareTo(v2);
          return v1.toString().toLowerCase().compareTo(v2.toString().toLowerCase());
        }

        int cmp = compareValues(valA, valB);
        return dir.toString().toLowerCase() == 'desc' ? -cmp : cmp;
      });
      name = pred['name'] ?? "Sorted Report";
    } else {
      // Default / Convert / Filter operations
      resultData = sourceRows;
      name = pred['name'] ?? "Full Report";
    }

    debugPrint("Extractor: Operation '$operation' complete. Results: ${resultData.length}");

    // Final step: Only filter columns for the VERY LAST predicate in the chain
    List<Map<String, dynamic>> finalRows = resultData;
    if (operation == 'sort' || predicates.last == pred) {
       finalRows = _filterColumns(resultData);
    }

    return {
      'data': finalRows,
      'extra': {
        'name': name,
        'source': source,
        'header': [[pred['name'] ?? 'Report', name]],
        'predicate': pred,
      }
    };
  }

  dynamic _findValueInsensitive(Map<String, dynamic> row, String key) {
    if (key.isEmpty) return null;
    for (var k in row.keys) {
      if (k.toLowerCase() == key.toLowerCase()) return row[k];
    }
    return null;
  }
}

class ExtractorService {
  Extractor? _extractor;

  void init(Map<String, dynamic> rowSchema) {
    final type = rowSchema['source']?['type'];
    if (type == 'database') {
      _extractor = ExtractorDatabase();
      _extractor!.init(rowSchema);
    } else {
      _extractor = ExtractorDatabase();
      _extractor!.init(rowSchema);
    }
  }

  Future<Map<String, dynamic>> generate(Map<String, dynamic> pred, {dynamic data}) async {
    if (_extractor == null) return {'data': [], 'extra': {}};
    return await _extractor!.applyPredicate(pred, data: data);
  }
}
