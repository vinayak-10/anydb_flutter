import 'package:intl/intl.dart';
import 'workbook_service.dart';
import 'extractor_service.dart';
import 'file_service.dart';
import '../core/formula_engine.dart';
import 'package:path/path.dart' as p;
import 'io_helper.dart' as io;

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
    
    // JS Logic: Filenames are typically aggregator-scoped.
    // We force the collection name to be consistent for all sheets in a month.
    String formattedName = "";
    final dateVal = nmeta['predicate']?['value'];
    if (dateVal is DateTime) {
      formattedName = DateFormat('MMM yyyy').format(dateVal);
    } else {
      formattedName = extractor[0].predicatedName(nmeta['predicate'] ?? {}, nmeta['entry'] ?? '');
    }

    String n = "${key}_$formattedName";
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

  Future<Map<String, dynamic>> generate(AggregatorReport report, {dynamic date, DateTime? timestamp}) async {
    // In RN, date selection is handled inside AggregatorReportDisplay via extractor.display
    // Here we bridge it by allowing an optional date override.
    await report.extractor[0].reinit(true); // Ensure data is populated
    
    final s = await report.extractor[0].extractor!.applyPredicate(
      report.extractor[0].extractor!.predicates[0], 
      data: date ?? DateTime.now(),
      getFileName: (meta) => getFileName(meta, timestamp: timestamp)
    );
    return report.generateReport(s);
  }

  Future<String> generateWorkbook(AggregatorReport report, {dynamic date, DateTime? timestamp}) async {
    final reportData = await generate(report, date: date, timestamp: timestamp);
    return await generateReport(reportData, timestamp: timestamp);
  }

  Future<String> generateMonthlyBatch(DateTime monthDate) async {
    // 1. Identify reports
    AggregatorReport? dailyReport;
    AggregatorReport? monthlyReport;

    for (var r in reports) {
      final source = r.extractor[0].extractor?.source;
      if (source != null) {
        if (source['type'] == 'database') dailyReport = r;
        if (source['type'] == 'report') monthlyReport = r;
      }
    }

    if (dailyReport == null || monthlyReport == null) {
      throw "Batch generation requires both a Database (Daily) and a Report (Monthly) definition.";
    }

    // 2. Fetch data once for efficiency
    await dailyReport.extractor[0].reinit(true);

    final year = monthDate.year;
    final month = monthDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    int generatedDays = 0;
    String lastPath = "";
    
    // IMPORTANT: Lock the timestamp for the entire batch to ensure all sheets go into the same file
    final DateTime batchTimestamp = DateTime.now();
    
    // Ensure we start with a fresh file if one already exists for this month
    final initialMeta = getFileName({
      "predicate": {"value": monthDate}
    }, timestamp: batchTimestamp);
    
    final _fileService = FileService();
    final aggregatorDir = await _fileService.getAggregatorPath(key, external: true);
    await _fileService.ensureDir(aggregatorDir);

    if (aggregatorDir.isNotEmpty) {
       final fullPath = p.join(aggregatorDir, initialMeta['fileName']);
       await io.deleteFile(fullPath);
    }

    // 3. Loop through each day
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final dailyData = await dailyReport.extractor[0].extractor!.applyPredicate(
        dailyReport.extractor[0].extractor!.predicates[0],
        data: date,
        getFileName: (meta) => getFileName(meta, timestamp: batchTimestamp),
      );

      if (dailyData['data'] != null && (dailyData['data'] as List).isNotEmpty) {
        final reportData = dailyReport.generateReport(dailyData);
        lastPath = await generateReport(reportData, timestamp: batchTimestamp);
        generatedDays++;
      }
    }

    // 4. Generate the Monthly Summary
    if (generatedDays > 0) {
      final monthlyData = await generate(monthlyReport, date: monthDate, timestamp: batchTimestamp);
      lastPath = await generateReport(monthlyData, timestamp: batchTimestamp);
      return lastPath;
    }

    return "No data found for the selected month.";
  }

  Future<String> generateReport(Map<String, dynamic> pd, {DateTime? timestamp}) async {
    // JS Logic: always use the last report to apply meta for workbook write
    if (reports.isEmpty) throw "No reports defined in aggregator";
    final report = reports.last;
    Map<String, dynamic> nmeta = report.applyMeta(pd['meta']);
    nmeta["aggregator"] = key;
    
    try {
      final fp = await workbook.write(nmeta, pd['data'], timestamp: timestamp);
      reportPath = fp;
      return fp;
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> getFileName(Map<String, dynamic> meta, {DateTime? timestamp}) {
    // JS Logic: always use the last report to apply meta for filenames
    // This ensures that all sheets (Daily and Monthly) go into the same workbook file.
    if (reports.isEmpty) return {"aggregator": key, "collection": key};
    final report = reports.last;
    Map<String, dynamic> nmeta = report.applyMeta(meta);
    
    final datePattern = workbook.formatFilenameDate(timestamp ?? DateTime.now());
    final fileName = "${_fileService.sanitizeName(nmeta['collection'] ?? key)}_$datePattern.xlsx";
    
    return {
      "aggregator": key, 
      "collection": nmeta['collection'],
      "fileName": fileName
    };
  }

  Future<void> openReport([String? path]) => workbook.openReport(path);
}
