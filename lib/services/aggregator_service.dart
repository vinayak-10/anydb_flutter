import 'workbook_service.dart';
import 'extractor_service.dart';
import '../core/formula_engine.dart';

class AggregatorReport {
  late String key;
  late List<dynamic> header;
  late Map<String, dynamic> summary;
  late List<dynamic> rows;
  final List<ExtractorIntf> extractor = [];
  dynamic pIntf;
  
  void init(Map<String, dynamic> jo, dynamic pintf) {
    key = jo['name'] ?? '';
    pIntf = pintf;
    header = jo.containsKey("header") ? _prepareHeader(jo['header']) : [];
    summary = jo.containsKey("summary") ? _prepareSummary(jo['summary']) : {};
    rows = jo['row'] as List? ?? [];

    extractor.clear();
    final rowList = jo['row'] as List? ?? [];
    for (var row in rowList) {
      final ext = ExtractorIntf();
      ext.init(Map<String, dynamic>.from(row), {
        'generate': (pd) => pIntf['generate'](generateReport(pd)),
        'getFileName': (j) => pIntf['getFileName'](generateMeta(j))
      });
      extractor.add(ext);
    }
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

  Map<String, dynamic> _prepareSummary(dynamic jos) {
    final Map<String, dynamic> summary = {};
    if (jos is List) {
      for (var s in jos) {
        if (s is Map) {
          summary[s['title']] = s['formula'];
        }
      }
    }
    return summary;
  }

  Map<String, dynamic> applyMeta(Map<String, dynamic> meta) {
    Map<String, dynamic> nmeta = Map<String, dynamic>.from(meta);
    String n = "$key ${extractor[0].predicatedName(nmeta['predicate'] ?? {}, nmeta['entry'] ?? '')}";
    nmeta['collection'] = n.replaceAll(' ', '_');
    return nmeta;
  }

  Future<Map<String, dynamic>> generate() async {
    try {
      final s = await extractor[0].generate();
      return generateReport(s);
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> generateMeta(Map<String, dynamic> j) {
    return {
      "collection": key,
      "entry": j['extra']['name'],
      "predicate": j['extra']['predicate']
    };
  }

  Map<String, dynamic> generateData(Map<String, dynamic> j) {
    final List<dynamic> rawRecords = j['data'] ?? [];
    final List<Map<String, dynamic>> records = rawRecords.map((r) {
      final Map<String, dynamic> record = Map<String, dynamic>.from(r as Map);
      return record.map((k, v) => MapEntry(k, _unwrap(v)));
    }).toList();

    final Map<String, dynamic> calculatedSummary = {};
    final List<String> dataHeaders = records.isNotEmpty ? records[0].keys.toList() : [];

    summary.forEach((title, formula) {
      calculatedSummary[title] = FormulaEngine.evaluate(formula.toString(), records, dataHeaders);
    });

    return {
      "name": key,
      "source": j['extra']['source'],
      "header": [...header, ...j['extra']['header']],
      "data": records,
      "summary": calculatedSummary,
      "summaryFormulas": summary, // Keep original formulas for Workbook
    };
  }

  dynamic _unwrap(dynamic val) {
    if (val is List && val.isNotEmpty) return _unwrap(val.first);
    return val;
  }

  Map<String, dynamic> generateReport(Map<String, dynamic> j) {
    return {
      "meta": generateMeta(j),
      "data": generateData(j)
    };
  }

  List<String> getColumns() {
    // Ported helper for UI
    if (extractor.isEmpty) return [];
    final firstExt = extractor[0];
    final cols = firstExt.extractor?.columns ?? [];
    return cols.map((c) => c is Map ? c['title'].toString() : c.toString()).toList();
  }
}

class AggregatorService {
  late String key;
  final List<AggregatorReport> reports = [];
  final WorkbookService workbook = WorkbookService();
  late Map<String, dynamic> share;
  String? reportPath;

  String? get lastReportPath => workbook.lastReportPath;

  void init(dynamic jo) {
    if (jo == null) return;
    
    if (jo is Map) {
      key = jo['name'] ?? '';
      share = jo['share'] is Map ? Map<String, dynamic>.from(jo['share']) : {};
      
      final schemaList = jo['schema'] as List? ?? [];
      reports.clear();
      
      for (var element in schemaList) {
        if (element is Map && element['type'] == 'report') {
          final report = AggregatorReport();
          report.init(Map<String, dynamic>.from(element), {
            'generate': (pd) => generateReport(pd),
            'getFileName': (meta) => getFileName(meta)
          });
          reports.add(report);
        }
      }
    } else if (jo is List) {
      // If it's a list, treat it as a collection of reports without a top-level name
      key = "Aggregator";
      share = {};
      reports.clear();
      for (var element in jo) {
        if (element is Map && element['type'] == 'report') {
          final report = AggregatorReport();
          report.init(Map<String, dynamic>.from(element), {
            'generate': (pd) => generateReport(pd),
            'getFileName': (meta) => getFileName(meta)
          });
          reports.add(report);
        }
      }
    }
  }

  Future<Map<String, dynamic>> generate(AggregatorReport report, {dynamic date}) async {
    // In RN, date selection is handled inside AggregatorReportDisplay via extractor.display
    // Here we bridge it by allowing an optional date override.
    await report.extractor[0].reinit(true); // Ensure data is populated
    
    final s = await report.extractor[0].extractor!.applyPredicate(
      report.extractor[0].extractor!.predicates[0], 
      data: date ?? DateTime.now(),
      getFileName: (meta) => getFileName(meta)
    );
    return report.generateReport(s);
  }

  Future<String> generateWorkbook(AggregatorReport report, {dynamic date}) async {
    final reportData = await generate(report, date: date);
    return await generateReport(reportData);
  }

  Future<String> generateReport(Map<String, dynamic> pd) async {
    // Find the report that matches this metadata
    final report = _findReportByMeta(pd['meta']);
    Map<String, dynamic> nmeta = report.applyMeta(pd['meta']);
    nmeta["aggregator"] = key;
    
    try {
      final fp = await workbook.write(nmeta, pd['data']);
      reportPath = fp;
      return fp;
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> getFileName(Map<String, dynamic> meta) {
    final report = _findReportByMeta(meta);
    Map<String, dynamic> nmeta = report.applyMeta(meta);
    return {"aggregator": key, "collection": nmeta['collection']};
  }

  AggregatorReport _findReportByMeta(Map<String, dynamic> meta) {
    final String reportName = meta['collection'] ?? '';
    for (var r in reports) {
      if (r.key == reportName) return r;
    }
    return reports.last; // Fallback
  }

  Future<void> openReport([String? path]) => workbook.openReport(path);
}
