import 'workbook_service.dart';

class AggregatorReport {
  late String key;
  late List<dynamic> header;
  late Map<String, dynamic> summary;
  
  void init(Map<String, dynamic> jo) {
    key = jo['name'] ?? '';
    header = _prepareHeader(jo['header'] ?? {});
    summary = _prepareSummary(jo['summary'] ?? []);
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

  void init(Map<String, dynamic> jo) {
    key = jo['name'] ?? '';
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

  Future<String> generateReport(String reportName, Map<String, dynamic> data) async {
    final report = reports.firstWhere((r) => r.key == reportName);
    
    final meta = {
      'aggregator': key,
      'collection': key, // Simplified for now
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
