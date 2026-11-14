import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'locale_helper.dart';
import 'translations/ar.dart';
import 'translations/bad.dart';
import 'translations/en.dart';
import 'translations/ku.dart';

export 'language_controller.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final value = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    if (value == null) {
      throw FlutterError('AppLocalizations are not available in this context.');
    }
    return value;
  }

  static AppLocalizations forLanguageCode(String code) {
    final locale = switch (code) {
      'ku' || 'ckb' => const Locale('ku'),
      'bad' || 'badini' || 'kmr' => const Locale('bad'),
      'ar' => const Locale('ar'),
      'en' => const Locale('en'),
      _ => throw ArgumentError.value(code, 'code', 'Unsupported app language'),
    };
    return AppLocalizations(locale);
  }

  static const _translations = <String, Map<String, Map<String, String>>>{
    'en': translationsEn,
    'ku': translationsKu,
    'bad': translationsBad,
    'ar': translationsAr,
  };

  static const domains = [
    'app',
    'settings',
    'notifications',
    'routines',
    'widgets',
  ];

  static Set<String> keysFor(String languageCode, String domain) =>
      _translations[languageCode]?[domain]?.keys.toSet() ?? const {};

  Map<String, String> domain(String name) =>
      _translations[locale.languageCode]?[name] ?? const <String, String>{};

  String text(
    String key, {
    String domain = 'app',
    Map<String, String> arguments = const {},
  }) {
    final localeTranslations = _translations[locale.languageCode];
    final value = localeTranslations?[domain]?[key] ??
        (domain == 'app' ? null : localeTranslations?['app']?[key]);
    if (value == null || value.trim().isEmpty) {
      throw FlutterError(
        'Missing translation "${locale.languageCode}.$domain.$key".',
      );
    }
    return value.replaceAllMapped(
      RegExp(r'\{([^}]+)\}'),
      (match) => arguments[match.group(1)] ?? match.group(0)!,
    );
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => LocaleHelper.supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
