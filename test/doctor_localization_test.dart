import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/localization/app_localizations.dart';

void main() {
  const languages = ['en', 'ku', 'bad', 'ar'];

  test('doctor discovery labels exist in all supported languages', () {
    for (final language in languages) {
      final localizations = AppLocalizations.forLanguageCode(language);
      expect(
        localizations.text('title', domain: 'doctors'),
        isNotEmpty,
        reason: language,
      );
      expect(
        localizations.text('noDoctorsSubtitle', domain: 'doctors'),
        isNotEmpty,
        reason: language,
      );
      expect(
        localizations.text('cityErbil', domain: 'doctors'),
        isNotEmpty,
        reason: language,
      );
      for (final key in [
        'favoritesOnly',
        'editClinic',
        'reviewPrivacyNote',
        'appointmentConfirm',
        'verificationDocuments',
      ]) {
        expect(
          localizations.text(key, domain: 'doctors'),
          isNotEmpty,
          reason: '$language.$key',
        );
      }
    }
  });

  test('structured scanner choices are translated in all supported languages',
      () {
    const appKeys = [
      'scanArea',
      'region_face',
      'region_scalp',
      'region_neck',
      'region_chest',
      'region_back',
      'region_arms',
      'region_hands',
      'region_legs',
      'region_feet',
      'region_other',
      'scanDuration',
      'durationUnderWeek',
      'durationOneToFourWeeks',
      'durationOneToSixMonths',
      'durationOverSixMonths',
      'durationNotSure',
      'scanSymptoms',
      'symptomItching',
      'symptomRedness',
      'symptomPain',
      'symptomSwelling',
      'symptomBleeding',
      'symptomColorChange',
      'symptomNone',
      'symptomNotSure',
      'scanChange',
      'changeBetter',
      'changeWorse',
      'changeNoChange',
      'changeAppearance',
      'changeNotSure',
      'photoClearGuidance',
      'photoAvoidFilters',
      'scannerDisclaimer',
    ];

    for (final language in languages) {
      final localizations = AppLocalizations.forLanguageCode(language);
      for (final key in appKeys) {
        expect(localizations.text(key), isNotEmpty, reason: '$language.$key');
      }
    }
  });
}
