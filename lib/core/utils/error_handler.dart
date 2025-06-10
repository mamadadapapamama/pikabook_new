import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// 에러 유형 열거형
enum ErrorType {
  network,           // 인터넷 연결 문제
  serverConnection,  // 서버 연결 불안정
  timeout,          // 타임아웃
  general,          // 일반적인 에러
}

/// 에러 처리 유틸리티 클래스
class ErrorHandler {
  /// 에러 객체나 메시지를 분석하여 적절한 에러 유형 반환
  static ErrorType analyzeError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (kDebugMode) {
      debugPrint('🔍 [ErrorHandler] 에러 분석: $errorString');
    }
    
    // 네트워크 관련 키워드 체크
    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('internet') ||
        errorString.contains('dns') ||
        errorString.contains('unreachable') ||
        errorString.contains('no address associated')) {
      return ErrorType.network;
    }
    
    // 서버 연결 관련 키워드 체크
    if (errorString.contains('server') ||
        errorString.contains('unavailable') ||
        errorString.contains('service') ||
        errorString.contains('backend') ||
        errorString.contains('gateway') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504')) {
      return ErrorType.serverConnection;
    }
    
    // 타임아웃 관련 키워드 체크
    if (errorString.contains('timeout') ||
        errorString.contains('deadline') ||
        errorString.contains('exceeded')) {
      return ErrorType.timeout;
    }
    
    // 기본값은 일반적인 에러
    return ErrorType.general;
  }
  
  /// 에러 유형에 따른 사용자 친화적 메시지 반환
  static String getErrorMessage(ErrorType errorType) {
    switch (errorType) {
      case ErrorType.network:
        return '인터넷 연결 상태를 확인해주세요.';
      case ErrorType.serverConnection:
        return '서버 연결이 불안정해요. 잠시 후 다시 시도해주세요.';
      case ErrorType.timeout:
        return '처리 시간이 너무 오래 걸리고 있어요. 다시 시도해주세요.';
      case ErrorType.general:
        return '일시적인 문제가 발생했어요. 잠시 후 다시 시도해주세요.';
    }
  }
  
  /// 에러를 분석하고 바로 메시지 반환
  static String getMessageFromError(dynamic error) {
    final errorType = analyzeError(error);
    return getErrorMessage(errorType);
  }
  
  /// 스낵바로 에러 메시지 표시
  static void showErrorSnackBar(BuildContext context, dynamic error) {
    if (!context.mounted) return;
    
    final message = getMessageFromError(error);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '확인',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
    
    if (kDebugMode) {
      debugPrint('📢 [ErrorHandler] 스낵바 메시지 표시: $message');
    }
  }
  
  /// 타임아웃 단계별 메시지 반환
  static String getTimeoutMessage(int elapsedSeconds) {
    if (elapsedSeconds >= 10 && elapsedSeconds < 20) {
      return '처리 시간이 평소보다 오래 걸리고 있어요. (약 ${elapsedSeconds}초 경과)';
    } else if (elapsedSeconds >= 20 && elapsedSeconds < 30) {
      return '다시 시도 중입니다…';
    } else if (elapsedSeconds >= 30) {
      return '문제가 지속되고 있어요. 잠시 뒤에 다시 시도해 주세요.';
    }
    return '처리 중입니다...';
  }
} 