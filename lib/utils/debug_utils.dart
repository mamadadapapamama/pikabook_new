import 'package:flutter/foundation.dart';

/// 디버그 로그 유틸리티
/// 릴리즈 모드에서 로그를 관리하기 위한 클래스
class DebugUtils {
  /// 릴리즈 모드에서 로그 출력 여부
  static bool enableLogInRelease = false;
  
  /// 심사용 모드 - true일 경우 모든 모드에서 로그 비활성화
  static bool reviewMode = true;
  
  /// 안전한 로그 출력 함수
  /// 릴리즈 모드에서는 특별히 설정된 경우만 출력
  static void log(String message) {
    // 심사 모드이거나 릴리즈 모드일 경우 출력하지 않음
    if (reviewMode || kReleaseMode) {
      return;
    }
    
    // 성능 측정 관련 로그인 경우 필터링
    if (_isPerformanceLog(message)) {
      return;
    }
    
    // 그 외의 경우 디버그 출력
    debugPrint(message);
  }
  
  /// 심각한 오류 로그만 출력하는 함수
  /// 심각한 오류는 릴리즈 모드에서도 출력
  static void error(String message) {
    // 심사 모드일 경우 출력하지 않음
    if (reviewMode) {
      return;
    }
    
    if (kReleaseMode) {
      // 릴리즈 모드에서도 심각한 오류는 기록할 수 있게 설정 가능
      if (enableLogInRelease) {
        print('ERROR: $message');
      }
    } else {
      debugPrint('ERROR: $message');
    }
  }
  
  /// 현재 모드 확인
  static bool isReleaseMode() {
    return kReleaseMode;
  }
  
  /// 성능 측정 관련 로그인지 확인
  static bool _isPerformanceLog(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('ms') ||
           lowerMessage.contains('timer') ||
           lowerMessage.contains('duration') ||
           lowerMessage.contains('elapsed') ||
           lowerMessage.contains('benchmark') ||
           lowerMessage.contains('performance') ||
           lowerMessage.contains('stopwatch') ||
           lowerMessage.contains('frame');
  }
} 