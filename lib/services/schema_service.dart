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
    final rootPath = await _fileService.getInternalRoot();
    debugPrint("SchemaService: rootPath = $rootPath");
    
    if (!kIsWeb) {
      if (!await io.dirExists(rootPath)) {
        await io.createDir(rootPath);
      }
    }

    final files = await _fileService.getFiles(rootPath, 'json');
    for (var filePath in files) {
      debugPrint("SchemaService: loading schema from $filePath");
      final content = await _fileService.readJson(filePath);
      if (content != null) {
        _schemas.add(SchemaInfo(
          name: content['name'],
          path: filePath,
        ));
      }
    }
    debugPrint("SchemaService: init finished, loaded ${_schemas.length} schemas");
  }

  Future<void> loadDefaultSchema() async {
    debugPrint("SchemaService: loading default schema from assets");
    try {
      final defaultJson = await rootBundle.loadString('assets/schema.json');
      final content = jsonDecode(defaultJson);
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
        final type = _fileService.sanitizeName(content['type']);
        final value = _fileService.sanitizeName(content['name']);
        
        await _fileService.ensureDir(await _fileService.getInternalPath(schemaName, type, value));
        await _fileService.ensureDir(await _fileService.getExternalPath(schemaName, type, value));
      }
    }
  }

  Future<void> exportSchema(SchemaInfo info) async {
    final externalRoot = await _fileService.getExternalRoot();
    final fileName = p.basename(info.path);
    final targetPath = p.join(externalRoot, fileName);
    
    await _fileService.moveFile(info.path, targetPath);
    await init();
  }
}
