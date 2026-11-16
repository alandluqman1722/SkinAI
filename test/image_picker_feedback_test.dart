import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_ai/image_picker_feedback.dart';
import 'package:skin_ai/localization/app_localizations.dart';

void main() {
  test('picker guidance is translated in all supported languages', () {
    for (final language in ['en', 'ku', 'bad', 'ar']) {
      final localizations = AppLocalizations.forLanguageCode(language);
      for (final key in [
        'pickerPermissionTitle',
        'pickerPermissionMessage',
        'cameraUnavailable',
        'openSettings',
        'settingsOpenFailed',
      ]) {
        expect(localizations.text(key), isNotEmpty, reason: '$language.$key');
      }
    }
  });

  test('classifies denied and restricted picker permissions', () {
    for (final code in [
      'camera_access_denied',
      'photo_access_restricted',
    ]) {
      expect(
        classifyImagePickerFailure(PlatformException(code: code)),
        ImagePickerFailureKind.permissionDenied,
      );
    }
  });

  test('classifies an unavailable camera separately', () {
    expect(
      classifyImagePickerFailure(
        PlatformException(code: 'camera_unavailable'),
      ),
      ImagePickerFailureKind.cameraUnavailable,
    );
  });

  test('classifies other picker errors for a friendly fallback', () {
    expect(
      classifyImagePickerFailure(PlatformException(code: 'unknown')),
      ImagePickerFailureKind.other,
    );
  });
}
