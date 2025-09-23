import 'package:flutter/material.dart';

const _primaryColor = Color(0xFF396289);
const _secondaryColor = Color(0xFF8D232B);
const _lightBackground = Color(0xFFFFFFFF);
const _lightText = Color(0xFF333333);
const _lightCardColor = Color(0xFFC5C5C5);
const _darkBackground = Color(0xFF121212);
const _darkSurface = Color(0xFF2A2A2A);
const _darkText = Color(0xFFFFFFFF);
const _lightButtonHover = Color(0xFF004080);
const _darkButtonHover = Color(0xFF003064);
const _lightFormBackground = Color(0xFFC5C5C5);
const _lightFormInput = Color(0xFFCCCCCC);
const _lightFormPlaceholder = Color(0xFF838383);
const _darkFormBackground = Color(0xFF2A2A2A);
const _darkFormInput = Color(0xFF1A1A1A);
const _darkFormPlaceholder = Color(0xFFAAAAAA);
const _borderRadius = 5.0;
const _fontFamily = 'Gideon Roman';

ThemeData buildLightTheme() {
  return _buildTheme(
    brightness: Brightness.light,
    backgroundColor: _lightBackground,
    surfaceColor: _lightCardColor,
    textColor: _lightText,
    buttonHoverColor: _lightButtonHover,
    formBackgroundColor: _lightFormBackground,
    formInputColor: _lightFormInput,
    formPlaceholderColor: _lightFormPlaceholder,
  );
}

ThemeData buildDarkTheme() {
  return _buildTheme(
    brightness: Brightness.dark,
    backgroundColor: _darkBackground,
    surfaceColor: _darkSurface,
    textColor: _darkText,
    buttonHoverColor: _darkButtonHover,
    formBackgroundColor: _darkFormBackground,
    formInputColor: _darkFormInput,
    formPlaceholderColor: _darkFormPlaceholder,
  );
}

ThemeData _buildTheme({
  required Brightness brightness,
  required Color backgroundColor,
  required Color surfaceColor,
  required Color textColor,
  required Color buttonHoverColor,
  required Color formBackgroundColor,
  required Color formInputColor,
  required Color formPlaceholderColor,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _primaryColor,
    primary: _primaryColor,
    secondary: _secondaryColor,
    brightness: brightness,
  ).copyWith(
    surface: surfaceColor,
    onSurface: textColor,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
    scaffoldBackgroundColor: backgroundColor,
    fontFamily: _fontFamily,
  );

  final textTheme = base.textTheme.apply(
    bodyColor: textColor,
    displayColor: textColor,
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_borderRadius),
  );

  final buttonBackground = WidgetStateProperty.resolveWith<Color?>(
    (states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return buttonHoverColor;
      }
      return _primaryColor;
    },
  );

  final cardColor = surfaceColor;

  return base.copyWith(
    colorScheme: colorScheme,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: _primaryColor,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: brightness == Brightness.light ? 2 : 0,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: colorScheme.primaryContainer,
      selectedColor: colorScheme.secondaryContainer,
      labelStyle: TextStyle(
        color: colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: buttonBackground,
        foregroundColor: WidgetStateProperty.all(Colors.white),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
        shape: WidgetStateProperty.all(buttonShape),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: buttonBackground,
        foregroundColor: WidgetStateProperty.all(Colors.white),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
        shape: WidgetStateProperty.all(buttonShape),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(_primaryColor),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: formInputColor,
      hintStyle: TextStyle(color: formPlaceholderColor),
      labelStyle: TextStyle(color: textColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
        borderSide: BorderSide(color: formBackgroundColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
        borderSide: BorderSide(color: formBackgroundColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
        borderSide: const BorderSide(color: _primaryColor),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: brightness == Brightness.light
          ? _primaryColor.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.08),
      thickness: 1,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      iconColor: colorScheme.primary,
      textColor: textColor,
    ),
  );
}
