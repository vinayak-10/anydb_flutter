import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_check.dart';
import 'io_helper.dart' as io;
import 'path_provider_helper.dart' as pp;

class FileService {
  static const String appName = 'anydb';
  static const String parentDir = 'xyz.maya';

  final Map<String, String> _webCache = {};

  Future<String> _getWebInternalRoot() async => p.join(parentDir, appName);

  Future<String> getInternalRoot() async {
    if (kIsWeb) return await _getWebInternalRoot();
    if (isLinux()) {
      return p.join(Platform.environment['HOME']!, 'Documents', parentDir, appName);
    }
    final path = await pp.getAppDocsDir();
    return p.join(path ?? "", parentDir, appName);
  }

  Future<String> getExternalRoot() async {
    if (kIsWeb) return p.join('web_external', parentDir, appName);
    if (isLinux()) {
      return p.join(Platform.environment['HOME']!, 'Documents', parentDir, appName);
    }
    
    String? rootPath;
    if (isAndroid()) {
      rootPath = await pp.getExtStorageDir();
    }
    
    rootPath ??= await pp.getAppDocsDir();
    
    return p.join(rootPath ?? "", parentDir, appName);
  }

  String sanitizeName(String name) {
    return name.replaceAll(' ', '_');
  }

  Future<String> getSchemaDir(String schemaName, {bool external = false}) async {
    final root = external ? await getExternalRoot() : await getInternalRoot();
    return p.join(root, sanitizeName(schemaName));
  }

  Future<String> getDatabasePath(String schemaName, String dbName, {bool external = false}) async {
    final schemaDir = await getSchemaDir(schemaName, external: external);
    return p.join(schemaDir, 'Database');
  }

  Future<String> getAggregatorPath(String schemaName, {bool external = false}) async {
    final schemaDir = await getSchemaDir(schemaName, external: external);
    return p.join(schemaDir, 'Aggregators');
  }

  Future<String> getLogsPath(String schemaName, {bool external = false}) async {
    final schemaDir = await getSchemaDir(schemaName, external: external);
    return p.join(schemaDir, 'logs');
  }

  Future<String> getLogPath(String year, String month, {bool external = true}) async {
    final root = external ? await getExternalRoot() : await getInternalRoot();
    return p.join(root, 'Logs', year, month);
  }

  Future<void> ensureDir(String path) async {
    if (kIsWeb) return;
    if (!await io.dirExists(path)) {
      await io.createDir(path);
    }
  }

  static final Map<String, Future<void>> _locks = {};

  Future<void> writeJson(String path, String fileName, dynamic content) async {
    final fullPath = p.join(path, fileName);
    final jsonStr = jsonEncode(content);

    if (kIsWeb) {
      _webCache[fullPath] = jsonStr;
      final prefs = await SharedPreferences.getInstance();
      
      // Update file registry for the directory
      List<String> files = prefs.getStringList(path) ?? [];
      if (!files.contains(fullPath)) {
        files.add(fullPath);
        await prefs.setStringList(path, files);
      }

      try {
        await prefs.setString(fullPath, jsonStr);
      } catch (e) {
        if (e.toString().contains("QuotaExceededError") || e.toString().contains("NS_ERROR_DOM_QUOTA_REACHED")) {
          debugPrint("FileService: Web Quota Exceeded. Using In-Memory fallback.");
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
        debugPrint("FileService.readJson: Corruption detected in $filePath. Error: $e");
        // Proactive Self-Healing: Back up corrupted file for debugging and return null to prevent crashes
        try {
          final backupPath = '$filePath.corrupted_${DateTime.now().millisecondsSinceEpoch}';
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
    
    return io.listDir(dirPath)
        .where((e) => e.path.endsWith('.$extension'))
        .map((e) => e.path)
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
       await io.writeString(p.join(path, fileName), error);
    }
  }
}
