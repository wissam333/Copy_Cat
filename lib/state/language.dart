// lib/state/language.dart — spoken UI language (Arabic default, English
// toggle). Persisted on-device like coins. main.dart loads the saved value
// into [currentLanguage] before runApp so the t() helper is correct at
// first frame; the provider just mirrors it for widget rebuilds.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { arabic, english }

/// Synchronous language for the t() helper and non-widget call sites.
AppLanguage currentLanguage = AppLanguage.arabic;

Locale? appLocale() => currentLanguage == AppLanguage.arabic
    ? const Locale('ar')
    : const Locale('en');

class LanguageController extends Notifier<AppLanguage> {
  static const _key = 'copycat.lang';

  @override
  AppLanguage build() => currentLanguage;

  Future<void> set(AppLanguage lang) async {
    if (lang == state) return;
    currentLanguage = lang;
    state = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, lang == AppLanguage.english ? 'en' : 'ar');
    } catch (_) {
      // Losing the toggle across restarts is fine this session.
    }
  }
}

final languageProvider =
    NotifierProvider<LanguageController, AppLanguage>(
        LanguageController.new);
