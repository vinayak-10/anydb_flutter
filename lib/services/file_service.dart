import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_check.dart';
import 'io_helper.dart' as io;
import 'path_provider_helper.dart' as pp;
import 'package:permission_handler/permission_handler.dart';

class FileService {
  static const String appName = 'anydb';
  static const String parentDir = 'xyz.maya';

  static String? internalRootOverride;
  static String? externalRootOverride;

  final Map<String, String> _webCache = {};

  Future<String> _getWebInternalRoot() async => p.join(parentDir, appName);

  Future<String> getInternalRoot() async {
    if (internalRootOverride != null) return internalRootOverride!;
    if (kIsWeb) return await _getWebInternalRoot();
    if (isLinux()) {
      final home = pp.getHomeDir();
      return p.join(home ?? '', 'Documents', parentDir, appName);
    }
    final path = await pp.getAppDocsDir();
    return p.join(path ?? "", parentDir, appName);
  }

  Future<String> getExternalRoot() async {
    if (externalRootOverride != null) return externalRootOverride!;
    if (kIsWeb) return p.join('web_external', parentDir, appName);
    if (isLinux()) {
      final home = pp.getHomeDir();
      return p.join(home ?? '', 'Documents', parentDir, appName);
    }

    String? rootPath;
    if (isAndroid()) {
      rootPath = await pp.getExtStorageDir();
    }

    rootPath ??= await pp.getAppDocsDir();

    return p.join(rootPath ?? "", parentDir, appName);
  }

  String sanitizeName(String name) {
    return name.replaceAll(' ', '_').replaceAll('/', '_');
  }

  Future<String> getSchemaDir(
    String schemaName, {
    bool external = false,
  }) async {
    // If external, target Android/data scratch layout directory; if internal, app sandbox container
    final root = external ? await getExternalRoot() : await getInternalRoot();
    return p.join(root, 'schema', sanitizeName(schemaName));
  }

  Future<String> getDatabasePath(
    String schemaName,
    String dbName, {
    bool external = false,
  }) async {
    final schemaDir = await getSchemaDir(schemaName, external: external);
    return p.join(schemaDir, 'Database');
  }

  Future<String> getAggregatorPath(
    String schemaName, {
    bool external = false,
  }) async {
    final schemaDir = await getSchemaDir(schemaName, external: external);
    return p.join(schemaDir, 'Aggregators');
  }

  Future<String> getLogsPath(String schemaName, {bool external = false}) async {
    final schemaDir = await getSchemaDir(schemaName, external: external);
    return p.join(schemaDir, 'logs');
  }


  Future<String> getLogPath(
    String year,
    String month, {
    bool external = true,
  }) async {
    final root = external ? await getExternalRoot() : await getInternalRoot();
    return p.join(root, 'Logs', year, month);
  }

  Future<void> ensureDir(String path) async {
    if (kIsWeb) return;
    try {
      if (!await io.dirExists(path)) {
        await io.createDir(path);
      }
    } catch (e) {
      debugPrint("FileService: ensureDir failed for path '$path': $e");
    }
  }

  static final Map<String, Future<void>> _locks = {};

  Future<void> writeJson(String path, String fileName, dynamic content) async {
    final fullPath = p.join(path, fileName);
    final jsonStr = jsonEncode(content);

    if (kIsWeb) {
      _webCache[fullPath] = jsonStr;
      final prefs = await SharedPreferences.getInstance();

      try {
        // Update file registry for the directory
        List<String> files = prefs.getStringList(path) ?? [];
        if (!files.contains(fullPath)) {
          files.add(fullPath);
          await prefs.setStringList(path, files);
        }
      } catch (e) {
        if (e.toString().contains("QuotaExceededError") ||
            e.toString().contains("quota") ||
            e.toString().contains("NS_ERROR_DOM_QUOTA_REACHED")) {
          debugPrint("FileService: Web Quota Exceeded during registry update.");
        } else {
          rethrow;
        }
      }

      try {
        await prefs.setString(fullPath, jsonStr);
      } catch (e) {
        if (e.toString().contains("QuotaExceededError") ||
            e.toString().contains("quota") ||
            e.toString().contains("NS_ERROR_DOM_QUOTA_REACHED")) {
          debugPrint(
            "FileService: Web Quota Exceeded. Using In-Memory fallback.",
          );
        } else {
          rethrow;
        }
      }
      return;
    }

    await ensureDir(path);

    // Asynchronous lock queue for this specific file path to prevent race conditions
    final previousLock = _locks[fullPath] ?? Future.value();
    final completer = Completer<void>();
    _locks[fullPath] = completer.future;

    try {
      await previousLock;
      // Atomic write: write to a temporary file first, then perform an atomic rename/move
      final tmpPath = '$fullPath.tmp';
      await io.writeString(tmpPath, jsonStr);
      await io.renameFile(tmpPath, fullPath);
    } finally {
      completer.complete();
      if (_locks[fullPath] == completer.future) {
        _locks.remove(fullPath);
      }
    }
  }

  Future<dynamic> readJson(String filePath) async {
    if (kIsWeb) {
      if (_webCache.containsKey(filePath)) {
        final decoded = jsonDecode(_webCache[filePath]!);
        return decoded is Map ? decoded.cast<String, dynamic>() : decoded;
      }
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString(filePath);
      if (content != null) {
        _webCache[filePath] = content;
        final decoded = jsonDecode(content);
        return decoded is Map ? decoded.cast<String, dynamic>() : decoded;
      }
      return null;
    }
    if (await io.fileExists(filePath)) {
      final content = await io.readString(filePath);
      try {
        final decoded = jsonDecode(content);
        return decoded is Map ? decoded.cast<String, dynamic>() : decoded;
      } catch (e) {
        debugPrint(
          "FileService.readJson: Corruption detected in $filePath. Error: $e",
        );
        // Proactive Self-Healing: Back up corrupted file for debugging and return null to prevent crashes
        try {
          final backupPath =
              '$filePath.corrupted_${DateTime.now().millisecondsSinceEpoch}';
          await io.copyFile(filePath, backupPath);
          debugPrint("FileService: Backed up corrupted file to $backupPath");
        } catch (err) {
          debugPrint("FileService: Failed to back up corrupted file: $err");
        }
        return null;
      }
    }
    return null;
  }

  Future<List<String>> getFiles(String dirPath, String extension) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final files = prefs.getStringList(dirPath) ?? [];
      return files.where((f) => f.endsWith('.$extension')).toList();
    }

    if (!await io.dirExists(dirPath)) return [];

    return io
        .listDir(dirPath)
        .where((e) => e.path.endsWith('.$extension'))
        .map((e) => e.path as String)
        .toList();
  }

  Future<void> deleteFile(String filePath) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(filePath);
      _webCache.remove(filePath);

      final dirPath = p.dirname(filePath);
      List<String> files = prefs.getStringList(dirPath) ?? [];
      files.remove(filePath);
      await prefs.setStringList(dirPath, files);
      return;
    }
    if (await io.fileExists(filePath)) {
      await io.deleteFile(filePath);
    }
  }

  Future<void> logError(String schemaName, String error) async {
    final path = await getLogsPath(schemaName, external: true);
    await ensureDir(path);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = "error_$timestamp.log";
    if (kIsWeb) {
      await writeJson(path, fileName, {"error": error});
    } else {
      final logFilePath = p.join(path, fileName);
      await io.writeString(logFilePath, error);
      await copyToPublicDocuments(
        logFilePath,
        fileName,
        relativePath: "xyz.maya/anydb/schema/$schemaName/logs",
      );
    }
  }

  static const MethodChannel _fileSaverChannel = MethodChannel('com.example.anydb_flutter/file_saver');

  Future<void> copyToPublicDocuments(
    String sourcePath,
    String displayName, {
    required String relativePath, // Should be: "xyz.maya/anydb/schema/[SchemaName]/Aggregators"
  }) async {
    if (kIsWeb) return;
    
    // Explicitly enforce parent directory injection fallback structure if not fully formed
    String targetRelativePath = relativePath;
    if (!targetRelativePath.contains('schema/')) {
       final parts = relativePath.split('/');
       if (parts.length >= 3) {
         // Re-inject 'schema' component cleanly if omitted by upstream services
         targetRelativePath = p.join(parts[0], parts[1], 'schema', parts[2], parts.sublist(3).join('/'));
       }
    }

    if (isAndroid()) {
      try {
        await _fileSaverChannel.invokeMethod('saveFileToDocuments', {
          'sourcePath': sourcePath,
          'displayName': displayName,
          'relativePath': targetRelativePath,
          'mimeType': displayName.endsWith('.json')
              ? 'application/json'
              : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        });
      } catch (e) {
        debugPrint("FileService: Failed to copy to public Documents via MediaStore: $e");
      }
    } else if (isLinux()) {
      try {
        final home = pp.getHomeDir();
        if (home != null) {
          final targetDir = p.join(home, 'Documents', targetRelativePath);
          await ensureDir(targetDir);
          final targetPath = p.join(targetDir, displayName);
          final bytes = await io.readBytes(sourcePath);
          if (bytes != null) {
            await io.writeBytes(targetPath, bytes);
          }
        }
      } catch (e) {
        debugPrint("FileService: Failed to copy to public Documents on Linux: $e");
      }
    }
  }


  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !isAndroid()) return true;
    try {
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
      final status = await Permission.storage.request();
      return status.isGranted;
    } catch (e) {
      debugPrint("FileService: requestStoragePermission failed: $e");
      return false;
    }
  }

  Future<void> purgeWorkspaceCache(String schemaName) async {
    final tempDir = await pp.getTempDir();
    if (tempDir != null && await io.dirExists(tempDir)) {
      await io.deleteDir(tempDir);
    }
    final aggregatorDir = await getAggregatorPath(schemaName, external: true);
    if (await io.dirExists(aggregatorDir)) {
      final files = io.listDir(aggregatorDir);
      for (var file in files) {
        await io.deleteFile(file.path);
      }
    }
  }

  Future<int> pruneExportedFiles(int retentionDays) async {
    if (kIsWeb) return 0;
    final home = pp.getHomeDir() ?? "";
    final documentsPath = isLinux()
        ? p.join(home, 'Documents', 'xyz.maya', 'anydb')
        : p.join(await pp.getExtStorageDir() ?? "", 'Documents', 'xyz.maya', 'anydb');

    if (!await io.dirExists(documentsPath)) return 0;

    int deletedCount = 0;
    final now = DateTime.now();
    final threshold = now.subtract(Duration(days: retentionDays));

    Future<void> pruneDirectory(String dirPath) async {
      final entities = io.listDir(dirPath);
      for (var entity in entities) {
        final path = entity.path as String;
        if (io.isDirectory(entity)) {
          await pruneDirectory(path);
          // If directory is now empty, delete it
          if (io.listDir(path).isEmpty) {
            try {
              await io.deleteDir(path);
            } catch (_) {}
          }
        } else {
          final fileStat = io.getFileStatSync(path);
          if (retentionDays == 0 || fileStat.modified.isBefore(threshold)) {
            await io.deleteFile(path);
            deletedCount++;
          }
        }
      }
    }

    await pruneDirectory(documentsPath);
    return deletedCount;
  }
}
