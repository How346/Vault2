import 'package:flutter/material.dart';

/// Design system for the Wallet app.
///
/// Light mode intentionally uses a cool, premium blue-white canvas. Documents
/// themselves are never colour-filtered by the UI.
abstract final class AppColors {
  static const top = Color(0xFFF8FAFF);
  static const middle = Color(0xFFF1F6FF);
  static const bottom = Color(0xFFE8F1FF);

  static const primary = Color(0xFF172B4D);
  static const accentBlue = Color(0xFF1683FF);
  static const background = Color(0xFFF8FAFF);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF101828);
  static const secondary = Color(0xFF667085);
  static const success = Color(0xFF0F9D78);
  static const danger = Color(0xFFD92D20);
  static const warning = Color(0xFFF79009);
  static const border = Color(0xFFD0D5DD);
}

abstract final class AppGradients {
  static const background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.top,
      AppColors.middle,
      AppColors.bottom,
    ],
    stops: [0.0, 0.52, 1.0],
  );

  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.primary,
      AppColors.accentBlue,
    ],
  );
}

ThemeData buildTheme(Brightness brightness) {
  if (brightness == Brightness.dark) {
    final dark = ColorScheme.fromSeed(
      seedColor: AppColors.accentBlue,
      brightness: Brightness.dark,
    );
    return _baseTheme(dark, isDark: true);
  }

  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFDCEBFF),
    onPrimaryContainer: AppColors.primary,
    secondary: AppColors.accentBlue,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE5F0FF),
    onSecondaryContainer: AppColors.primary,
    surface: AppColors.card,
    onSurface: AppColors.text,
    surfaceContainerHighest: Color(0xFFF1F6FF),
    surfaceContainerHigh: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFF8FAFF),
    outline: AppColors.border,
    outlineVariant: Color(0xFFE4EAF2),
    error: AppColors.danger,
    onError: Colors.white,
  );

  return _baseTheme(scheme, isDark: false);
}

ThemeData _baseTheme(
  ColorScheme scheme, {
  required bool isDark,
}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        isDark ? scheme.surface : Colors.transparent,
    canvasColor: isDark ? scheme.surface : Colors.transparent,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? scheme.surfaceContainerHigh : AppColors.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x140F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDark
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFE8EDF5)),
      ),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor:
          isDark ? scheme.surfaceContainerHighest : AppColors.middle,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: AppColors.accentBlue,
          width: 1.6,
        ),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentBlue,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurface,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? scheme.outlineVariant : const Color(0xFFE8EDF5),
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primary,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accentBlue,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accentBlue
            : null,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
