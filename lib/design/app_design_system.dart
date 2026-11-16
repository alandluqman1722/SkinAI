import 'package:flutter/material.dart';

enum AppViewport { compact, medium, expanded }

class AppBreakpoints {
  const AppBreakpoints._();

  static const double compactMaxWidth = 600;
  static const double mediumMaxWidth = 1024;
  static const double contentMaxWidth = 1200;

  static AppViewport fromWidth(double width) {
    if (width < compactMaxWidth) return AppViewport.compact;
    if (width <= mediumMaxWidth) return AppViewport.medium;
    return AppViewport.expanded;
  }

  static AppViewport of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static double contentWidth(double availableWidth) =>
      availableWidth < contentMaxWidth ? availableWidth : contentMaxWidth;
}

class AppSpacing {
  const AppSpacing._();

  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
}

class AppRadius {
  const AppRadius._();

  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double extraLarge = 24;
  static const double pill = 32;
}

class AppElevation {
  const AppElevation._();

  static const double flat = 0;
  static const double subtle = 1;
  static const double raised = 3;
  static const double floating = 6;
}

class AppDesignTokens {
  const AppDesignTokens._();

  static const Color cyan = Color(0xFF00E5FF);
  static const Color blue = Color(0xFF087CFF);
  static const Color purple = Color(0xFF963BFF);
  static const List<Color> brandGradient = [
    Color(0xFF00B8D9),
    blue,
    purple,
  ];

  static const Color darkBackground = Color(0xFF050714);
  static const Color lightBackground = Color(0xFFF3F6FF);
  static const Color darkSnack = Color(0xFF17243B);
  static const Color lightSnack = Colors.white;
}

class AppTheme {
  const AppTheme._();

  static ThemeData build(
    Brightness brightness, {
    Color? accentColor,
    Locale? locale,
  }) {
    final isDark = brightness == Brightness.dark;
    final isKurdish = locale != null &&
        const {'ku', 'ckb', 'bad'}.contains(locale.languageCode);
    final accent = accentColor ??
        (isDark ? AppDesignTokens.cyan : const Color(0xFF0A7BD8));
    final background = isDark
        ? AppDesignTokens.darkBackground
        : AppDesignTokens.lightBackground;

    return ThemeData(
      brightness: brightness,
      fontFamily: isKurdish ? 'NRT' : null,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppDesignTokens.darkSnack : AppDesignTokens.lightSnack,
        contentTextStyle: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF0B1226),
        ),
      ),
    );
  }
}
