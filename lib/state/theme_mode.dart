// lib/state/theme_mode.dart — light/dark toggle (Stage Black vs Stage
// Paper). Same pattern as language.dart: a sync global read before runApp,
// a Notifier for widget rebuilds, persisted on-device.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_refresh.dart';
import '../stage_theme.dart';

/// Sync flag for main.dart and non-widget call sites.
bool currentThemeIsLight = false;

class ThemeController extends Notifier<bool> {
  static const _key = 'copycat.theme';

  @override
  bool build() => currentThemeIsLight;

  Future<void> set(bool light) async {
    if (light == state) return;
    currentThemeIsLight = light;
    StageBlack.setLight(light);
    state = light;
    appRefresh.refresh();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, light ? 'light' : 'dark');
    } catch (_) {
      // Losing the toggle across restarts is fine this session.
    }
  }
}

final themeProvider =
    NotifierProvider<ThemeController, bool>(ThemeController.new);
