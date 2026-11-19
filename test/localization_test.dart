import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skin_ai/localization/app_localizations.dart';
import 'package:skin_ai/localization/locale_helper.dart';
import 'package:skin_ai/main.dart';

void main() {
  test('supported language codes and directions are explicit', () {
    expect(
      LocaleHelper.supportedLocales.map((locale) => locale.languageCode),
      ['ku', 'bad', 'en', 'ar'],
    );
    expect(LocaleHelper.directionFor(const Locale('ku')), TextDirection.rtl);
    expect(LocaleHelper.directionFor(const Locale('bad')), TextDirection.rtl);
    expect(LocaleHelper.directionFor(const Locale('ar')), TextDirection.rtl);
    expect(LocaleHelper.directionFor(const Locale('en')), TextDirection.ltr);
  });

  test('published languages have complete non-empty translation domains', () {
    for (final domain in AppLocalizations.domains) {
      final english = AppLocalizations.keysFor('en', domain);
      expect(english, isNotEmpty, reason: domain);
      for (final language in ['ku', 'bad', 'ar']) {
        final translated = AppLocalizations.keysFor(language, domain);
        expect(translated, english, reason: '$language.$domain keys');
        expect(
          translated.every(
            (key) => AppLocalizations.forLanguageCode(language)
                .text(key, domain: domain)
                .trim()
                .isNotEmpty,
          ),
          isTrue,
          reason: '$language.$domain values',
        );
      }
    }
  });

  test('assessment yes and no labels exist in the app domain', () {
    for (final language in ['en', 'ku', 'bad', 'ar']) {
      final localizations = AppLocalizations.forLanguageCode(language);
      expect(localizations.text('yes'), isNotEmpty);
      expect(localizations.text('no'), isNotEmpty);
    }
  });

  test('notification templates render in the active app language', () {
    expect(
      AppLocalizations.forLanguageCode('en').text(
        'dailyReminderBody',
        domain: 'notifications',
        arguments: const {'task': 'Apply moisturizer'},
      ),
      'It is time for your skincare routine: Apply moisturizer',
    );
    expect(
      AppLocalizations.forLanguageCode('ku').text(
        'dailyReminderBody',
        domain: 'notifications',
        arguments: const {'task': 'Apply moisturizer'},
      ),
      'کاتی ڕۆتینی چاودێری پێستە: Apply moisturizer',
    );
    expect(
      AppLocalizations.forLanguageCode('bad').text(
        'dailyReminderBody',
        domain: 'notifications',
        arguments: const {'task': 'Apply moisturizer'},
      ),
      'دەما رۆتینا چاڤدێریا پێستی یە: Apply moisturizer',
    );
    expect(
      AppLocalizations.forLanguageCode('ar').text(
        'dailyReminderBody',
        domain: 'notifications',
        arguments: const {'task': 'Apply moisturizer'},
      ),
      'حان وقت روتين العناية بالبشرة: Apply moisturizer',
    );
  });

  test('screening labels, fields, disclaimer, and errors are localized', () {
    const disclaimer =
        'This is a screening tool, not a medical diagnosis. Please consult a healthcare professional.';
    expect(
        AppLocalizations.forLanguageCode('en').text('disclaimer'), disclaimer);
    for (final language in ['ku', 'bad', 'ar']) {
      final localizations = AppLocalizations.forLanguageCode(language);
      expect(localizations.text('disclaimer'), isNotEmpty);
      expect(localizations.text('scanLocation'), isNotEmpty);
      expect(localizations.text('symptomsDuration'), isNotEmpty);
      expect(localizations.text('symptomsDetails'), isNotEmpty);
      expect(localizations.text('symptomsChange'), isNotEmpty);
      expect(localizations.text('continueWithoutLocation'), isNotEmpty);
      expect(localizations.text('scanBadInput'), isNotEmpty);
      expect(localizations.text('scanAccessDenied'), isNotEmpty);
      expect(localizations.text('scanProviderError'), isNotEmpty);
      expect(localizations.text('scanTimeout'), isNotEmpty);
    }
  });

  test('secure scan-history and consent copy is complete in every language',
      () {
    const scanHistoryKeys = [
      'accountHistoryConsent',
      'accountHistoryConsentDetail',
      'originalImageConsent',
      'originalImageConsentDetail',
      'accountHistoryConsentTitle',
      'accountHistoryConsentBody',
      'accountImageConsentBody',
      'analyzeWithoutSaving',
      'consentAndAnalyze',
      'imageStorageUnavailable',
      'imageStorageChecking',
      'secureHistoryError',
      'secureHistoryAuthError',
      'secureHistoryUnavailable',
      'refreshAccountHistory',
      'historySourceDesc',
      'clearLocalHistory',
      'clearLocalHistoryConfirm',
      'localHistoryLabel',
      'accountHistoryLabel',
      'scanDate',
      'scanConfidence',
      'bodyLocation',
      'notes',
      'saveDetails',
      'saving',
      'close',
      'originalImageLoadError',
      'originalImageNotStored',
      'imageStorageSaveFailed',
    ];
    for (final language in ['ku', 'bad', 'en', 'ar']) {
      final localizations = AppLocalizations.forLanguageCode(language);
      for (final key in scanHistoryKeys) {
        expect(localizations.text(key).trim(), isNotEmpty,
            reason: '$language.$key');
      }
    }
    expect(
      AppLocalizations.forLanguageCode('bad').text('accountHistoryConsent'),
      isNot(
        AppLocalizations.forLanguageCode('ku').text('accountHistoryConsent'),
      ),
    );
  });

  test('API authentication and availability errors are localized', () {
    for (final language in ['en', 'ku', 'bad', 'ar']) {
      final localizations = AppLocalizations.forLanguageCode(language);
      expect(localizations.text('emailVerificationRequired'), isNotEmpty);
      expect(localizations.text('analysisAccessDenied'), isNotEmpty);
      expect(
        localizations.text('scanProvider', domain: 'settings'),
        isNotEmpty,
      );
      expect(localizations.text('disclaimer'), isNotEmpty);
      expect(localizations.text('uncertainRetake'), isNotEmpty);
      expect(localizations.text('apiServiceUnavailable'), isNotEmpty);
      expect(localizations.text('apiRequestFailed'), isNotEmpty);
    }
  });

  test('Badini is a supported locale with a real catalog', () async {
    final locale = AppLocalizations.forLanguageCode('bad');
    expect(locale.locale, const Locale('bad'));
    expect(locale.text('tagline'), isNotEmpty);
    expect(
      () => AppLocalizations.forLanguageCode('unknown'),
      throwsArgumentError,
    );

    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();
    await controller.setLang(AppLang.badini);
    expect(controller.lang, AppLang.badini);
    expect(controller.t('tagline'), isNotEmpty);
    expect((await SharedPreferences.getInstance()).getString('lang'), 'bad');
  });

  test('language changes update immediately and persist across controllers',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AppController();
    await controller.init();

    await controller.setLang(AppLang.ku);
    expect(controller.lang, AppLang.ku);
    expect(controller.t('tagline'), 'شیکاری پێشکەوتووی تەندروستی پێست');
    expect(
      (await SharedPreferences.getInstance()).getString('lang'),
      'ku',
    );

    await controller.setLang(AppLang.ar);
    expect(controller.lang, AppLang.ar);
    expect(controller.t('tagline'), 'تحليل متقدم لصحة البشرة');

    await controller.setLang(AppLang.en);
    expect(controller.lang, AppLang.en);
    expect(controller.t('tagline'), 'ADVANCED SKIN HEALTH ANALYSIS');

    final restored = AppController();
    await restored.init();
    expect(restored.lang, AppLang.en);
  });

  test('legacy Badini preference restores as Badini instead of falling back',
      () async {
    SharedPreferences.setMockInitialValues({'lang': 'badini'});
    final controller = AppController();
    await controller.init();

    expect(controller.lang, AppLang.badini);
    expect((await SharedPreferences.getInstance()).getString('lang'), 'bad');
  });
}
