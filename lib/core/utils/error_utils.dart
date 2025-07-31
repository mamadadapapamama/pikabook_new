/// 🚨 오류 처리 유틸리티 클래스
/// 기존 ErrorHandler를 확장하여 더 편리한 오류 처리 기능을 제공합니다.

import 'package:flutter/material.dart';
import 'error_handler.dart';
import 'logging_utils.dart';
import 'string_utils.dart';

/// 🔧 통합 오류 처리 유틸리티
class ErrorUtils {
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 오류 분석 및 분류
  // ────────────────────────────────────────────────────────────────────────
  
  /// 오류 타입 빠른 분석 (ErrorHandler 기반)
  static ErrorType analyzeErrorType(dynamic error) {
    return ErrorHandler.analyzeError(error);
  }
  
  /// 오류가 네트워크 관련인지 확인
  static bool isNetworkError(dynamic error) {
    return analyzeErrorType(error) == ErrorType.network;
  }
  
  /// 오류가 서버 관련인지 확인
  static bool isServerError(dynamic error) {
    final errorType = analyzeErrorType(error);
    return errorType == ErrorType.serverConnection || 
           errorType == ErrorType.timeout;
  }
  
  /// 오류가 권한 관련인지 확인
  static bool isPermissionError(dynamic error) {
    final errorType = analyzeErrorType(error);
    return errorType == ErrorType.unauthorized || 
           errorType == ErrorType.forbidden ||
           errorType == ErrorType.permission;
  }
  
  /// 오류가 사용자가 해결할 수 있는 오류인지 확인
  static bool isUserRecoverableError(dynamic error) {
    final errorType = analyzeErrorType(error);
    return errorType == ErrorType.network ||
           errorType == ErrorType.timeout ||
           errorType == ErrorType.rateLimited;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 📱 사용자 친화적 오류 메시지
  // ────────────────────────────────────────────────────────────────────────
  
  /// 오류에 대한 사용자 친화적 메시지 생성
  static String getUserFriendlyMessage(dynamic error, [ErrorContext? context]) {
    return ErrorHandler.getMessageFromError(error, context);
  }
  
  /// 오류에 대한 간단한 메시지 생성
  static String getSimpleMessage(dynamic error) {
    final errorType = analyzeErrorType(error);
    
    switch (errorType) {
      case ErrorType.network:
        return '인터넷 연결을 확인해주세요';
      case ErrorType.serverConnection:
      case ErrorType.timeout:
        return '일시적인 문제가 발생했습니다';
      case ErrorType.unauthorized:
        return '로그인이 필요합니다';
      case ErrorType.forbidden:
        return '권한이 없습니다';
      case ErrorType.notFound:
        return '요청한 정보를 찾을 수 없습니다';
      case ErrorType.rateLimited:
        return '잠시 후 다시 시도해주세요';
      default:
        return '오류가 발생했습니다';
    }
  }
  
  /// 상황별 오류 메시지 생성
  static String getContextualMessage(dynamic error, String action) {
    final simpleMessage = getSimpleMessage(error);
    return '$action 중 $simpleMessage';
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔔 사용자 알림 헬퍼들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 스낵바로 오류 표시 (ErrorHandler 기반)
  static void showErrorSnackBar(BuildContext context, dynamic error, [ErrorContext? errorContext]) {
    if (!context.mounted) return;
    ErrorHandler.showErrorSnackBar(context, error, errorContext);
  }
  
  /// 간단한 오류 스낵바 표시
  static void showSimpleErrorSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  /// 재시도 가능한 오류 스낵바 표시
  static void showRetryableErrorSnackBar(
    BuildContext context, 
    String message, 
    VoidCallback onRetry,
  ) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '다시 시도',
          textColor: Colors.white,
          onPressed: onRetry,
        ),
      ),
    );
  }
  
  /// 오류 다이얼로그 표시
  static Future<void> showErrorDialog(
    BuildContext context, {
    String? title,
    required String message,
    String? buttonText,
    VoidCallback? onRetry,
  }) async {
    if (!context.mounted) return;
    
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: title != null ? Text(title) : null,
          content: Text(message),
          actions: [
            if (onRetry != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onRetry();
                },
                child: const Text('다시 시도'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(buttonText ?? '확인'),
            ),
          ],
        );
      },
    );
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🚀 try-catch 래퍼들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 안전한 비동기 실행 (오류 로깅 포함)
  static Future<T?> safeExecuteAsync<T>(
    Future<T> Function() operation, {
    String? operationName,
    T? defaultValue,
    bool showUserError = false,
    BuildContext? context,
    ErrorContext? errorContext,
  }) async {
    try {
      LoggingUtils.debugIf(
        operationName != null,
        '🔄 비동기 실행 시작: $operationName',
      );
      
      final result = await operation();
      
      LoggingUtils.debugIf(
        operationName != null,
        '✅ 비동기 실행 완료: $operationName',
      );
      
      return result;
    } catch (error, stackTrace) {
      final errorMessage = operationName != null 
          ? '$operationName 실행 중 오류 발생'
          : '비동기 실행 중 오류 발생';
      
      LoggingUtils.error(
        '$errorMessage: $error',
        tag: 'ErrorUtils',
        error: error,
      );
      
      if (showUserError && context != null && context.mounted) {
        showErrorSnackBar(context, error, errorContext);
      }
      
      return defaultValue;
    }
  }
  
  /// 안전한 동기 실행 (오류 로깅 포함)
  static T? safeExecute<T>(
    T Function() operation, {
    String? operationName,
    T? defaultValue,
    bool logError = true,
  }) {
    try {
      LoggingUtils.debugIf(
        operationName != null,
        '🔄 동기 실행 시작: $operationName',
      );
      
      final result = operation();
      
      LoggingUtils.debugIf(
        operationName != null,
        '✅ 동기 실행 완료: $operationName',
      );
      
      return result;
    } catch (error, stackTrace) {
      if (logError) {
        final errorMessage = operationName != null 
            ? '$operationName 실행 중 오류 발생'
            : '동기 실행 중 오류 발생';
        
        LoggingUtils.error(
          '$errorMessage: $error',
          tag: 'ErrorUtils',
          error: error,
        );
      }
      
      return defaultValue;
    }
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 📊 오류 통계 및 분석
  // ────────────────────────────────────────────────────────────────────────
  
  static final Map<String, int> _errorCounts = {};
  static final Map<String, DateTime> _lastErrorTimes = {};
  
  /// 오류 발생 기록
  static void recordError(String errorKey, [dynamic error]) {
    _errorCounts[errorKey] = (_errorCounts[errorKey] ?? 0) + 1;
    _lastErrorTimes[errorKey] = DateTime.now();
    
    LoggingUtils.debug(
      '📊 오류 기록: $errorKey (총 ${_errorCounts[errorKey]}회)',
      tag: 'ErrorStats',
    );
  }
  
  /// 특정 오류의 발생 횟수 조회
  static int getErrorCount(String errorKey) {
    return _errorCounts[errorKey] ?? 0;
  }
  
  /// 특정 오류의 마지막 발생 시간 조회
  static DateTime? getLastErrorTime(String errorKey) {
    return _lastErrorTimes[errorKey];
  }
  
  /// 오류 통계 초기화
  static void clearErrorStats() {
    _errorCounts.clear();
    _lastErrorTimes.clear();
    LoggingUtils.debug('📊 오류 통계 초기화됨', tag: 'ErrorStats');
  }
  
  /// 오류 통계 요약 조회
  static Map<String, dynamic> getErrorStatsSummary() {
    return {
      'totalErrors': _errorCounts.values.fold(0, (sum, count) => sum + count),
      'uniqueErrors': _errorCounts.length,
      'errorCounts': Map<String, int>.from(_errorCounts),
      'recentErrors': _lastErrorTimes.entries
          .where((entry) => DateTime.now().difference(entry.value).inMinutes < 60)
          .map((entry) => entry.key)
          .toList(),
    };
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 특화된 오류 처리 메서드들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 네트워크 오류 처리
  static void handleNetworkError(
    dynamic error, {
    BuildContext? context,
    VoidCallback? onRetry,
    String? customMessage,
  }) {
    recordError('network_error', error);
    
    final message = customMessage ?? getSimpleMessage(error);
    
    if (context != null && context.mounted) {
      if (onRetry != null) {
        showRetryableErrorSnackBar(context, message, onRetry);
      } else {
        showSimpleErrorSnackBar(context, message);
      }
    }
  }
  
  /// API 오류 처리
  static void handleApiError(
    dynamic error, {
    BuildContext? context,
    String? operation,
    ErrorContext? errorContext,
  }) {
    final operationStr = operation ?? 'API 호출';
    recordError('api_error_$operationStr', error);
    
    LoggingUtils.api('❌ $operationStr 실패: $error', tag: 'API');
    
    if (context != null && context.mounted) {
      showErrorSnackBar(context, error, errorContext);
    }
  }
  
  /// 데이터베이스 오류 처리
  static void handleDatabaseError(
    dynamic error, {
    String? operation,
    bool showUserMessage = false,
    BuildContext? context,
  }) {
    final operationStr = operation ?? '데이터베이스 작업';
    recordError('database_error_$operationStr', error);
    
    LoggingUtils.database('❌ $operationStr 실패: $error', tag: 'Database');
    
    if (showUserMessage && context != null && context.mounted) {
      showSimpleErrorSnackBar(context, '데이터 처리 중 오류가 발생했습니다');
    }
  }
}

/// 🎯 Future 확장 메서드들
extension FutureErrorHandling<T> on Future<T> {
  /// 안전한 await (오류 시 기본값 반환)
  Future<T?> safeAwait({T? defaultValue}) async {
    return ErrorUtils.safeExecuteAsync(() => this, defaultValue: defaultValue);
  }
  
  /// 사용자 친화적 오류 처리와 함께 await
  Future<T?> awaitWithUserError(
    BuildContext context, {
    T? defaultValue,
    ErrorContext? errorContext,
  }) async {
    return ErrorUtils.safeExecuteAsync(
      () => this,
      defaultValue: defaultValue,
      showUserError: true,
      context: context,
      errorContext: errorContext,
    );
  }
}