import 'package:flutter/material.dart';

enum AppViewport { compact, medium, expanded }

class AppBreakpoints {
  const AppBreakpoints._();

  static const double compactMaxWidth = 600;
  static const double mediumMaxWidth = 1024;
  static const double contentMaxWidth = 1100;

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
  static const double x12 = 48;
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

class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
}

class AppTypography {
  const AppTypography._();

  static const double display = 32;
  static const double headline = 24;
  static const double title = 20;
  static const double body = 16;
  static const double label = 14;
  static const double caption = 12;
}

class AppDesignTokens {
  const AppDesignTokens._();

  static const Color cyan = Color(0xFF00E5FF);
  static const Color blue = Color(0xFF0066FF);
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
  static const Color success = Color(0xFF15803D);
  static const Color warning = Color(0xFF9A5B00);
  static const Color danger = Color(0xFFB42318);
  static const Color darkSurface = Color(0xFF151C2C);
  static const Color lightSurface = Colors.white;
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color lightText = Color(0xFF0B1226);
  static const Color darkMuted = Color(0xFFB8C2DC);
  static const Color lightMuted = Color(0xFF475569);
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
    final accent = accentColor ?? AppDesignTokens.blue;
    final background = isDark
        ? AppDesignTokens.darkBackground
        : AppDesignTokens.lightBackground;
    final foreground =
        isDark ? AppDesignTokens.darkText : AppDesignTokens.lightText;
    final muted =
        isDark ? AppDesignTokens.darkMuted : AppDesignTokens.lightMuted;
    final fontFamily = isKurdish ? 'NRT' : null;

    return ThemeData(
      brightness: brightness,
      fontFamily: fontFamily,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      ),
      textTheme: Typography.material2021()
          .black
          .apply(
            fontFamily: fontFamily,
            bodyColor: foreground,
            displayColor: foreground,
          )
          .copyWith(
            displayLarge: TextStyle(
              fontSize: AppTypography.display,
              height: 1.25,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
            headlineSmall: TextStyle(
              fontSize: AppTypography.headline,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
            titleLarge: TextStyle(
              fontSize: AppTypography.title,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
            bodyLarge: TextStyle(
              fontSize: AppTypography.body,
              height: 1.5,
              color: foreground,
            ),
            bodyMedium: TextStyle(
              fontSize: AppTypography.label,
              height: 1.5,
              color: foreground,
            ),
            bodySmall: TextStyle(
              fontSize: AppTypography.caption,
              height: 1.45,
              color: muted,
            ),
            labelLarge: TextStyle(
              fontSize: AppTypography.label,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? AppDesignTokens.darkSurface : AppDesignTokens.lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x4,
          vertical: AppSpacing.x3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF46516A) : const Color(0xFF667085),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.flat,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: foreground,
          fontSize: AppTypography.title,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: accent),
        actionsIconTheme: IconThemeData(color: accent),
      ),
      cardTheme: CardThemeData(
        color:
            isDark ? AppDesignTokens.darkSurface : AppDesignTokens.lightSurface,
        elevation: AppElevation.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFD0D5DD),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppDesignTokens.darkSnack : AppDesignTokens.lightSnack,
        contentTextStyle: TextStyle(
          color: foreground,
          fontFamily: fontFamily,
          fontSize: AppTypography.body,
        ),
      ),
    );
  }
}
