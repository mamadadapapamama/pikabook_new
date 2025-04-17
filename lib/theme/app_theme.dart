import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens/color_tokens.dart';
import 'tokens/typography_tokens.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: ColorTokens.primary,
      scaffoldBackgroundColor: ColorTokens.background,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ColorTokens.primary,
        selectionColor: ColorTokens.primarylight.withOpacity(0.5),
        selectionHandleColor: ColorTokens.primary,
      ),
      colorScheme: const ColorScheme.light(
        primary: ColorTokens.primary,
        secondary: ColorTokens.secondary,
        tertiary: ColorTokens.tertiary,
        surface: ColorTokens.surface,
        background: ColorTokens.background,
        error: ColorTokens.error,
      ),
      textTheme: TextTheme(
        displayLarge: TypographyTokens.headline1,
        displayMedium: TypographyTokens.headline2,
        displaySmall: TypographyTokens.headline3,
        headlineMedium: TypographyTokens.subtitle1,
        headlineSmall: TypographyTokens.subtitle2,
        bodyLarge: TypographyTokens.body1,
        bodyMedium: TypographyTokens.body2,
        labelLarge: TypographyTokens.button,
        bodySmall: TypographyTokens.caption,
        labelSmall: TypographyTokens.overline,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ColorTokens.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: ColorTokens.primary,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorTokens.primary,
          foregroundColor: Colors.white,
          textStyle: TypographyTokens.button,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      cardTheme: CardTheme(
        color: ColorTokens.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: ColorTokens.divider,
        thickness: 1,
      ),
    );
  }
}
