import 'package:flutter/foundation.dart';

bool isAndroid() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

bool isIOS() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

bool isLinux() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.linux;
}

bool isWindows() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows;
}

bool isMacOS() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS;
}
