import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'file_service.dart';
import 'invoker_service.dart';
import 'isolate_worker.dart';
import '../core/logger.dart';
import 'package:path/path.dart' as p;
import 'io_helper.dart' as io;
import 'excel_generation_service.dart';

/// WorkbookService: Orchestrator / Facade.
/// Manages high-level I/O paths, coordination, isolate delegating, shares triggering, and database backups.
/// Contains NO dependencies on package:excel/excel.dart, package:xml/xml.dart, or package:archive/archive.dart.
class WorkbookService {
  static final WorkbookService _instance = WorkbookService._internal();
  factory WorkbookService() => _instance;
  WorkbookService._internal();

  final FileService _fileService = FileService();
  String? _lastReportPath;
  String? _lastAggregatorDir;
  String? get lastReportPath => _lastReportPath;

  void clearCache() {
    ExcelGenerationService.clearCache();
  }

  Future<String> write(
    Map<String, dynamic> meta,
    Map<String, dynamic> data, {
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    final String collectionName = meta['collection'] ?? 'Report';

    String fileName = meta['fileName'] ?? "";
    if (fileName.isEmpty) {
      final String datePattern = formatFilenameDate(now);
      fileName = "${_fileService.sanitizeName(collectionName)}_$datePattern.xlsx";
    }

    final schemaName = meta['aggregator'] ?? 'Default';
    final aggregatorDir = await _fileService.getAggregatorPath(
      schemaName,
      external: true,
    );
    _lastAggregatorDir = aggregatorDir;
    await _fileService.ensureDir(aggregatorDir);

    final fullPath = p.join(aggregatorDir, fileName);
    final String targetPath = p.isAbsolute(fullPath) ? fullPath : p.absolute(fullPath);

    final String entryName = meta['entry'] ?? 'Default';
    final sheetName = _fileService.sanitizeName(entryName);
    logger.log("WorkbookService: Writing to sheet '$sheetName' in file '$fileName'");

    List<int>? fileBytes;

    if (kIsWeb) {
      fileBytes = await IsolateWorker.instance.execute<List<int>?>(
        'writeExcel',
        {
          'existingBytes': null,
          'data': data,
          'sheetName': sheetName,
          'targetPath': targetPath,
        },
      );
    } else {
      List<int>? existingBytes;
      if (ExcelGenerationService.cachedExcel != null &&
          ExcelGenerationService.cachedExcelPath == targetPath) {
        // Cache matches, we let the isolate worker pull it directly from the cache helper
      } else if (await io.fileExists(targetPath)) {
        existingBytes = await io.readBytes(targetPath);
      }

      if (IsolateWorker.isInsideWorkerIsolate) {
        fileBytes = IsolateWorker.writeExcelInIsolate({
          'existingBytes': existingBytes,
          'data': data,
          'sheetName': sheetName,
          'targetPath': targetPath,
        });
      } else {
        fileBytes = await IsolateWorker.instance.execute<List<int>?>(
          'writeExcel',
          {
            'existingBytes': existingBytes,
            'data': data,
            'sheetName': sheetName,
            'targetPath': targetPath,
          },
        );
      }
    }

    _lastReportPath = targetPath;

    if (kIsWeb) {
      if (fileBytes != null) {
        final base64Data = base64Encode(fileBytes);
        _lastReportPath = "data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64Data|$fileName";
        return _lastReportPath!;
      }
      return fileName;
    }

    if (fileBytes != null) {
      await io.writeBytes(_lastReportPath!, Uint8List.fromList(fileBytes));
      final relativePath = "xyz.maya/anydb/schema/$schemaName/reports";
      await _fileService.copyToPublicDocuments(
        _lastReportPath!,
        fileName,
        relativePath: relativePath,
      );
      _triggerRemoteShares(meta['share'] ?? [], _lastReportPath!, fileName);
    }

    // await _backupDatabase(schemaName, meta['collection'] ?? "Database");

    return _lastReportPath!;
  }

  Future<void> openReport(String? path) async {
    var pStr = path ?? _lastReportPath;
    if (pStr != null) {
      if (!p.isAbsolute(pStr) &&
          !pStr.startsWith('http') &&
          !pStr.startsWith('data:') &&
          _lastAggregatorDir != null) {
        pStr = p.join(_lastAggregatorDir!, pStr);
      }
      await InvokerService.open(pStr);
    }
  }

  void _triggerRemoteShares(
    List<dynamic> shares,
    String filePath,
    String fileName,
  ) async {
    for (var share in shares) {
      final type = share['type'];
      final url = share['url'];
      if (type == 'e-mail' && url != null) {
        final Uri emailLaunchUri = Uri(
          scheme: 'mailto',
          path: url,
          query: 'subject=Report: $fileName&body=Please find the attached report.',
        );
        launchUrl(emailLaunchUri);
      } else if (type == 'url' && url != null) {
        try {
          final bytes = await io.readBytes(filePath);
          if (bytes != null) await http.post(Uri.parse(url), body: bytes);
        } catch (e) {
          debugPrint("WorkbookService: REST share failed: $e");
        }
      }
    }
  }

  Future<void> _backupDatabase(String schemaName, String dbName) async {
    try {
      final dbDir = await _fileService.getDatabasePath(
        schemaName,
        dbName,
        external: false,
      );
      if (!await io.dirExists(dbDir)) return;

      final relativePath = 'xyz.maya/anydb/schema/$schemaName/Database/$dbName';

      final entities = io.listDir(dbDir);
      for (final entity in entities) {
        final path = entity.path as String;
        if (!io.isDirectory(entity) && path.endsWith('.json')) {
          await _fileService.copyToPublicDocuments(
            path,
            p.basename(path),
            relativePath: relativePath,
          );
        }
      }
      debugPrint('WorkbookService: DB backup written to Documents/$relativePath');
    } catch (e) {
      debugPrint('WorkbookService: DB backup failed: $e');
    }
  }

  Future<List<String>> getSheetNames(dynamic fileMeta, String type) async {
    try {
      String fileName = "";
      String collection = "";
      String aggregator = "";
      if (fileMeta is Map) {
        fileName = fileMeta['fileName'] ?? fileMeta['collection'] ?? "";
        collection = fileMeta['collection'] ?? "";
        aggregator = fileMeta['aggregator'] ?? "";
      } else {
        fileName = fileMeta.toString();
        collection = fileName;
      }

      String? currentDir = _lastAggregatorDir;
      if (currentDir == null && aggregator.isNotEmpty) {
        currentDir = await _fileService.getAggregatorPath(
          aggregator,
          external: true,
        );
        _lastAggregatorDir = currentDir;
      }

      String targetPath = fileName;
      if (!p.isAbsolute(fileName) && currentDir != null) {
        String f = fileName;
        if (!f.endsWith('.xlsx')) f += '.xlsx';
        targetPath = p.join(currentDir, f);
      }

      // Check Cache first
      final String sanitizedCol = _fileService.sanitizeName(collection);
      final bool isCacheMatch = kIsWeb
          ? (ExcelGenerationService.cachedExcelPath != null &&
                ((sanitizedCol.isNotEmpty &&
                        p
                            .basename(ExcelGenerationService.cachedExcelPath!.split('|').last)
                            .startsWith(sanitizedCol)) ||
                    ExcelGenerationService.cachedExcelPath == targetPath))
          : (ExcelGenerationService.cachedExcelPath == targetPath);

      final cachedMatched = ExcelGenerationService.getMatchedSheetsFromCache(targetPath, type);
      if (cachedMatched != null && isCacheMatch) {
        debugPrint("WorkbookService: Using cached excel for getSheetNames: $targetPath");
        return cachedMatched;
      }

      // If exact file doesn't exist, try to find the latest matching the collection
      if (!await io.fileExists(targetPath) &&
          collection.isNotEmpty &&
          currentDir != null) {
        final dir = io.listDir(currentDir);
        final sanitizedCollection = collection.replaceAll(' ', '_');
        final matches = dir.where((e) {
          final base = p.basename(e.path);
          return (base.startsWith(collection) ||
                  base.startsWith(sanitizedCollection)) &&
              base.endsWith('.xlsx');
        }).toList();

        if (matches.isNotEmpty) {
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          targetPath = matches.first.path;
          debugPrint("WorkbookService: Discovered existing workbook for discovery at $targetPath");
        }
      }

      // Check Cache again after potential discovery
      final recachedMatched = ExcelGenerationService.getMatchedSheetsFromCache(targetPath, type);
      if (recachedMatched != null && isCacheMatch) {
        return recachedMatched;
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) {
        debugPrint("WorkbookService: Could not read workbook for discovery at $targetPath");
        return [];
      }

      if (IsolateWorker.isInsideWorkerIsolate) {
        return ExcelGenerationService.getMatchedSheetsInIsolate({'bytes': bytes, 'type': type});
      }
      return await IsolateWorker.instance.execute<List<String>>(
        'getMatchedSheets',
        {'bytes': bytes, 'type': type},
      );
    } catch (e) {
      debugPrint("WorkbookService: getSheetNames Error: $e");
      return [];
    }
  }

  Future<List<List<dynamic>>> read(dynamic fileMeta, String sheetName, {bool force = false}) async {
    try {
      String fileName = "";
      String collection = "";
      String aggregator = "";
      if (fileMeta is Map) {
        fileName = fileMeta['fileName'] ?? fileMeta['collection'] ?? "";
        collection = fileMeta['collection'] ?? "";
        aggregator = fileMeta['aggregator'] ?? "";
      } else {
        fileName = fileMeta.toString();
        collection = fileName;
      }

      String? currentDir = _lastAggregatorDir;
      if (currentDir == null && aggregator.isNotEmpty) {
        currentDir = await _fileService.getAggregatorPath(
          aggregator,
          external: true,
        );
        _lastAggregatorDir = currentDir;
      }

      String targetPath = fileName;
      if (!p.isAbsolute(fileName) && currentDir != null) {
        String f = fileName;
        if (!f.endsWith('.xlsx')) f += '.xlsx';
        targetPath = p.join(currentDir, f);
      }

      // Check Cache first
      final String sanitizedCol = _fileService.sanitizeName(collection);
      final bool isCacheMatch = kIsWeb
          ? (ExcelGenerationService.cachedExcelPath != null &&
                ((sanitizedCol.isNotEmpty &&
                        p
                            .basename(ExcelGenerationService.cachedExcelPath!.split('|').last)
                            .startsWith(sanitizedCol)) ||
                    ExcelGenerationService.cachedExcelPath == targetPath))
          : (ExcelGenerationService.cachedExcelPath == targetPath);

      if (!force) {
        final cachedRows = ExcelGenerationService.readSheetFromCache(targetPath, sheetName);
        if (cachedRows != null && isCacheMatch) {
          debugPrint("WorkbookService: Using cached excel for read: $targetPath");
          return cachedRows;
        }
      }

      // If exact file doesn't exist, try to find the latest matching the collection
      if (!await io.fileExists(targetPath) &&
          collection.isNotEmpty &&
          currentDir != null) {
        final dir = io.listDir(currentDir);
        final sanitizedCollection = collection.replaceAll(' ', '_');
        final matches = dir.where((e) {
          final base = p.basename(e.path);
          return (base.startsWith(collection) ||
                  base.startsWith(sanitizedCollection)) &&
              base.endsWith('.xlsx');
        }).toList();

        if (matches.isNotEmpty) {
          matches.sort((a, b) {
            final statA = io.getFileStatSync(a.path);
            final statB = io.getFileStatSync(b.path);
            return statB.modified.compareTo(statA.modified);
          });
          targetPath = matches.first.path;
          debugPrint("WorkbookService: Discovered existing workbook for read at $targetPath");
        }
      }

      // Check Cache again after potential discovery
      if (!force) {
        final recachedRows = ExcelGenerationService.readSheetFromCache(targetPath, sheetName);
        if (recachedRows != null && isCacheMatch) {
          return recachedRows;
        }
      }

      final bytes = await io.readBytes(targetPath);
      if (bytes == null) return [];

      if (IsolateWorker.isInsideWorkerIsolate) {
        return ExcelGenerationService.readSheetInIsolate({'bytes': bytes, 'sheetName': sheetName});
      }
      final dynamic rawRows = await IsolateWorker.instance.execute(
        'readSheet',
        {'bytes': bytes, 'sheetName': sheetName},
      );

      if (rawRows is List) {
        return rawRows.map((row) => (row as List).toList()).toList();
      }
      return [];
    } catch (e) {
      debugPrint("WorkbookService: read Error: $e");
      return [];
    }
  }

  String formatFilenameDate(DateTime dt) {
    final String dayName = DateFormat('E').format(dt);
    final String monthName = DateFormat('MMM').format(dt);
    final String rest = DateFormat('dd_yyyy_HH_mm_ss').format(dt);

    final offset = dt.timeZoneOffset;
    final String hours = offset.inHours.abs().toString().padLeft(2, '0');
    final String mins = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final String sign = offset.isNegative ? "-" : "";
    final String gmt = "GMT_$sign$hours$mins";

    return "${dayName}_${monthName}_${rest}_$gmt";
  }
}
