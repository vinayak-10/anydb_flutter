import 'dart:typed_data';

class WebFileStat {
  DateTime get modified => DateTime.now();
  int get size => 0;
}

Future<String?> readFile(String path) async => null;
Future<String> readString(String path) async => "";
Future<Uint8List?> readBytes(String path) async => null;
Future<void> writeString(String path, String content) async {}
Future<void> appendString(String path, String content) async {}
Future<void> writeBytes(String path, Uint8List bytes) async {}
Future<bool> fileExists(String path) async => false;
Future<bool> dirExists(String path) async => false;
Future<void> createDir(String path) async {}
Future<void> copyFile(String source, String dest) async {}
Future<void> deleteFile(String path) async {}
Future<void> renameFile(String source, String dest) async {}
WebFileStat getFileStatSync(String path) => WebFileStat();
List<dynamic> listDir(String path) => [];
bool isDirectory(dynamic entity) => false;
