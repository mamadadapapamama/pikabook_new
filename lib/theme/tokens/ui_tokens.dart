import 'package:flutter/material.dart';
import 'color_tokens.dart';
import 'typography_tokens.dart';

/// 앱 전체에서 사용되는 UI 요소에 대한 토큰
class UITokens {
  // 그림자
  static List<BoxShadow> get lightShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];
  
  static List<BoxShadow> get mediumShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];
  
  // 배경색
  static const Color homeBackground = Color(0xFFFFF9F1);
  static const Color cardBackground = Colors.white;
  
  // 플래시카드 관련 색상
  static const Color flashcardBadgeBackground = Color(0xFFFFD53C); // 노란색
  static const Color flashcardBadgeBorder = Color(0xFF665518); // 노란색 테두리
  
  // 버튼 스타일
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  );
  
  // 컨테이너 스타일
  static BoxDecoration roundedContainerDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: lightShadow,
  );
  
  static BoxDecoration circleContainerDecoration = BoxDecoration(
    color: Colors.white,
    shape: BoxShape.circle,
    boxShadow: lightShadow,
  );
  
  // 스낵바 스타일
  static SnackBarThemeData snackBarTheme = const SnackBarThemeData(
    backgroundColor: ColorTokens.secondary,
    contentTextStyle: TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  );
} 