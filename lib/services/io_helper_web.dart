dynamic getFile(String path) => null;
dynamic getDirectory(String path) => null;

Future<bool> fileExists(String path) async => false;
Future<bool> dirExists(String path) async => false;

Future<void> createDir(String path) async {}

Future<void> writeBytes(String path, List<int> bytes) async {}

Future<void> writeString(String path, String content) async {}

Future<String> readString(String path) async => "";

List<dynamic> listDir(String path) => [];

Future<void> deleteFile(String path) async {}

Future<void> renameFile(String source, String dest) async {}

Future<void> copyFile(String source, String dest) async {}
