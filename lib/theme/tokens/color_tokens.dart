import 'package:flutter/material.dart';

/// 앱 전체에서 사용되는 색상을 정의합니다.
/// 모든 색상은 해당 클래스를 통해 참조해야 합니다.

class ColorTokens {
  // 브랜드 컬러
  static const Color primary = Color(0xFFFE6A15); // 메인 브랜드 컬러
  static const Color secondary = Color(0xFF226357); // 보조 브랜드 컬러
  static const Color tertiary = Color(0xFFFFD53C); // 강조 브랜드 컬러
  
  // 중립 컬러
  static const Color background = Color(0xFFFFF9F1); // 배경색
  static const Color surface = Color(0xFFFFFFFF); // 카드, 요소 배경색
  
  // 텍스트 컬러
  static const Color textPrimary = Color(0xFF0E2823); // 주요 텍스트 색상
  static const Color textSecondary = Color(0xFF226357); // 부 텍스트 색상
  static const Color textTertiary = Color(0xFF90B1AB); // 보조 텍스트 색상
  static const Color textLight = Color(0xFFFFFFFF); // 밝은 배경에서 텍스트
  
  // 상태 컬러
  static const Color success = Color(0xFF34A853); // 성공 상태
  static const Color error = Color(0xFFCC0A0A); // 오류 상태
  static const Color warning = Color(0xFFFFC107); // 경고 상태
  static const Color info = Color(0xFF2196F3); // 정보 상태
  
  // 작업/플래시카드 관련 색상
  static const Color flashcardEasy = Color(0xFF34A853); // 플래시카드 쉬움
  static const Color flashcardMedium = Color(0xFFFFC107); // 플래시카드 보통
  static const Color flashcardHard = Color(0xFFCC0A0A); // 플래시카드 어려움
  
  // 구분선 및 비활성화
  static const Color divider = Color(0xFFE0E0E0); // 구분선
  static const Color disabled = Color(0xFFB8B8B8); // 비활성화 요소
}
