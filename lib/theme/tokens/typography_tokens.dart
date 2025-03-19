import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TypographyTokens {
  // 폰트 패밀리
  static final TextStyle poppins = GoogleFonts.poppins();
  static final TextStyle notoSansKr = GoogleFonts.notoSansKr();
  static final TextStyle notoSansSc = GoogleFonts.notoSansSc();

  // 헤드라인
  static TextStyle headline1 = GoogleFonts.poppins(
    fontSize: 40,
    fontWeight: FontWeight.bold,
    height: 1.5,
  );

  static TextStyle headline2 = GoogleFonts.poppins(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static TextStyle headline3 = GoogleFonts.poppins(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // 서브타이틀
  static TextStyle subtitle1 = GoogleFonts.notoSansKr(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static TextStyle subtitle2 = GoogleFonts.notoSansKr(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  // 본문
  static TextStyle body1 = GoogleFonts.notoSansKr(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static TextStyle body2 = GoogleFonts.notoSansKr(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  // 버튼
  static TextStyle button = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  // 캡션
  static TextStyle caption = GoogleFonts.notoSansKr(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  // 작은 글씨
  static TextStyle overline = GoogleFonts.notoSansKr(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.4,
  );

  // 중국어 텍스트 (중국어 텍스트는 Noto Sans SC 유지)
  static TextStyle chineseText = GoogleFonts.notoSansSc(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );
}
