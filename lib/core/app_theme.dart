import 'package:flutter/material.dart';

/// Source unique de vérité pour l'identité visuelle de DrinkVerse.
///
/// Aucun écran ne doit définir sa propre palette globale. Les couleurs,
/// rayons, ombres et styles principaux sont centralisés ici afin de préparer
/// la refonte premium sans multiplier les valeurs magiques dans les widgets.
abstract final class AppTheme {
  static const background = Color(0xFF05070C);
  static const backgroundRaised = Color(0xFF090D15);
  static const surface = Color(0xFF101620);
  static const surfaceHigh = Color(0xFF171F2C);
  static const surfaceGlass = Color(0xB3141B27);

  static const accent = Color(0xFFFFB347);
  static const accentStrong = Color(0xFFFF7A3D);
  static const electricBlue = Color(0xFF43B8FF);
  static const success = Color(0xFF55D69E);
  static const danger = Color(0xFFFF6B72);

  static const textPrimary = Color(0xFFF6F8FC);
  static const textSecondary = Color(0xFFADB7C7);
  static const textMuted = Color(0xFF737F91);
  static const outline = Color(0xFF283243);

  static const appGradient = RadialGradient(
    center: Alignment(0.32, -0.38),
    radius: 1.3,
    colors: <Color>[
      Color(0xFF1A2434),
      backgroundRaised,
      background,
    ],
    stops: <double>[0, 0.48, 1],
  );

  static const premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[accent, accentStrong],
  );

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFF211300),
      primaryContainer: Color(0xFF523513),
      onPrimaryContainer: Color(0xFFFFDDB3),
      secondary: electricBlue,
      onSecondary: Color(0xFF001E2C),
      secondaryContainer: Color(0xFF103B52),
      onSecondaryContainer: Color(0xFFC5E9FF),
      tertiary: success,
      error: danger,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: outline,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.8,
          height: 1.02,
        ),
        headlineLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          height: 1.08,
        ),
        headlineMedium: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineSmall: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleLarge: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: const TextStyle(
          color: textSecondary,
          height: 1.45,
        ),
        bodyMedium: const TextStyle(
          color: textSecondary,
          height: 1.4,
        ),
        bodySmall: const TextStyle(
          color: textMuted,
          height: 1.35,
        ),
        labelLarge: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: const Color(0xF20B1018),
        indicatorColor: accent.withValues(alpha: 0.18),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected)
                ? textPrimary
                : textMuted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : textMuted,
            size: 24,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: surfaceGlass,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          foregroundColor: const Color(0xFF211300),
          backgroundColor: accent,
          disabledBackgroundColor: outline,
          disabledForegroundColor: textMuted,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: textPrimary,
          side: const BorderSide(color: outline),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surfaceHigh,
          highlightColor: accent.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: outline),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        showDragHandle: true,
        dragHandleColor: outline,
        modalBarrierColor: Color(0xB3000000),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline),
        ),
      ),
    );
  }
}
