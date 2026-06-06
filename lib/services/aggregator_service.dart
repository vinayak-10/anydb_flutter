import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'workbook_service.dart';
import 'extractor_service.dart';
import 'file_service.dart';
import '../core/formula_engine.dart';
import '../core/logger.dart';
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
        'generate': (pd, {DateTime? timestamp}) => pIntf['generate'](pd, timestamp: timestamp),
        'getFileName': (j, {DateTime? timestamp}) => pIntf['getFileName'](j, timestamp: timestamp)
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
    final Map<String, dynamic> summaryMap = {};
    if (jos is List) {
      for (var s in jos) {
        if (s is Map) {
          summaryMap[s['title']] = s['formula'];
        }
      }
    }
    return summaryMap;
  }

  Map<String, dynamic> applyMeta(Map<String, dynamic> meta) {
    Map<String, dynamic> nmeta = Map<String, dynamic>.from(meta);
    
    String formattedName = "";
    dynamic dateVal = nmeta['predicate']?['value'];
    if (dateVal == null && nmeta['entry'] != null) {
       dateVal = DateTime.tryParse(nmeta['entry']);
    }

    if (dateVal is DateTime) {
      formattedName = DateFormat('MMM_yyyy').format(dateVal);
    } else {
      formattedName = extractor[0].predicatedName(nmeta['predicate'] ?? {}, nmeta['entry'] ?? '');
      formattedName = formattedName.replaceAll(' ', '_');
    }

    String n = "${key}_$formattedName";
    nmeta['collection'] = n.replaceAll(' ', '_');
    return nmeta;
  }

  Future<Map<String, dynamic>> generate({DateTime? timestamp}) async {
    try {
      final s = await extractor[0].generate(timestamp: timestamp);
      return pIntf['generate'](s, timestamp: timestamp);
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> generateMeta(Map<String, dynamic> j) {
    try {
      if (j.containsKey('collection') && j.containsKey('entry')) {
        return {
          "collection": j['collection']?.toString() ?? key,
          "entry": j['entry']?.toString() ?? 'Default',
          "predicate": j['predicate'] ?? {}
        };
      }
      final extra = j['extra'] as Map? ?? {};
      return {
        "collection": key,
        "entry": extra['name']?.toString() ?? extra['entry']?.toString() ?? 'Default',
        "predicate": extra['predicate'] ?? {}
      };
    } catch (e) {
      debugPrint("AggregatorService: generateMeta Error: $e");
      return {"collection": key, "entry": "Default", "predicate": {}};
    }
  }

  Map<String, dynamic> generateData(Map<String, dynamic> j) {
    final List<dynamic> rawRecords = j['data'] ?? [];
    logger.log("AggregatorReport: Generating data for $key. Records: ${rawRecords.length}");

    final List<Map<String, dynamic>> records = rawRecords.map((r) {
      try {
        return Map<String, dynamic>.from(r as Map);
      } catch (e) {
        logger.log("AggregatorReport: Failed to process record: $e");
        return <String, dynamic>{};
      }
    }).toList();

    final Map<String, dynamic> calculatedSummary = {};
    final List<String> dataHeaders = records.isNotEmpty ? records[0].keys.toList() : [];

    summary.forEach((title, formula) {
      final val = FormulaEngine.evaluate(formula.toString(), records, dataHeaders);
      calculatedSummary[title] = val;
      logger.log("AggregatorReport: Summary '$title' = $val (Formula: $formula)");
    });

    return {
      "meta": generateMeta(j),
      "name": key,
      "source": j['extra']?['source'] ?? (extractor.isNotEmpty ? extractor[0].extractor?.source : {}),
      "header": [...header, ...(j['extra']?['header'] ?? [])],
      "data": records,
      "summary": calculatedSummary,
      "summaryFormulas": summary,
    };
  }

  Map<String, dynamic> generateReport(Map<String, dynamic> j) {
    return generateData(j);
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
  final workbook = WorkbookService();
  final FileService _fileService = FileService();
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
            'generate': (pd, {DateTime? timestamp}) => generateReport(pd, timestamp: timestamp),
            'getFileName': (meta, {DateTime? timestamp}) => getFileName(meta, timestamp: timestamp)
          });
          reports.add(report);
        }
      }
    } else if (jo is List) {
      key = "Aggregator";
      share = {};
      reports.clear();
      for (var element in jo) {
        if (element is Map && element['type'] == 'report') {
          final report = AggregatorReport();
          report.init(Map<String, dynamic>.from(element), {
            'generate': (pd, {DateTime? timestamp}) => generateReport(pd, timestamp: timestamp),
            'getFileName': (meta, {DateTime? timestamp}) => getFileName(meta, timestamp: timestamp)
          });
          reports.add(report);
        }
      }
    }
  }

  Future<Map<String, dynamic>> generate(AggregatorReport report, {dynamic date, DateTime? timestamp, bool force = false}) async {
    final DateTime targetDate = date is DateTime ? date : (date is DateTimeRange ? date.start : DateTime.now());
    logger.log("AggregatorService: Generating report '${report.key}' for date ${targetDate.toIso8601String()}");

    final meta = getFileName({
      "predicate": {"value": targetDate}
    }, timestamp: timestamp);
    
    final entryName = report.extractor[0].predicatedName(report.extractor[0].extractor?.predicates[0] ?? {}, targetDate.toIso8601String());
    final sheetName = _fileService.sanitizeName(entryName);

    // FIX: For monthly reports, ensure the sheet name is 'MMM_yyyy' (e.g., Feb_2026)
    // while daily reports keep their 'd_MMM yyyy' pattern.
    String finalSheetName = sheetName;
    if (report.key.toLowerCase().contains('monthly')) {
      finalSheetName = DateFormat('MMM_yyyy').format(targetDate);
    }

    logger.log("AggregatorService: Target Sheet Name: $finalSheetName (Original: $sheetName)");
    
    logger.log("AggregatorService: Fetching data from source (force: $force)...");
    await report.extractor[0].reinit(true, force: force);
    final s = await report.extractor[0].extractor!.applyPredicate(
      report.extractor[0].extractor!.predicates[0], 
      data: targetDate,
      getFileName: (meta, {DateTime? timestamp}) => getFileName(meta, timestamp: timestamp),
      timestamp: timestamp,
      force: force
    );
    
    // Inject the corrected sheetName for workbook writing
    s['extra'] ??= {};
    s['extra']['name'] = finalSheetName;

    return report.generateData(s);
  }

  Future<String> generateWorkbook(AggregatorReport report, {dynamic date, DateTime? timestamp, bool force = false}) async {
    final reportData = await generate(report, date: date, timestamp: timestamp, force: force);
    final result = await generateReport(reportData, timestamp: timestamp);
    return result['path'];
  }

  Future<String> generateMonthlyBatch(DateTime monthDate, {bool force = false}) async {
    try {
      workbook.clearCache();
      final monthStr = DateFormat('MMM yyyy').format(monthDate);
      logger.log("AggregatorService: Starting monthly batch for $monthStr (force: $force)");
      
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

      await dailyReport.extractor[0].reinit(true);

      final year = monthDate.year;
      final month = monthDate.month;
      final daysInMonth = DateTime(year, month + 1, 0).day;

      int generatedDays = 0;
      String lastPath = "";
      final DateTime batchTimestamp = DateTime.now();
      
      final initialMeta = getFileName({
        "predicate": {"value": monthDate}
      }, timestamp: batchTimestamp);
      
      final aggregatorDir = await _fileService.getAggregatorPath(key, external: true);
      await _fileService.ensureDir(aggregatorDir);

      if (aggregatorDir.isNotEmpty) {
         final fullPath = p.join(aggregatorDir, initialMeta['fileName']);
         if (force) {
           await io.deleteFile(fullPath);
         }
      }

      final initialSummaryData = {
        "meta": monthlyReport.generateMeta({
          "predicate": {"value": monthDate},
          "extra": {"name": DateFormat('MMM yyyy').format(monthDate)}
        }),
        "name": monthlyReport.key,
        "source": monthlyReport.extractor[0].extractor?.source,
        "header": monthlyReport.header,
        "data": [],
        "summary": {},
        "summaryFormulas": monthlyReport.summary,
      };

      final placeholderMeta = getFileName({
        "collection": key,
        "entry": DateFormat('MMM_yyyy').format(monthDate),
        "predicate": {"value": monthDate}
      }, timestamp: batchTimestamp);

      await workbook.write(placeholderMeta, initialSummaryData, timestamp: batchTimestamp);

      for (int d = 1; d <= daysInMonth; d++) {
        if (kIsWeb) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        final date = DateTime(year, month, d);
        try {
          logger.log("AggregatorService: Processing day $d of $daysInMonth...");
          final dailyData = await dailyReport.extractor[0].extractor!.applyPredicate(
            dailyReport.extractor[0].extractor!.predicates[0],
            data: date,
            getFileName: (meta, {DateTime? timestamp}) => getFileName(meta, timestamp: timestamp ?? batchTimestamp),
            force: force
          );

          if (dailyData['data'] != null && (dailyData['data'] as List).isNotEmpty) {
            final reportData = dailyReport.generateReport(dailyData);
            final result = await generateReport(reportData, timestamp: batchTimestamp);
            lastPath = result['path'];
            generatedDays++;
          }
        } catch (e, stack) {
          debugPrint("AggregatorService: Error processing day $d: $e");
          debugPrint("Stack Trace: $stack");
        }
      }

      if (generatedDays > 0) {
        logger.log("AggregatorService: Finished processing $generatedDays days. Generating final monthly summary...");
        final monthlyDataFull = await generate(monthlyReport, date: monthDate, timestamp: batchTimestamp, force: true);
        final result = await generateReport(monthlyDataFull, timestamp: batchTimestamp);
        lastPath = result['path'];
        logger.log("AggregatorService: Monthly batch complete. Path: $lastPath");
        if (!kIsWeb) {
          workbook.clearCache();
        }
        return lastPath;
      }

      if (!kIsWeb) {
        workbook.clearCache();
      }
      return "No data found for the selected month.";
    } catch (e, stack) {
      debugPrint("AggregatorService: FATAL BATCH ERROR: $e");
      debugPrint("Stack Trace: $stack");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generateReport(Map<String, dynamic> pd, {DateTime? timestamp}) async {
    if (reports.isEmpty) throw "No reports defined in aggregator";
    final report = reports.last;
    final Map<String, dynamic> metaObj = (pd['meta'] as Map<String, dynamic>?) ?? {};
    Map<String, dynamic> nmeta = report.applyMeta(metaObj);
    nmeta["aggregator"] = key;
    
    try {
      final fp = await workbook.write(nmeta, pd, timestamp: timestamp);
      reportPath = fp;
      
      final Map<String, dynamic> result = Map<String, dynamic>.from(pd);
      result['path'] = fp;
      return result;
    } catch (e) {
      rethrow;
    }
  }

  Map<String, dynamic> getFileName(Map<String, dynamic> meta, {DateTime? timestamp}) {
    if (reports.isEmpty) return {"aggregator": key, "collection": key};
    final report = reports.last;
    Map<String, dynamic> nmeta = report.applyMeta(meta);
    final String collection = nmeta['collection'] ?? key;
    
    String fileName = "";
    final ts = timestamp ?? DateTime.now();
    final datePattern = workbook.formatFilenameDate(ts);
    fileName = "${_fileService.sanitizeName(collection)}_$datePattern.xlsx";
    
    return {
      "aggregator": key, 
      "collection": collection,
      "fileName": fileName
    };
  }

  Future<void> openReport([String? path]) => workbook.openReport(path);
}
