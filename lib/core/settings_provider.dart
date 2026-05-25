import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final double fontScale;
  final double inputFontScale;

  SettingsState({this.fontScale = 1.0, this.inputFontScale = 1.0});

  SettingsState copyWith({double? fontScale, double? inputFontScale}) {
    return SettingsState(
      fontScale: fontScale ?? this.fontScale,
      inputFontScale: inputFontScale ?? this.inputFontScale,
    );
  }

  /// Returns the effective input font size (base 16 * scale)
  double get inputFontSize => 16.0 * inputFontScale;
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _load();
    return SettingsState(fontScale: 1.0, inputFontScale: 1.0);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble('fontScale') ?? 1.0;
    final inputScale = prefs.getDouble('inputFontScale') ?? 1.0;
    state = state.copyWith(fontScale: scale, inputFontScale: inputScale);
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

  Future<void> setInputFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('inputFontScale', scale);
    state = state.copyWith(inputFontScale: scale);
  }

  void increaseInputFont() {
    setInputFontScale(state.inputFontScale + 0.1);
  }

  void decreaseInputFont() {
    if (state.inputFontScale > 0.5) {
      setInputFontScale(state.inputFontScale - 0.1);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
