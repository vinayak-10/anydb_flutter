import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'storage_service.dart';
import 'workbook_service.dart';

// Replicates Extractor class from extractor.js
abstract class Extractor {
  late Map<String, dynamic> source;
  late List<dynamic> predicates;
  late List<dynamic> columns;
  
  void init(Map<String, dynamic> jsonObj) {
    source = jsonObj['source'] ?? {};
    predicates = jsonObj['predicates'] ?? [];
    columns = jsonObj['columns'] ?? [];
  }

  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data, dynamic getFileName});
}

class ExtractorDatabase extends Extractor {
  final List<Map<String, dynamic>> _data = [];
  final List<Map<String, dynamic>> _rows = [];
  late StorageService _storage;

  @override
  void init(Map<String, dynamic> jsonObj) {
    super.init(jsonObj);
    _storage = StorageService();
    _storage.init(source['name'] ?? "", source['storage'] ?? [{"type": "local"}]);
  }

  Future<void> reinit() async {
    return await populateRecords();
  }

  Future<void> populateRecords() async {
    _rows.clear();
    _data.clear();

    final elements = await _storage.fetch();
    debugPrint("ExtractorDatabase: Fetched ${elements.length} elements from storage.");

    // Segregate Active records only for report (Matching RN default filter)
    final activeElements = _segregate(elements, types: ["Active"]);
    debugPrint("ExtractorDatabase: Segregated ${activeElements.length} Active elements.");

    for (var element in activeElements) {
      List<Map<String, dynamic>> trows = [];
      _flatten(element, 0, trows);
      
      if (trows.isNotEmpty) {
        final refrow = trows[0];
        final keys = refrow.keys.toList();
        for (var row in trows) {
          Map<String, dynamic> sanitizedRow = Map<String, dynamic>.from(row);
          for (var key in keys) {
            if (!row.containsKey(key)) {
              sanitizedRow[key] = refrow[key];
            }
          }
          _data.add(sanitizedRow);
        }
      }
    }
    
    debugPrint("ExtractorDatabase: Flattened into ${_data.length} total rows.");
    _rows.addAll(_filter(_data, columns));
    debugPrint("ExtractorDatabase: Filtered into ${_rows.length} rows based on columns.");

    for (var p in predicates) {
      await applyPredicate(p as Map<String, dynamic>);
    }
  }

  List<Map<String, dynamic>> _segregate(List<Map<String, dynamic>> records, {List<String> types = const ["Active"]}) {
    return records.where((rec) {
      if (rec.isEmpty) return false;
      final val = rec.values.first;
      if (val is! Map) return false;
      
      final meta = val['__meta__'];
      final time = meta != null ? meta['time'] : null;
      
      bool isArchived = time != null && time.containsKey('a');
      bool isDeleted = time != null && time.containsKey('d');
      bool isActive = !isArchived && !isDeleted;

      bool match = false;
      for (var type in types) {
        if (type == "Active" && isActive) match = true;
        if (type == "Archived" && isArchived) match = true;
        if (type == "Deleted" && isDeleted) match = true;
      }
      return match;
    }).toList();
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
          if (key.split(':').length > 1) {
             for (int vi = 0; vi < value.length; vi++) {
               _flatten(value[vi], index + vi, keyValues);
             }
          } else {
             sv(keyValues, index, key, value.toString());
          }
          break;
        default:
          sv(keyValues, index, key, value);
          break;
      }
    }
  }

  String _getJsonType(dynamic o) {
    if (o == null) return "null";
    if (o is List) return "array";
    if (o is bool) return "boolean";
    if (o is num) return "number";
    if (o is String) return "string";
    if (o is Map) return "object";
    return "undefined";
  }

  // Corrected port of JS filter(rows, columns)
  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows, List<dynamic> cols) {
    if (cols.isEmpty) return List.from(rows);

    List<Map<String, dynamic>> filtered = [];
    for (var row in rows) {
      Map<String, dynamic> one = {};
      for (var column in cols) {
        final String destKey = (column is Map ? (column['title'] ?? column['column']) : column).toString();
        final String srcKey = (column is Map ? (column['column'] ?? column['title']) : column).toString();
        
        // Fetch from source key (e.g. 'Amount'), store in dest key (e.g. 'Paid Amount')
        one[destKey] = row[srcKey] ?? _findValueInsensitive(row, srcKey);
      }
      filtered.add(one);
    }
    return filtered;
  }

  @override
  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data, dynamic getFileName}) async {
    if (_rows.isEmpty) await populateRecords();
    
    final operation = pred['operation'];
    
    switch (operation) {
      case "date":
        if (data == null) return {};
        final DateTime d = data is DateTime ? data : DateTime.parse(data.toString());
        
        // Find the correct key in the already filtered _rows (usually the title)
        final String searchKey = pred['column'].toString();
        
        final predicated = _rows.where((row) {
          final rd = _parseDate(row[searchKey] ?? _findValueInsensitive(row, searchKey));
          return rd != null && rd.day == d.day && rd.month == d.month && rd.year == d.year;
        }).toList();

        debugPrint("ExtractorDatabase: Date filter ($searchKey) matched ${predicated.length} records.");

        return {
          "data": predicated,
          "extra": {
            "header": [[pred['name'], DateFormat('yyyy-MM-dd').format(d)]],
            "name": DateFormat('yyyy-MM-dd').format(d),
            "source": source,
            "predicate": {...pred, "value": d}
          }
        };

      case "generate":
        return {
          "data": List.from(_rows),
          "extra": {
            "header": [[pred['name']]],
            "name": pred['name'],
            "source": source,
            "predicate": {...pred, "value": ""}
          }
        };

      case "convert":
        if (pred['parameter']?['to'] == 'date') {
          for (var r in _rows) {
            if (r.containsKey(pred['column'])) {
              final dt = _parseDate(r[pred['column']]);
              if (dt != null) r[pred['column']] = DateFormat('yyyy-MM-dd').format(dt);
            }
          }
        }
        break;

      case "sort":
        _rows.sort((a, b) {
          final valA = a[pred['column']]?.toString() ?? "";
          final valB = b[pred['column']]?.toString() ?? "";
          return valA.compareTo(valB);
        });
        break;
    }
    return {};
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    if (val is String) {
      final dt = DateTime.tryParse(val);
      if (dt != null) return dt;
      final ms = int.tryParse(val);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return null;
  }

  dynamic _findValueInsensitive(Map<String, dynamic> row, String key) {
    if (key.isEmpty) return null;
    for (var k in row.keys) {
      if (k.toLowerCase() == key.toLowerCase()) return row[k];
    }
    return null;
  }
}

class ExtractorReport extends Extractor {
  final List<Map<String, dynamic>> _rows = [];
  final WorkbookService _workbookService = WorkbookService();

  @override
  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data, dynamic getFileName}) async {
    if (pred['operation'] == 'date') {
       if (data == null) return {};
       final DateTime date = data is DateTime ? data : DateTime.parse(data.toString());
       
       // Prepare workbook names etc using getFileName callback
       final fileMeta = getFileName != null ? getFileName({
         "extra": {
           "name": DateFormat('yyyy-MM-dd').format(date),
           "predicate": {...pred, "value": date}
         }
       }) : null;

       await _prepare(pred, date, fileMeta);

       return {
         "data": _rows,
         "extra": {
           "header": [[pred['name'], DateFormat('yyyy-MM-dd').format(date)]],
           "name": DateFormat('yyyy-MM-dd').format(date),
           "source": source,
           "predicate": {...pred, "value": date}
         }
       };
    }
    return {};
  }

  Future<void> _prepare(Map<String, dynamic> pred, DateTime date, dynamic fileMeta) async {
    _rows.clear();
    if (fileMeta == null) return;
    
    // In Flutter, WorkbookService.getSheetNames requires a file path
    final sheetNames = await _workbookService.getSheetNames(fileMeta['collection'], source['name'] ?? "");
    
    for (var sheetName in sheetNames) {
      Map<String, dynamic> row = {};
      for (var col in columns) {
        if (col is Map) {
          row[col['title']] = col['formula'].toString().replaceAll(source['name'] ?? "", sheetName);
        }
      }
      _rows.add(row);
    }
  }
}

class ExtractorIntf {
  Extractor? extractor;
  dynamic pIntf;
  bool reinited = false;

  void init(Map<String, dynamic> jo, dynamic pintf) {
    pIntf = pintf;
    final type = jo['source']?['type'];
    if (type == 'database') {
      extractor = ExtractorDatabase();
    } else if (type == 'report') {
      extractor = ExtractorReport();
    }
    extractor?.init(jo);
    reinited = false;
  }

  Future<void> reinit(bool focused) async {
    if (extractor != null) {
      bool isInited = reinited;
      reinited = focused;
      if (focused && !isInited) {
        if (extractor is ExtractorDatabase) {
           await (extractor as ExtractorDatabase).reinit();
        }
      }
    }
  }

  Future<Map<String, dynamic>> generate() async {
    await reinit(true);
    final pred = extractor?.predicates[0];
    return await extractor!.applyPredicate(
      pred, 
      data: DateTime.now(), 
      getFileName: pIntf['getFileName']
    );
  }

  String predicatedName(Map<String, dynamic> pred, String data) {
    return data;
  }
}

class ExtractorService {
  final ExtractorIntf _intf = ExtractorIntf();

  void init(Map<String, dynamic> rowSchema, {dynamic getFileName}) {
    _intf.init(rowSchema, {'getFileName': getFileName});
  }

  Future<Map<String, dynamic>> generate(Map<String, dynamic> pred, {dynamic data}) async {
    return await _intf.extractor!.applyPredicate(pred, data: data, getFileName: _intf.pIntf['getFileName']);
  }
}
