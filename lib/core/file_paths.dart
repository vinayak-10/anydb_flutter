import 'package:path/path.dart' as p;
import '../services/file_service.dart';

class FilePaths {
  late String _rootDir;
  final FileService _fileService = FileService();
  Map<String, String> dirs = {};

  Future<void> init(Map<String, dynamic> schema, {bool partial = false}) async {
    _rootDir = _fileService.sanitizeName(schema['name'] ?? 'default');
    if (partial) return;

    final contents = schema['contents'] as List<dynamic>?;
    if (contents != null) {
      for (var c in contents) {
        String n = _fileService.sanitizeName(c['type'] ?? '');
        String v = _fileService.sanitizeName(c['name'] ?? '');
        dirs[n] = v;
      }
    }
  }

  Future<String> getInternalPath(String name) async {
    final root = await _fileService.getInternalRoot();
    String path = p.join(root, _rootDir);
    if (dirs.containsKey(name)) {
      path = p.join(path, name, dirs[name]);
    }
    return path;
  }

  Future<String> genInternalPath(String name, String value) async {
    final root = await _fileService.getInternalRoot();
    return p.join(root, _rootDir, name, _fileService.sanitizeName(value));
  }

  Future<String> getExternalPath(String name) async {
    final root = await _fileService.getExternalRoot();
    String path = p.join(root, _rootDir);
    if (dirs.containsKey(name)) {
      path = p.join(path, name, dirs[name]);
    }
    return path;
  }

  Future<String> genExternalPath(String name, String value) async {
    final root = await _fileService.getExternalRoot();
    return p.join(root, _rootDir, name, _fileService.sanitizeName(value));
  }
}
