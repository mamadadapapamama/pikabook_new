import 'package:flutter/material.dart';
import 'tokens/color_tokens.dart';
import 'tokens/typography_tokens.dart';

/// 앱의 테마를 정의하는 클래스입니다.
class AppTheme {
  /// 라이트 테마를 반환합니다.
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: ColorTokens.primary,
      scaffoldBackgroundColor: ColorTokens.background,
      colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: ColorTokens.primary,
        secondary: ColorTokens.secondary,
        tertiary: ColorTokens.tertiary,
        surface: ColorTokens.surface,
        background: ColorTokens.background,
        error: ColorTokens.error,
        onPrimary: ColorTokens.textLight,
        onSecondary: ColorTokens.textLight,
        onSurface: ColorTokens.textPrimary,
        onBackground: ColorTokens.textPrimary,
        onError: ColorTokens.textLight,
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
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ColorTokens.primary,
        selectionColor: ColorTokens.primary.withOpacity(0.3),
        selectionHandleColor: ColorTokens.primary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorTokens.primary,
        foregroundColor: Colors.white,
        elevation: 0,
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
        color: ColorTokens.textTertiary,
        thickness: 1,
      ),
    );
  }
}
