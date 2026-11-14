import 'package:flutter/widgets.dart';

class LocaleHelper {
  const LocaleHelper._();

  static const supportedLocales = [
    Locale('ku'),
    Locale('bad'),
    Locale('en'),
    Locale('ar'),
  ];

  static bool isRtl(Locale locale) => locale.languageCode != 'en';

  static TextDirection directionFor(Locale locale) =>
      isRtl(locale) ? TextDirection.rtl : TextDirection.ltr;
}
