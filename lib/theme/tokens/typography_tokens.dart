import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TypographyTokens {
  // 헤드라인
  static TextStyle headline1 = GoogleFonts.poppins(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static TextStyle headline2 = GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static TextStyle headline3 = GoogleFonts.poppins(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  // 본문
  static TextStyle body1 = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );

  static TextStyle body2 = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  // 버튼
  static TextStyle button = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  // 캡션
  static TextStyle caption = GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.2,
  );
  // 중국어 텍스트 (중국어 텍스트는 Noto Sans SC 유지)
  static TextStyle chineseText = GoogleFonts.notoSans(
    fontSize: 16,
    fontWeight: FontWeight.normal,
  );
}
