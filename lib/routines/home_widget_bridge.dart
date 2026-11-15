import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

abstract interface class RoutineWidgetBridge {
  bool get isSupported;
  Stream<Uri?> get clicks;
  Future<Uri?> initialLaunch();
  Future<void> update(Map<String, Object?> snapshot);
  Future<bool> requestPinWidget();
}

class HomeWidgetBridge implements RoutineWidgetBridge {
  static const androidWidgetClass =
      'com.example.flutter_application_1.SkinAIHomeWidgetProvider';

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<Uri?> get clicks =>
      isSupported ? HomeWidget.widgetClicked : const Stream<Uri?>.empty();

  @override
  Future<Uri?> initialLaunch() => isSupported
      ? HomeWidget.initiallyLaunchedFromHomeWidget()
      : Future<Uri?>.value();

  @override
  Future<void> update(Map<String, Object?> snapshot) async {
    if (!isSupported) {
      return;
    }

    try {
      await HomeWidget.saveWidgetData<String>(
        'skinai_snapshot',
        jsonEncode(snapshot),
      );
      final updated = await HomeWidget.updateWidget(
        qualifiedAndroidName: androidWidgetClass,
      );
      if (updated != true) {
        debugPrint(
          'SkinAI home widget update is not available yet. Add the widget '
          'to the launcher and configure the iOS App Group if applicable.',
        );
      }
    } on MissingPluginException catch (error) {
      debugPrint('Home screen widget bridge unavailable: $error');
    }
  }

  @override
  Future<bool> requestPinWidget() async {
    if (!isSupported || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    await HomeWidget.requestPinWidget(
      qualifiedAndroidName: androidWidgetClass,
    );
    return true;
  }
}
