import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLang { ku, badini, en, ar }

extension AppLangLocale on AppLang {
  Locale get locale => switch (this) {
        AppLang.ku => const Locale('ku'),
        AppLang.badini => const Locale('bad'),
        AppLang.en => const Locale('en'),
        AppLang.ar => const Locale('ar'),
      };

  String get firebaseLanguageCode => switch (this) {
        AppLang.ku => 'ckb',
        AppLang.badini => 'kmr',
        AppLang.en => 'en',
        AppLang.ar => 'ar',
      };

  bool get isReleaseReady => true;
}

const Map<AppLang, String> langNames = {
  AppLang.ku: 'کوردیی سۆرانی',
  AppLang.badini: 'کوردیی بادینی',
  AppLang.en: 'English',
  AppLang.ar: 'العربية',
};

AppLang? appLangFromCode(String? code) {
  return switch (code?.toLowerCase()) {
    'ku' || 'ckb' => AppLang.ku,
    'bad' || 'badini' || 'kmr' => AppLang.badini,
    'en' => AppLang.en,
    'ar' => AppLang.ar,
    _ => null,
  };
}

class LanguageController extends ChangeNotifier {
  AppLang _language = AppLang.en;

  AppLang get language => _language;

  Future<void> restore(SharedPreferences preferences) async {
    final stored = preferences.getString('lang');
    final restored = appLangFromCode(stored);
    if (restored == null) {
      _language = AppLang.en;
      if (stored != null && stored != 'en') {
        await preferences.setString('lang', 'en');
      }
      return;
    }
    _language = restored;
    if (stored != null && stored.toLowerCase() != restored.locale.languageCode) {
      await preferences.setString('lang', restored.locale.languageCode);
    }
  }

  Future<void> setLanguage(
    AppLang language, {
    required SharedPreferences preferences,
  }) async {
    if (_language == language) return;

    _language = language;
    notifyListeners();
    await preferences.setString('lang', language.locale.languageCode);
  }
}
