import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'file_service.dart';
import 'io_helper.dart' as io;
import 'isolate_worker.dart';
import 'web_downloader.dart';

class SchemaInfo {
  final String name;
  final String path;
  final bool isDefault;

  SchemaInfo({required this.name, required this.path, this.isDefault = false});
}

class SchemaService {
  final FileService _fileService = FileService();
  List<SchemaInfo> _schemas = [];

  List<SchemaInfo> get schemas => _schemas;

  Future<void> init() async {
    debugPrint("SchemaService: init started");
    _schemas = [];
    
    // 1. Load from internal storage
    final internalRoot = await _fileService.getInternalRoot();
    await _loadFromDir(internalRoot);

    // 2. Load from external storage
    final externalRoot = await _fileService.getExternalRoot();
    await _loadFromDir(externalRoot);
    
    debugPrint("SchemaService: init finished, loaded ${_schemas.length} schemas");
  }

  Future<void> _loadFromDir(String path) async {
    if (!kIsWeb) {
      if (!await io.dirExists(path)) {
        await io.createDir(path);
      }
    }

    final files = await _fileService.getFiles(path, 'json');
    for (var filePath in files) {
      debugPrint("SchemaService: checking schema at $filePath");
      try {
        final content = await _fileService.readJson(filePath);
        if (content != null && content is Map && content.containsKey('name')) {
          // Avoid duplicates by path
          if (!_schemas.any((s) => s.path == filePath)) {
            _schemas.add(SchemaInfo(
              name: content['name'].toString(),
              path: filePath,
            ));
          }
        }
      } catch (e) {
        debugPrint("SchemaService: Failed to load schema from $filePath: $e");
      }
    }
  }

  Future<void> loadDefaultSchema() async {
    debugPrint("SchemaService: loading default schema");
    try {
      String defaultJson;
      if (kIsWeb) {
        // On Web, fetch the unbundled schema dynamically via HTTP
        final response = await http.get(Uri.parse('assets/RKM_Physio (1).json'));
        if (response.statusCode == 200) {
          defaultJson = response.body;
        } else {
          final fallback = await http.get(Uri.parse('RKM_Physio (1).json'));
          if (fallback.statusCode == 200) {
            defaultJson = fallback.body;
          } else {
            throw "HTTP fetch failed (status: ${response.statusCode})";
          }
        }
      } else {
        // On native platforms, the schema from assets folder is not bundled per request
        debugPrint("SchemaService: default schema is not bundled on native platforms");
        return;
      }
      final decoded = jsonDecode(defaultJson);
      final Map<String, dynamic> content = decoded is Map ? decoded.cast<String, dynamic>() : decoded;
      await addSchema(content);
    } catch (e) {
      debugPrint("SchemaService Error: Failed to load default schema. $e");
    }
  }

  Future<void> addSchema(dynamic input) async {
    Map<String, dynamic>? content;

    if (input is Map<String, dynamic>) {
      content = input;
    } else if (!kIsWeb) {
      // In IO mode, we expect a string path
      if (input is String) {
         if (await io.fileExists(input)) {
           final rawStr = await io.readString(input);
           content = await IsolateWorker.instance.execute<Map<String, dynamic>>(
             'parseSchema',
             {'jsonStr': rawStr},
           );
         }
      }
    }

    if (content == null) throw "Invalid schema input";

    final rootPath = await _fileService.getInternalRoot();
    final fileName = "${_fileService.sanitizeName(content['name'])}.json";
    
    if (!kIsWeb && input is String) {
      final targetPath = p.join(rootPath, fileName);
      await io.copyFile(input, targetPath);
    } else {
      await _fileService.writeJson(rootPath, fileName, content);
    }

    await _initializeSchemaStructure(content);
    await init();
  }

  Future<void> _initializeSchemaStructure(Map<String, dynamic> schema) async {
    final schemaName = schema['name'];
    final contents = schema['contents'] as List<dynamic>?;
    
    if (contents != null) {
      for (var content in contents) {
        final name = content['name'];
        final type = content['type'];
        
        if (type == 'database') {
          await _fileService.ensureDir(await _fileService.getDatabasePath(schemaName, name));
          await _fileService.ensureDir(await _fileService.getDatabasePath(schemaName, name, external: true));
        } else if (type == 'aggregator') {
          await _fileService.ensureDir(await _fileService.getAggregatorPath(schemaName));
          await _fileService.ensureDir(await _fileService.getAggregatorPath(schemaName, external: true));
        }
      }
    }
  }

  Future<void> exportSchema(SchemaInfo info) async {
    final externalRoot = await _fileService.getExternalRoot();
    final fileName = p.basename(info.path);
    final targetPath = p.join(externalRoot, fileName);
    
    if (!kIsWeb) {
      await io.copyFile(info.path, targetPath);
    } else {
      final content = await _fileService.readJson(info.path);
      if (content != null) {
        final jsonStr = jsonEncode(content);
        downloadWebData(fileName, jsonStr);
      }
    }
    await init();
  }

  Future<void> deleteSchema(SchemaInfo info) async {
    await _fileService.deleteFile(info.path);
    await init();
  }
}

// Top-level schema parser helper for IsolateWorker
Map<String, dynamic> parseSchemaJsonInIsolate(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  return decoded is Map ? decoded.cast<String, dynamic>() : decoded;
}
