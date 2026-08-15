import 'package:flutter/material.dart';

/// Dark retro-modern design system theme for the Sierra AGI Workbench.
class AgiTheme {
  const AgiTheme._();

  // EGA Accent palette colors
  static const Color egaBlack = Color(0xFF0D1117);
  static const Color egaDarkSurface = Color(0xFF161B22);
  static const Color egaCardSurface = Color(0xFF21262D);
  static const Color egaBorder = Color(0xFF30363D);

  static const Color egaAmber = Color(0xFFFFAA00);
  static const Color egaCyan = Color(0xFF55FFFF);
  static const Color egaGreen = Color(0xFF55FF55);
  static const Color egaMagenta = Color(0xFFFF55FF);
  static const Color egaBlue = Color(0xFF5555FF);
  static const Color egaRed = Color(0xFFFF5555);
  static const Color egaWhite = Color(0xFFF0F6FC);
  static const Color egaMuted = Color(0xFF8B949E);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: egaBlack,
      cardColor: egaCardSurface,
      colorScheme: const ColorScheme.dark(
        primary: egaCyan,
        secondary: egaAmber,
        surface: egaDarkSurface,
        error: egaRed,
        onPrimary: Color(0xFF002233),
        onSurface: egaWhite,
      ),
      fontFamily: 'Courier', // Retro monospace feel on macOS
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: egaCyan,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: egaWhite,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: egaAmber,
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          color: egaWhite,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          color: egaMuted,
          height: 1.3,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1F6FEB),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0xFF388BFD), width: 1),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: egaCyan,
          side: const BorderSide(color: Color(0xFF388BFD), width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0D1117),
        hintStyle: const TextStyle(color: egaMuted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: egaBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: egaBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: egaCyan, width: 1.5),
        ),
      ),
    );
  }
}
