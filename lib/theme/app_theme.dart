import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgDark = Color(0xFF0B0E14);
  static const Color bgElevated = Color(0xFF111622);
  static const Color cardBg = Color(0xFF161B26);
  static const Color cardBorder = Color(0xFF232D3F);

  static const Color cyanAccent = Color(0xFF00F2FE);
  static const Color cyanSecondary = Color(0xFF4FACFE);
  static const Color purpleAccent = Color(0xFF7928CA);
  static const Color pinkAccent = Color(0xFFFF0080);
  static const Color greenSuccess = Color(0xFF00E676);
  static const Color amberWarning = Color(0xFFFFAB00);
  static const Color redDanger = Color(0xFFFF5252);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [cyanAccent, cyanSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGradient = LinearGradient(
    colors: [purpleAccent, pinkAccent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF181F2E), Color(0xFF10141D)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: cyanAccent,
      canvasColor: bgDark,
      cardColor: cardBg,
      colorScheme: const ColorScheme.dark(
        primary: cyanAccent,
        secondary: cyanSecondary,
        surface: cardBg,
        error: redDanger,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgElevated,
        selectedItemColor: cyanAccent,
        unselectedItemColor: textMuted,
      ),
    );
  }
}
