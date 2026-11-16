import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum ImagePickerFailureKind {
  permissionDenied,
  cameraUnavailable,
  other,
}

ImagePickerFailureKind classifyImagePickerFailure(Object error) {
  final code = error is PlatformException ? error.code.toLowerCase() : '';
  if (code.contains('denied') || code.contains('restricted')) {
    return ImagePickerFailureKind.permissionDenied;
  }
  if (code.contains('camera_unavailable') ||
      code.contains('camera_not_available') ||
      code == 'no_camera') {
    return ImagePickerFailureKind.cameraUnavailable;
  }
  return ImagePickerFailureKind.other;
}

void showImagePickerFailure(
  BuildContext context,
  Object error, {
  required String Function(String key) translate,
}) {
  final kind = classifyImagePickerFailure(error);
  if (kind == ImagePickerFailureKind.permissionDenied) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(translate('pickerPermissionTitle')),
        content: Text(translate('pickerPermissionMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translate('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _openAppSettings(context, translate);
            },
            child: Text(translate('openSettings')),
          ),
        ],
      ),
    );
    return;
  }

  final message = kind == ImagePickerFailureKind.cameraUnavailable
      ? translate('cameraUnavailable')
      : translate('errPick');
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _openAppSettings(
  BuildContext context,
  String Function(String key) translate,
) async {
  try {
    final opened = await launchUrl(
      Uri.parse('app-settings:'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _showSettingsFailure(context, translate);
    }
  } on Exception {
    if (context.mounted) _showSettingsFailure(context, translate);
  }
}

void _showSettingsFailure(
  BuildContext context,
  String Function(String key) translate,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(translate('settingsOpenFailed'))));
}
