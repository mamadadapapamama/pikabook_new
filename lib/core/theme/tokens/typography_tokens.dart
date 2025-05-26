import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 앱 전체에서 사용되는 텍스트 스타일을 정의합니다.
/// 모든 텍스트 스타일은 해당 클래스를 통해 참조해야 합니다.

class TypographyTokens {
  // 기본 폰트 패밀리 정의
  static const String notoSansKr = 'Noto Sans KR';
  static const String notoSansHk = 'Noto Sans HK';
  static String poppins = 'Poppins';

  // 헤드라인 스타일 - 페이지 제목, 중요 섹션 등
  static TextStyle get headline1 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 40,
        fontWeight: FontWeight.bold,
        letterSpacing: -1.0,
        height: 1.2,
      );

  static TextStyle get headline1En => GoogleFonts.poppins(
        fontSize: 40,
        fontWeight: FontWeight.bold,
        letterSpacing: -1.0,
        height: 1.5,
      );

  static TextStyle get headline1Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 40,
        fontWeight: FontWeight.bold,
        letterSpacing: -1.0,
        height: 1.2,
      );

  static TextStyle get headline2 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get headline2En => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        height: 1.5,
      );

  static TextStyle get headline2Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get headline3 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );

  static TextStyle get headline3En => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.5,
      );

  static TextStyle get headline3Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );
  
  // 부제목 스타일 - 섹션 소개, 요약 등
  static TextStyle get subtitle1 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  static TextStyle get subtitle1En => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 1.5,
      );

  static TextStyle get subtitle1Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  static TextStyle get subtitle2 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );

  static TextStyle get subtitle2En => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        height: 1.5,
      );

  static TextStyle get subtitle2Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.2,
      );

  // 본문 스타일 - 일반 텍스트 내용

  static TextStyle get body1 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  static TextStyle get body1En => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.5,
      );

  static TextStyle get body1Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  static TextStyle get body1Bold => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );
   static TextStyle get body1BoldEn => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.5,
      );

  static TextStyle get body1BoldCn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ); 

  static TextStyle get body2 => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  static TextStyle get body2En => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.5,
      );

  static TextStyle get body2Cn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  // 버튼 텍스트 스타일
  static TextStyle get button => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  static TextStyle get buttonEn => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.5,
      );

  static TextStyle get buttonCn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.2,
      );

  // 작은 텍스트 스타일 - 보조 정보, 각주 등
  static TextStyle get caption => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.2,
      );

  static TextStyle get captionEn => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get captionCn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.2,
      );

  // 오버라인 스타일 - 라벨, 머리말 등
  static TextStyle get overline => TextStyle(
        fontFamily: notoSansKr,
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.5,
        height: 1.2,
      );

  static TextStyle get overlineEn => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.5,
        height: 1.5,
      );

  static TextStyle get overlineCn => TextStyle(
        fontFamily: notoSansHk,
        fontSize: 10,
        fontWeight: FontWeight.w400,
        letterSpacing: 1.5,
        height: 1.2,
      );
}
