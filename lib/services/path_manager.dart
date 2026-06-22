import 'package:flutter/foundation.dart';
import 'file_service.dart';

/// PathManager: A singleton that resolves canonical storage paths exactly once
/// on the main thread before any isolate is spawned. This prevents race conditions
/// where isolates start IO before paths are known.
class PathManager {
  static String? _internalRoot;
  static String? _externalRoot;
  static bool _initialized = false;

  static bool get isInitialized => _initialized;
  static String? get internalRoot => _internalRoot;
  static String? get externalRoot => _externalRoot;

  /// Call once on the main thread at app startup before spawning isolates.
  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    final fs = FileService();
    _internalRoot = await fs.getInternalRoot();
    _externalRoot = await fs.getExternalRoot();
    FileService.internalRootOverride = _internalRoot;
    FileService.externalRootOverride = _externalRoot;
    _initialized = true;
    debugPrint(
      'PathManager: initialized. internal=$_internalRoot external=$_externalRoot',
    );
  }

  /// Returns a Map suitable for the isolate initPaths message.
  static Map<String, String?> toIsolateMessage() => {
    'internalRoot': _internalRoot,
    'externalRoot': _externalRoot,
  };
}
