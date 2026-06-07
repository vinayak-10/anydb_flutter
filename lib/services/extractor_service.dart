import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'storage_service.dart';
import 'workbook_service.dart';
import '../core/cell_helper.dart';
import '../core/logger.dart';

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

  String predicatedName(Map<String, dynamic> pred, String data) {
    String name = data;
    
    // Find a predicate in this extractor that can provide formatting
    // If we can't find one that's different from 'pred', we use 'pred' itself.
    final formatPreds = predicates.where((p) => p['operation'] == pred['operation']).toList();
    final p = formatPreds.firstWhere((p) => p['name'] != pred['name'], orElse: () => pred);

    if (p['operation'] == 'date') {
      try {
        DateTime? d;
        if (data.contains('-') || data.contains('/') || data.contains('T')) {
           d = DateTime.tryParse(data);
        } else {
           final ms = int.tryParse(data);
           if (ms != null) d = DateTime.fromMillisecondsSinceEpoch(ms);
        }
        d ??= DateTime.now();
        
        final type = p['parameter']?['type'];
        if (type == 'month') {
          name = DateFormat('MMM yyyy').format(d);
        } else if (type == 'day') {
          name = DateFormat('d_MMM yyyy').format(d);
        } else {
          // Default formatting if type is missing
          name = DateFormat('yyyy-MM-dd').format(d);
        }
      } catch (e) {
        debugPrint("Extractor.predicatedName Error: $e for data '$data'");
      }
    }
    return name;
  }

  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data, dynamic getFileName, DateTime? timestamp, bool force = false});
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

  void populateWithData(List<Map<String, dynamic>> elements) {
    _rows.clear();
    _data.clear();

    final allElements = _segregate(elements, types: ["Active", "Archived", "Deleted"]);
    logger.log("ExtractorDatabase Isolate: Segregated ${allElements.length} Total elements.");

    for (var element in allElements) {
      if (element.isEmpty) continue;
      final recordValue = element.values.first;
      if (recordValue is! Map) continue;

      List<Map<String, dynamic>> trows = [];
      _flatten(recordValue, 0, trows);
      
      if (trows.isNotEmpty) {
        final refrow = trows[0];
        for (var row in trows) {
          Map<String, dynamic> sanitizedRow = {};
          refrow.forEach((k, v) => sanitizedRow[k] = v);
          row.forEach((k, v) => sanitizedRow[k] = v);
          _data.add(sanitizedRow);
        }
      }
    }
    
    logger.log("ExtractorDatabase Isolate: Flattened into ${_data.length} total rows.");

    _rows.clear();
    _rows.addAll(_filter(_data, columns));

    final List<Map<String, dynamic>> workingRows = [];
    for (var r in _rows) {
      final dateVal = r['Date'] ?? _findValueInsensitive(r, 'Date');
      if (dateVal != null && dateVal.toString().isNotEmpty) {
        workingRows.add(r);
      }
    }

    if (workingRows.isNotEmpty && workingRows.length < _rows.length) {
       _rows.clear();
       _rows.addAll(workingRows);
    }
  }

  Future<void> populateRecords() async {
    _rows.clear();
    _data.clear();

    final elements = await _storage.fetch(allRecords: true);
    logger.log("ExtractorDatabase: Fetched ${elements.length} raw elements from storage.");

    // IMPORTANT: Include Active, Archived, and Deleted for report (Matching RN historical data extraction)
    // In ManyDB, we typically want ALL patient records ever created, regardless of current state.
    final allElements = _segregate(elements, types: ["Active", "Archived", "Deleted"]);
    logger.log("ExtractorDatabase: Segregated ${allElements.length} Total elements (Active/Archived/Deleted).");

    int index = 0;
    for (var element in allElements) {
      if (kIsWeb && index % 100 == 0) {
        await Future.delayed(Duration.zero);
      }
      index++;
      if (element.isEmpty) continue;
      final recordValue = element.values.first;
      if (recordValue is! Map) continue;

      List<Map<String, dynamic>> trows = [];
      _flatten(recordValue, 0, trows);
      
      if (trows.isNotEmpty) {
        final refrow = trows[0];
        for (var row in trows) {
          Map<String, dynamic> sanitizedRow = {};
          // Fill from refrow (first row of this record) to ensure common fields are present
          refrow.forEach((k, v) => sanitizedRow[k] = v);
          // Overwrite with current row specific fields
          row.forEach((k, v) => sanitizedRow[k] = v);
          
          _data.add(sanitizedRow);
        }
      }
    }
    
    logger.log("ExtractorDatabase: Flattened into ${_data.length} total rows from ${allElements.length} records.");

    // Reset _rows and populate from filtered _data
    _rows.clear();
    _rows.addAll(_filter(_data, columns));

    // SPECIAL CASE: For Daily Reports, we might only want rows that have a value for 'Date'
    // after filtering, to avoid counting placeholder records in summary.
    final List<Map<String, dynamic>> workingRows = [];
    for (var r in _rows) {
      final dateVal = r['Date'] ?? _findValueInsensitive(r, 'Date');
      if (dateVal != null && dateVal.toString().isNotEmpty) {
        workingRows.add(r);
      }
    }

    if (workingRows.isNotEmpty && workingRows.length < _rows.length) {
       logger.log("ExtractorDatabase: Refined rows to ${workingRows.length} (had date value).");
       _rows.clear();
       _rows.addAll(workingRows);
    }

    // APPLY ALL SCHEMA PREDICATES SEQUENTIALLY (Match RN logic)

    for (var p in predicates) {
      if (p is Map) {
        logger.log("ExtractorDatabase: Applying sequential predicate: ${p['operation']} (${p['name']})");
        await applyPredicate(Map<String, dynamic>.from(p));
      }
    }
    
    logger.log("ExtractorDatabase: Final population complete. Filtered Rows: ${_rows.length}");
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
          if (key.contains(':') || (value is List && value.isNotEmpty && value.first is Map)) {
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
        one[destKey] = row[srcKey] ?? _findValueInsensitive(row, srcKey);
      }
      filtered.add(one);
    }
    return filtered;
  }

  @override
  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data, dynamic getFileName, DateTime? timestamp, bool force = false}) async {
    final operation = pred['operation'];
    
    switch (operation) {
      case "date":
        final String searchKey = pred['column']?.toString() ?? "Date";
        if (data == null) {
          // If no data provided (e.g. during initial population), do not filter _rows
          return {};
        }
        
        final DateTime d = data is DateTime ? data : (DateTime.tryParse(data.toString()) ?? DateTime.now());
        // Force correct Daily sheet naming pattern: "1_Mar 2026"
        final String formattedDate = DateFormat('d_MMM yyyy').format(d);
        
        final predicated = _rows.where((row) {
          final val = row[searchKey] ?? _findValueInsensitive(row, searchKey);
          final rd = _parseDate(CellHelper.unwrap(val));
          return rd != null && rd.day == d.day && rd.month == d.month && rd.year == d.year;
        }).toList();

        logger.log("ExtractorDatabase: Date filter ($searchKey) matched ${predicated.length} records for $formattedDate.");

        // During report generation, we typically want to return the predicated subset
        // without permanently clearing _rows (which might be used for other things).
        // But for consistency with reinit(), we need a way to apply filters.
        return {
          "data": predicated,
          "extra": {
            "header": [[pred['name'], formattedDate]],
            "name": formattedDate,
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
          final colKey = pred['column'].toString();
          for (var r in _rows) {
            final val = r[colKey] ?? _findValueInsensitive(r, colKey);
            final dt = _parseDate(CellHelper.unwrap(val));
            if (dt != null) r[colKey] = DateFormat('yyyy-MM-dd').format(dt);
          }
        }
        break;

      case "sort":
        final colKey = pred['column']?.toString() ?? "";
        if (colKey.isNotEmpty) {
          _rows.sort((a, b) {
            final valA = CellHelper.unwrap(a[colKey] ?? _findValueInsensitive(a, colKey))?.toString() ?? "";
            final valB = CellHelper.unwrap(b[colKey] ?? _findValueInsensitive(b, colKey))?.toString() ?? "";
            return valA.compareTo(valB);
          });
        }
        break;
    }
    return {};
  }

  DateTime? _parseDate(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    if (val is num) {
       if (val.isNaN || val.isInfinite) return null;
       return DateTime.fromMillisecondsSinceEpoch(val.toInt());
    }
    
    final s = val.toString().trim();
    if (s.isEmpty || s.toLowerCase() == "nan") return null;

    // 1. Try ISO parsing
    final dt = DateTime.tryParse(s);
    if (dt != null) return dt;

    // 2. Try Milliseconds parsing
    final ms = int.tryParse(s);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);

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
  Future<Map<String, dynamic>> applyPredicate(Map<String, dynamic> pred, {dynamic data, dynamic getFileName, DateTime? timestamp, bool force = false}) async {
    if (pred['operation'] == 'date') {
       if (data == null) return {};
       final DateTime date = data is DateTime ? data : (DateTime.tryParse(data.toString()) ?? DateTime.now());

       final String formattedName = predicatedName(pred, date.toIso8601String());

       final fileMeta = getFileName != null ? getFileName({
         "collection": source['name'] ?? "",
         "entry": formattedName,
         "predicate": {...pred, "value": date}
       }, timestamp: timestamp) : null;

       await _prepare(pred, date, fileMeta, formattedName, timestamp: timestamp, force: force);


       return {
         "data": _rows,
         "extra": {
           "header": [[pred['name'], formattedName]],
           "name": formattedName,
           "source": source,
           "predicate": {...pred, "value": date}
         }
       };
    }
    return {};
  }

  Future<void> _prepare(Map<String, dynamic> pred, DateTime date, dynamic fileMeta, String targetSheetName, {DateTime? timestamp, bool force = false}) async {
    _rows.clear();
    if (fileMeta == null) return;
    
    // During a batch, the collection might be the aggregator name, 
    // while individual extractors might have their own source name.
    // We try to find the workbook using both, but prioritizing the passed fileMeta.
    
    final fileName = fileMeta['fileName'] ?? fileMeta['collection'];
    final sourceReportName = source['name'] ?? "";
    logger.log("ExtractorReport: Searching for source sheets '$sourceReportName' in file '$fileName' (timestamp: $timestamp)");
    
    final sheetNames = await _workbookService.getSheetNames(fileMeta, sourceReportName);
    logger.log("ExtractorReport: Found ${sheetNames.length} source sheets: $sheetNames");
    
    for (var sheetName in sheetNames) {
      logger.log("ExtractorReport: Reading source sheet '$sheetName'...");
      final List<List<dynamic>> sheetData = await _workbookService.read(fileMeta, sheetName);
      if (sheetData.isNotEmpty) {
        logger.log("ExtractorReport: Sheet '$sheetName' has ${sheetData.length} rows.");
        Map<String, dynamic> row = {};
        for (var col in columns) {
          if (col is Map) {
            final String title = col['title'].toString();
            final String formula = col['formula'].toString();
            
            // Pattern to match cell reference: 'Source'!A7 or Daily!B4
            // We handle optional single quotes around the sheet name
            final refRegex = RegExp(r"(?:'([^']+)'|([^!]+))!([A-Z]+)([0-9]+)");
            final match = refRegex.firstMatch(formula);
            
            if (match != null) {
              // Group 1 or 2 is sheet name, Group 3 is column, Group 4 is row
              final String colAlpha = match.group(3)!;
              final int? rowNum = int.tryParse(match.group(4)!);
              
              if (rowNum != null) {
                int colIdx = 0;
                for (int i = 0; i < colAlpha.length; i++) {
                  colIdx = colIdx * 26 + (colAlpha.codeUnitAt(i) - 64);
                }
                colIdx -= 1; // 0-indexed
                int rowIdx = rowNum - 1; // 0-indexed
                
                if (rowIdx < sheetData.length && colIdx < sheetData[rowIdx].length) {
                  final val = CellHelper.unwrap(sheetData[rowIdx][colIdx]);
                  row[title] = val;
                  logger.log("ExtractorReport: Sheet '$sheetName' ($colAlpha$rowNum) -> $title = $val");
                } else {
                  logger.log("ExtractorReport: Coordinate $colAlpha$rowNum out of bounds for sheet '$sheetName'");
                  row[title] = 0;
                }
                } else {
                row[title] = 0;
                }
                } else {
                // Fallback to title matching if no coordinate found
                final headers = sheetData.length > 5 ? sheetData[5] : [];
                final values = sheetData.length > 6 ? sheetData[6] : [];

                int foundIdx = -1;
                for (int i = 0; i < headers.length; i++) {
                final h = CellHelper.unwrap(headers[i]).toString().trim().toLowerCase();
                if (h == title.toLowerCase() || h == "total $title".toLowerCase()) {
                  foundIdx = i;
                  break;
                }
                }

                if (foundIdx != -1 && foundIdx < values.length) {
                row[title] = CellHelper.unwrap(values[foundIdx]);
                } else {
                row[title] = formula.replaceAll(sourceReportName, sheetName);
                }
                }

          }
        }
        _rows.add(row);
      }
    }
    debugPrint("ExtractorReport: Prepared ${_rows.length} rows for summary.");
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

  Future<void> reinit(bool focused, {bool force = false}) async {
    if (extractor != null) {
      bool isInited = reinited;
      reinited = focused;
      if (force || (focused && !isInited)) {
        if (extractor is ExtractorDatabase) {
           await (extractor as ExtractorDatabase).reinit();
        }
      }
    }
  }

  void populateWithData(List<Map<String, dynamic>> elements) {
    if (extractor is ExtractorDatabase) {
      (extractor as ExtractorDatabase).populateWithData(elements);
      reinited = true;
    }
  }

  Future<Map<String, dynamic>> generate({DateTime? timestamp}) async {
    await reinit(true);
    final pred = extractor?.predicates[0];
    return await extractor!.applyPredicate(
      pred, 
      data: DateTime.now(), 
      getFileName: pIntf['getFileName'],
      timestamp: timestamp
    );
  }

  String predicatedName(Map<String, dynamic> pred, String data) {
    if (extractor == null) return data;
    return extractor!.predicatedName(pred, data);
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
