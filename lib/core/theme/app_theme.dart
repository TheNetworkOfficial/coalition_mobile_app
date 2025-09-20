import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const primaryColor = Color(0xFF1B4D3E);
  const secondaryColor = Color(0xFFAA2B1D);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    primary: primaryColor,
    secondary: secondaryColor,
    brightness: Brightness.light,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF7F3EF),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Gideon Roman',
        fontWeight: FontWeight.w400,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 2,
      shadowColor: Colors.black12,
      surfaceTintColor: Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
