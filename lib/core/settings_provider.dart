import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final double fontScale;

  SettingsState({this.fontScale = 1.0});

  SettingsState copyWith({double? fontScale}) {
    return SettingsState(fontScale: fontScale ?? this.fontScale);
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _load();
    return SettingsState(fontScale: 1.0);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble('fontScale') ?? 1.0;
    state = state.copyWith(fontScale: scale);
  }

  Future<void> setFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontScale', scale);
    state = state.copyWith(fontScale: scale);
  }

  void increaseFont() {
    setFontScale(state.fontScale + 0.1);
  }

  void decreaseFont() {
    if (state.fontScale > 0.5) {
      setFontScale(state.fontScale - 0.1);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
