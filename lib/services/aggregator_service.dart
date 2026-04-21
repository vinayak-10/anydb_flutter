import 'workbook_service.dart';
import 'extractor_service.dart';
import '../core/formula_engine.dart';

class AggregatorReport {
  late String key;
  late List<dynamic> header;
  late Map<String, dynamic> summary;
  late List<dynamic> rows;
  final List<ExtractorService> extractors = [];
  
  void init(Map<String, dynamic> jo) {
    key = jo['name'] ?? '';
    header = _prepareHeader(jo['header'] ?? {});
    summary = _prepareSummary(jo['summary'] ?? []);
    rows = jo['row'] ?? [];

    extractors.clear();
    for (var row in rows) {
      final ext = ExtractorService();
      ext.init(Map<String, dynamic>.from(row));
      extractors.add(ext);
    }
  }

  List<String> getColumns() {
    if (rows.isEmpty) return [];
    final firstRow = rows[0];
    final cols = firstRow['columns'] as List<dynamic>? ?? [];
    return cols.map((c) => c is Map ? c['title'].toString() : c.toString()).toList();
  }

  Future<Map<String, dynamic>> generate({dynamic date, required WorkbookService workbook}) async {
    if (extractors.isEmpty) return {'data': [], 'extra': {}};
    
    final rowSchema = rows[0];
    final predicates = rowSchema['predicates'] as List<dynamic>? ?? [];
    
    Map<String, dynamic> result = {'data': [], 'extra': {}};
    dynamic currentData = date;

    // Apply ALL predicates in sequence
    for (var pred in predicates) {
      result = await extractors[0].generate(pred, data: currentData);
      currentData = result['data']; // Result of one predicate is input for next
    }
    
    // Calculate Summary values using FormulaEngine
    final List<Map<String, dynamic>> records = List<Map<String, dynamic>>.from(result['data'] ?? []);
    final Map<String, dynamic> calculatedSummary = {};
    summary.forEach((title, formula) {
      calculatedSummary[title] = FormulaEngine.evaluate(formula.toString(), records);
    });

    return {
      'meta': {
        'collection': key,
        'entry': result['extra']['name'],
        'predicate': result['extra']['predicate'],
      },
      'data': {
        'name': key,
        'header': [...header, ...result['extra']['header']],
        'records': records,
        'summary': calculatedSummary,
      }
    };
  }

  Future<String> generateWorkbook({dynamic date, required WorkbookService workbook}) async {
    final reportData = await generate(date: date, workbook: workbook);
    final meta = {
      'aggregator': key,
      'collection': key,
      'entry': reportData['meta']['entry'],
    };
    
    return await workbook.write(meta, reportData['data']);
  }

  List<dynamic> _prepareHeader(dynamic h) {
    if (h is List) return h;
    if (h is Map) {
      return [
        [h['title']?.toString() ?? ''],
        [h['subtitle']?.toString() ?? '']
      ];
    }
    return [];
  }

  Map<String, dynamic> _prepareSummary(dynamic s) {
    final Map<String, dynamic> result = {};
    if (s is List) {
      for (var item in s) {
        if (item is Map) {
          result[item['title']] = item['formula'];
        }
      }
    }
    return result;
  }
}

class AggregatorService {
  late String key;
  final List<AggregatorReport> reports = [];
  final WorkbookService _workbook = WorkbookService();
  late List<dynamic> share;

  String? get lastReportPath => _workbook.lastReportPath;
  Future<void> openReport([String? path]) => _workbook.openReport(path);

  void init(Map<String, dynamic> jo) {
    key = jo['name'] ?? '';
    share = jo['share'] ?? [];
    final rawSchema = jo['schema'];
    List<dynamic>? schema;
    if (rawSchema is List) {
      schema = rawSchema;
    } else if (rawSchema is Map) {
      schema = [rawSchema];
    }
    
    reports.clear();
    if (schema != null) {
      for (var element in schema) {
        if (element['type'] == 'report') {
          final report = AggregatorReport();
          report.init(element);
          reports.add(report);
        }
      }
    }
  }

  Future<Map<String, dynamic>> generate(AggregatorReport report, {dynamic date}) async {
    return await report.generate(date: date, workbook: _workbook);
  }

  Future<String> generateWorkbook(AggregatorReport report, {dynamic date}) async {
    return await report.generateWorkbook(date: date, workbook: _workbook);
  }

  Future<String> generateReport(String reportName, Map<String, dynamic> data) async {
    final report = reports.firstWhere((r) => r.key == reportName);
    
    final meta = {
      'aggregator': key,
      'collection': key,
      'entry': reportName,
    };

    final reportData = {
      'name': report.key,
      'header': report.header,
      'data': data['records'] ?? [],
      'summary': report.summary,
    };

    return await _workbook.write(meta, reportData);
  }
}
