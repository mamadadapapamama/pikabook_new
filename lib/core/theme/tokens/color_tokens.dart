import 'package:flutter/material.dart';

/// 앱 전체에서 사용되는 색상을 정의합니다.
/// 모든 색상은 해당 클래스를 통해 참조해야 합니다.

class ColorTokens {
  // 브랜드 컬러
  static const Color primary = Color(0xFFFE6A15); // 메인 브랜드 컬러
  static const Color primaryMedium= Color(0xFfFE975B); // 메인 브랜드 컬러 연하게
  static const Color primarylight = Color(0xFFFFE1D0); // 메인 브랜드 컬러 연하게
  static const Color primaryverylight = Color(0xFFFFF0E8); // 메인 브랜드 컬러 아주 연하게
  static const Color secondary = Color(0xFF226357); // 보조 브랜드 컬러
  static const Color secondaryLight = Color(0xFFD3E0DD); // 보조 브랜드 컬러
  static const Color secondaryVeryLight = Color(0xFFF1F3F3); // 보조 브랜드 컬러 아주 연하게
  static const Color tertiary = Color(0xFFFFD53C); // 강조 브랜드 컬러
  
  // 중립 컬러
  static const Color background = Color(0xFFFFF9F1); // 배경색
  static const Color surface = Color(0xFFFFFFFF); // 카드, 요소 배경색
  
  // 텍스트 컬러
  static const Color textPrimary = Color(0xFF0E2823); // 주요 텍스트 색상
  static const Color textSecondary = Color(0xFF226357); // 부 텍스트 색상
  static const Color textTertiary = Color(0xFF90B1AB); // 보조 텍스트 색상
  static const Color textLight = Color(0xFFFFFFFF); // 밝은 배경에서 텍스트
  static const Color textGrey = Color(0xFF969696); // 밝은 배경에서 중요하지 않은 텍스트
  static const Color textDarkGrey = Color(0xFF585858); // 회색인데 조금 더 가독성이 있는 텍스트 
  // 상태 컬러
  static const Color success = Color(0xFF34A853); // 성공 상태
  static const Color successLight = Color(0xFFE7F7E9); // 성공 상태 배경색 (연한 녹색)
  static const Color error = Color(0xFFCC0A0A); // 오류 상태
  static const Color errorLight = Color(0xFFFDE8E8); // 오류 상태 연한 배경색
  static const Color errorBackground = Color(0xFFFF6D6D); // 오류 상태 배경
  static const Color warning = Color(0xFFFFC107); // 경고 상태
  static const Color warningLight = Color(0xFFFFF8E1); // 경고 상태 연한 배경색
  static const Color info = Color(0xFF2196F3); // 정보 상태
    
  // 구분선 및 비활성화
  static const Color divider = Color(0xFFE0E0E0); // 구분선
  static const Color disabled = Color(0xFFB8B8B8); // 비활성화 요소, help text
  static const Color black = Color(0xFF000000); // 블랙

  // 추가적인 UI 컬러
  static const Color pinyinText = Color(0xFF969696); // 핀인 텍스트 색상
  static const Color dividerLight = Color(0xFFEEEEEE); // 연한 구분선
  static const Color greyLight = Color(0xFFF0F0F0); // 연한 회색 배경
  static const Color greyMedium = Color(0xFFD3D3D3); // 중간 회색
  static const Color flashcardBackground = Color(0xFFFFF7D8); // 플래시카드 배경
  static const Color deleteSwipeBackground = ColorTokens.errorBackground; // 삭제 스와이프 배경색
  static const Color segmentButtonBackground = Color(0xFFD3E0DD); // 세그먼트 버튼 배경
}
