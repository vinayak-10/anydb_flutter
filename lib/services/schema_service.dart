import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'file_service.dart';
import 'io_helper.dart' as io;

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
    debugPrint("SchemaService: loading default schema from assets");
    try {
      final defaultJson = await rootBundle.loadString('assets/RKM_Physio (1).json');
      final decoded = jsonDecode(defaultJson);
      final Map<String, dynamic> content = decoded is Map ? decoded.cast<String, dynamic>() : decoded;
      await addSchema(content);
    } catch (e) {
      debugPrint("SchemaService Error: No default schema found in assets. $e");
    }
  }

  Future<void> addSchema(dynamic input) async {
    Map<String, dynamic>? content;

    if (input is Map<String, dynamic>) {
      content = input;
    } else if (!kIsWeb) {
      // In IO mode, we expect a string path or a dynamic object that has a path
      // But let's simplify: main.dart should pass content or a path
      if (input is String) {
         content = await _fileService.readJson(input);
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
    }
    await init();
  }

  Future<void> deleteSchema(SchemaInfo info) async {
    await io.deleteFile(info.path);
    await init();
  }
}
