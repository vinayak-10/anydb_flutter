import 'package:path_provider/path_provider.dart';

Future<String?> getAppDocsDir() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  } catch (e) {
    return null;
  }
}

Future<String?> getExtStorageDir() async {
  try {
    final directory = await getExternalStorageDirectory();
    return directory?.path;
  } catch (e) {
    return null;
  }
}
