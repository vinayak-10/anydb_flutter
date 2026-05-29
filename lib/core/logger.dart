import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../services/file_service.dart';
import '../services/io_helper.dart' as io;

class Logger {
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();

  final FileService _fileService = FileService();
  String? _currentLogPath;

  Future<void> log(String message) async {
    final now = DateTime.now();
    final year = DateFormat('yyyy').format(now);
    final month = DateFormat('MM').format(now); // 01, 02...
    final day = DateFormat('yyyy-MM-dd').format(now);

    final logDir = await _fileService.getLogPath(year, month);
    await _fileService.ensureDir(logDir);

    final logFile = p.join(logDir, "$day.log");
    final timestamp = DateFormat('HH:mm:ss').format(now);
    final logMessage = "[$timestamp] $message\n";

    print("LOG: $logMessage"); // Still print to console for dev

    try {
      await io.appendString(logFile, logMessage);
      _currentLogPath = logFile;
    } catch (e) {
      print("Logger Error: $e");
    }
  }

  String? get currentLogPath => _currentLogPath;
}

final logger = Logger();
