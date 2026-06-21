import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final double fontScale;
  final double inputFontScale;
  final bool enableTabletSplitView;
  final String? lastLoadedSchemaPath;
  final String? customSearchPicPath;
  final bool useGoogleProfilePic;

  SettingsState({
    this.fontScale = 1.0,
    this.inputFontScale = 1.0,
    this.enableTabletSplitView = false,
    this.lastLoadedSchemaPath,
    this.customSearchPicPath,
    this.useGoogleProfilePic = false,
  });

  SettingsState copyWith({
    double? fontScale,
    double? inputFontScale,
    bool? enableTabletSplitView,
    String? lastLoadedSchemaPath,
    String? customSearchPicPath,
    bool? useGoogleProfilePic,
    bool clearCustomPic = false,
  }) {
    return SettingsState(
      fontScale: fontScale ?? this.fontScale,
      inputFontScale: inputFontScale ?? this.inputFontScale,
      enableTabletSplitView:
          enableTabletSplitView ?? this.enableTabletSplitView,
      lastLoadedSchemaPath: lastLoadedSchemaPath ?? this.lastLoadedSchemaPath,
      customSearchPicPath: clearCustomPic
          ? null
          : (customSearchPicPath ?? this.customSearchPicPath),
      useGoogleProfilePic: useGoogleProfilePic ?? this.useGoogleProfilePic,
    );
  }

  /// Returns the effective input font size (base 16 * scale)
  double get inputFontSize => 16.0 * inputFontScale;
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _load();
    return SettingsState(
      fontScale: 1.0,
      inputFontScale: 1.0,
      enableTabletSplitView: false,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble('fontScale') ?? 1.0;
    final inputScale = prefs.getDouble('inputFontScale') ?? 1.0;
    final tabletSplit = prefs.getBool('enableTabletSplitView') ?? false;
    final lastSchema = prefs.getString('lastLoadedSchemaPath');
    final customSearchPic = prefs.getString('customSearchPicPath');
    final useGooglePic = prefs.getBool('useGoogleProfilePic') ?? false;

    state = state.copyWith(
      fontScale: scale,
      inputFontScale: inputScale,
      enableTabletSplitView: tabletSplit,
      lastLoadedSchemaPath: lastSchema,
      customSearchPicPath: customSearchPic,
      useGoogleProfilePic: useGooglePic,
    );
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

  Future<void> setTabletSplitView(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableTabletSplitView', enabled);
    state = state.copyWith(enableTabletSplitView: enabled);
  }

  Future<void> setLastLoadedSchema(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('lastLoadedSchemaPath');
    } else {
      await prefs.setString('lastLoadedSchemaPath', path);
    }
    state = state.copyWith(lastLoadedSchemaPath: path);
  }

  Future<void> setCustomSearchPicPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('customSearchPicPath');
      state = state.copyWith(clearCustomPic: true);
    } else {
      await prefs.setString('customSearchPicPath', path);
      state = state.copyWith(customSearchPicPath: path);
    }
  }

  Future<void> setUseGoogleProfilePic(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useGoogleProfilePic', enabled);
    state = state.copyWith(useGoogleProfilePic: enabled);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
