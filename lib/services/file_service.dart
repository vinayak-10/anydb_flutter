import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_check.dart';
import 'io_helper.dart' as io;
import 'path_provider_helper.dart' as pp;

class FileService {
  static const String appName = 'anydb';
  static const String rootDirName = 'schema';

  Future<String> getInternalRoot() async {
    if (kIsWeb) return rootDirName;
    final path = await pp.getAppDocsDir();
    return p.join(path ?? "", rootDirName);
  }

  Future<String> getExternalRoot() async {
    if (kIsWeb) return 'web_external';
    
    String? rootPath;
    if (isAndroid()) {
      rootPath = await pp.getExtStorageDir();
    }
    
    if (rootPath == null) {
      rootPath = await pp.getAppDocsDir();
    }
    
    return p.join(rootPath ?? "", 'xyz.maya', appName, rootDirName);
  }

  String sanitizeName(String name) {
    return name.replaceAll(' ', '_');
  }

  Future<String> getInternalPath(String schemaName, String type, String value) async {
    final root = await getInternalRoot();
    return p.join(root, sanitizeName(schemaName), type, sanitizeName(value));
  }

  Future<String> getExternalPath(String schemaName, String type, String value) async {
    final root = await getExternalRoot();
    return p.join(root, sanitizeName(schemaName), type, sanitizeName(value));
  }

  Future<void> ensureDir(String path) async {
    if (kIsWeb) return;
    if (!await io.dirExists(path)) {
      await io.createDir(path);
    }
  }

  Future<void> writeJson(String path, String fileName, dynamic content) async {
    final fullPath = p.join(path, fileName);
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(fullPath, jsonEncode(content));
      
      List<String> files = prefs.getStringList(path) ?? [];
      if (!files.contains(fullPath)) {
        files.add(fullPath);
        await prefs.setStringList(path, files);
      }
      return;
    }
    await ensureDir(path);
    await io.writeString(fullPath, jsonEncode(content));
  }

  Future<dynamic> readJson(String filePath) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString(filePath);
      return content != null ? jsonDecode(content) : null;
    }
    if (await io.fileExists(filePath)) {
      final content = await io.readString(filePath);
      return jsonDecode(content);
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
        .map((e) => e.path as String)
        .toList();
  }

  Future<void> deleteFile(String filePath) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(filePath);
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

  Future<void> moveFile(String sourcePath, String destinationPath) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString(sourcePath);
      if (content != null) {
        await prefs.setString(destinationPath, content);
        await deleteFile(sourcePath);
        
        final dirPath = p.dirname(destinationPath);
        List<String> files = prefs.getStringList(dirPath) ?? [];
        if (!files.contains(destinationPath)) {
          files.add(destinationPath);
          await prefs.setStringList(dirPath, files);
        }
      }
      return;
    }
    if (await io.fileExists(sourcePath)) {
      await ensureDir(p.dirname(destinationPath));
      await io.renameFile(sourcePath, destinationPath);
    }
  }
}
