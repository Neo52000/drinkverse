import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFF080B12);
  static const surface = Color(0xFF111722);
  static const accent = Color(0xFFFFB84D);

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF17130E),
        indicatorColor: Color(0xFF6A5030),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: Color(0xFFB5BECC)),
      ),
    );
  }
}
