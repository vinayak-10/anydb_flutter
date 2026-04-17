import 'dart:io';

dynamic getFile(String path) => File(path);
dynamic getDirectory(String path) => Directory(path);

Future<bool> fileExists(String path) async => await File(path).exists();
Future<bool> dirExists(String path) async => await Directory(path).exists();

Future<void> createDir(String path) async => await Directory(path).create(recursive: true);

Future<void> writeBytes(String path, List<int> bytes) async {
  await File(path).create(recursive: true);
  await File(path).writeAsBytes(bytes);
}

Future<void> writeString(String path, String content) async {
  await File(path).writeAsString(content);
}

Future<String> readString(String path) async {
  return await File(path).readAsString();
}

List<dynamic> listDir(String path) {
  return Directory(path).listSync();
}

Future<void> deleteFile(String path) async {
  await File(path).delete();
}

Future<void> renameFile(String source, String dest) async {
  await File(source).rename(dest);
}

Future<void> copyFile(String source, String dest) async {
  await File(source).copy(dest);
}
