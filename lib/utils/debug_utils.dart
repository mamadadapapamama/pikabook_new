import 'package:flutter/foundation.dart';

/// 디버그 로그 유틸리티
/// 리리즈 모드에서 로그를 관리하기 위한 클래스
class DebugUtils {
  /// 릴리즈 모드에서 로그 출력 여부
  static bool enableLogInRelease = false;
  
  /// 안전한 로그 출력 함수
  /// 릴리즈 모드에서는 특별히 설정된 경우만 출력
  static void log(String message) {
    if (kReleaseMode) {
      // 릴리즈 모드에서는 설정에 따라 로그 출력
      if (enableLogInRelease) {
        print(message);
      }
    } else {
      // 디버그 모드에서는 항상 출력
      debugPrint(message);
    }
  }
  
  /// 심각한 오류 로그만 출력하는 함수
  /// 심각한 오류는 릴리즈 모드에서도 출력
  static void error(String message) {
    if (kReleaseMode) {
      // 중요 오류는 릴리즈 모드에서도 출력
      print('ERROR: $message');
    } else {
      debugPrint('ERROR: $message');
    }
  }
  
  /// 현재 모드 확인
  static bool isReleaseMode() {
    return kReleaseMode;
  }
} 