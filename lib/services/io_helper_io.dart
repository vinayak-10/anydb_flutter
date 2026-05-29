import 'dart:io' as io;
import 'dart:typed_data';

Future<String?> readFile(String path) async {
  final file = io.File(path);
  if (await file.exists()) {
    return await file.readAsString();
  }
  return null;
}

Future<String> readString(String path) async {
  final file = io.File(path);
  return await file.readAsString();
}

Future<Uint8List?> readBytes(String path) async {
  final file = io.File(path);
  if (await file.exists()) {
    return await file.readAsBytes();
  }
  return null;
}

Future<void> writeString(String path, String content) async {
  final file = io.File(path);
  await file.writeAsString(content);
}

Future<void> appendString(String path, String content) async {
  final file = io.File(path);
  await file.writeAsString(content, mode: io.FileMode.append);
}

Future<void> writeBytes(String path, Uint8List bytes) async {
  final file = io.File(path);
  await file.writeAsBytes(bytes);
}

Future<bool> fileExists(String path) async {
  return await io.File(path).exists();
}

Future<bool> dirExists(String path) async {
  return await io.Directory(path).exists();
}

Future<void> createDir(String path) async {
  await io.Directory(path).create(recursive: true);
}

Future<void> copyFile(String source, String dest) async {
  await io.File(source).copy(dest);
}

Future<void> deleteFile(String path) async {
  final file = io.File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> renameFile(String source, String dest) async {
  await io.File(source).rename(dest);
}

io.FileStat getFileStatSync(String path) {
  return io.File(path).statSync();
}

List<io.FileSystemEntity> listDir(String path) {
  final dir = io.Directory(path);
  if (dir.existsSync()) {
    return dir.listSync();
  }
  return [];
}

bool isDirectory(dynamic entity) => entity is io.Directory;
